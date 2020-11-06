{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.Scala.Backend exposing (..)

import Dict
import List.Extra as ListExtra
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (FQName(..), fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.SDK.Customization as Customization exposing (Customization(..), caseClassesToAnnotate, getAnnotations)
import Morphir.Scala.AST as Scala exposing (Annotated, MemberDecl(..))
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Set exposing (Set)


type alias Options =
    {}


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Distribution.Library packagePath dependencies packageDef ->
            mapPackageDefinition opt distro packagePath packageDef


mapPackageDefinition : Options -> Distribution -> Package.PackageName -> Package.Definition ta (Type ()) -> FileMap
mapPackageDefinition opt distribution packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                mapModuleDefinition opt distribution packagePath modulePath moduleImpl
                    |> List.map
                        (\compilationUnit ->
                            let
                                fileContent =
                                    compilationUnit
                                        |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                            in
                            ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                        )
            )
        |> Dict.fromList


mapFQNameToPathAndName : FQName -> ( Scala.Path, Name )
mapFQNameToPathAndName (FQName packagePath modulePath localName) =
    let
        scalaModulePath =
            case modulePath |> List.reverse of
                [] ->
                    []

                lastName :: reverseModulePath ->
                    List.concat
                        [ packagePath
                            |> List.map (Name.toCamelCase >> String.toLower)
                        , reverseModulePath
                            |> List.reverse
                            |> List.map (Name.toCamelCase >> String.toLower)
                        , [ lastName
                                |> Name.toTitleCase
                          ]
                        ]
    in
    ( scalaModulePath
    , localName
    )


mapFQNameToTypeRef : FQName -> Scala.Type
mapFQNameToTypeRef fQName =
    let
        ( path, name ) =
            mapFQNameToPathAndName fQName
    in
    Scala.TypeRef path (name |> Name.toTitleCase)


maptypeMember : Maybe Customization -> Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> List Scala.MemberDecl
maptypeMember annotations currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) =
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeParams (Type.Record _ fields) ->
            [ Scala.MemberTypeDecl
                (Scala.Class
                    { modifiers = [ Scala.Case ]
                    , name = typeName |> Name.toTitleCase
                    , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                    , ctorArgs =
                        fields
                            |> List.map
                                (\field ->
                                    { modifiers = []
                                    , tpe = mapType field.tpe
                                    , name = field.name |> Name.toCamelCase
                                    , defaultValue = Nothing
                                    }
                                )
                            |> List.singleton
                    , extends = []
                    , members =
                        mapFunctionsToMethods currentPackagePath
                            currentModulePath
                            typeName
                            (accessControlledModuleDef.value.values
                                |> Dict.toList
                                |> List.map
                                    (\( valueName, valueDef ) ->
                                        ( valueName, valueDef.value |> Value.definitionToSpecification )
                                    )
                            )
                    }
                )
            ]

        Type.TypeAliasDefinition typeParams typeExp ->
            [ Scala.TypeAlias
                { alias =
                    typeName |> Name.toTitleCase
                , typeArgs =
                    typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                , tpe =
                    mapType typeExp
                }
            ]

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            mapCustomTypeDefinition
                annotations
                currentPackagePath
                currentModulePath
                accessControlledModuleDef.value
                typeName
                typeParams
                accessControlledCtors


mapModuleDefinition : Options -> Distribution -> Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List Scala.CompilationUnit
mapModuleDefinition opt distribution currentPackagePath currentModulePath accessControlledModuleDef =
    let
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        typeMembers : List Scala.MemberDecl
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\types ->
                        maptypeMember Nothing currentPackagePath currentModulePath accessControlledModuleDef types
                    )

        functionMembers : List Scala.MemberDecl
        functionMembers =
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledValueDef ) ->
                        [ Scala.FunctionDecl
                            { modifiers =
                                case accessControlledValueDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        [ Scala.Private Nothing ]
                            , name =
                                valueName |> Name.toCamelCase
                            , typeArgs =
                                []
                            , args =
                                if List.isEmpty accessControlledValueDef.value.inputTypes then
                                    []

                                else
                                    [ accessControlledValueDef.value.inputTypes
                                        |> List.map
                                            (\( argName, a, argType ) ->
                                                { modifiers = []
                                                , tpe = mapType argType
                                                , name = argName |> Name.toCamelCase
                                                , defaultValue = Nothing
                                                }
                                            )
                                    ]
                            , returnType =
                                Just (mapType accessControlledValueDef.value.outputType)
                            , body =
                                Just (mapFunctionBody distribution accessControlledValueDef.value.body)
                            }
                        ]
                    )

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Scala.Annotated Nothing <|
                        Scala.Object
                            { modifiers =
                                case accessControlledModuleDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        [ Scala.Private
                                            (currentPackagePath
                                                |> ListExtra.last
                                                |> Maybe.map (Name.toCamelCase >> String.toLower)
                                            )
                                        ]
                            , name =
                                moduleName |> Name.toTitleCase
                            , members =
                                List.append typeMembers functionMembers
                            , extends =
                                []
                            , body = Nothing
                            }
                    )
                ]
            }
    in
    [ moduleUnit ]


mapCustomTypeDefinition : Maybe Customization -> Package.PackageName -> Path -> Module.Definition ta (Type ()) -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List Scala.MemberDecl
mapCustomTypeDefinition annotations currentPackagePath currentModulePath moduleDef typeName typeParams accessControlledCtors =
    let
        caseClass name args extends =
            if List.isEmpty args then
                Scala.Object
                    { modifiers = [ Scala.Case ]
                    , name = name |> Name.toTitleCase
                    , extends = extends
                    , members = []
                    , body = Nothing
                    }

            else
                Scala.Class
                    { modifiers = [ Scala.Case ]
                    , name = name |> Name.toTitleCase
                    , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                    , ctorArgs =
                        args
                            |> List.map
                                (\( argName, argType ) ->
                                    { modifiers = []
                                    , tpe = mapType argType
                                    , name = argName |> Name.toCamelCase
                                    , defaultValue = Nothing
                                    }
                                )
                            |> List.singleton
                    , extends = extends
                    , members = []
                    }

        parentTraitRef =
            mapFQNameToTypeRef (FQName currentPackagePath currentModulePath typeName)

        sealedTraitHierarchy =
            List.concat
                [ [ Scala.Trait
                        { modifiers = [ Scala.Sealed ]
                        , name = typeName |> Name.toTitleCase
                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                        , extends = []
                        , members =
                            mapFunctionsToMethods currentPackagePath
                                currentModulePath
                                typeName
                                (moduleDef.values
                                    |> Dict.toList
                                    |> List.map
                                        (\( valueName, valueDef ) ->
                                            ( valueName, valueDef.value |> Value.definitionToSpecification )
                                        )
                                )
                        }
                  ]
                , accessControlledCtors.value
                    |> List.map
                        (\(Type.Constructor ctorName ctorArgs) ->
                            caseClass ctorName
                                ctorArgs
                                (if List.isEmpty typeParams then
                                    [ parentTraitRef ]

                                 else
                                    [ Scala.TypeApply parentTraitRef (typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)) ]
                                )
                        )
                ]
    in
    case accessControlledCtors.value of
        [ Type.Constructor ctorName ctorArgs ] ->
            if ctorName == typeName then
                [ Scala.MemberTypeDecl
                    (caseClass ctorName ctorArgs [])
                ]

            else
                sealedTraitHierarchy
                    |> List.map
                        (\sealedTrait ->
                            Scala.MemberTypeDecl sealedTrait
                        )

        _ ->
            sealedTraitHierarchy
                |> List.map
                    (\sealedTrait ->
                        Scala.AnnotatedMemberDecl (getAnnotations annotations (caseClassesToAnnotate annotations sealedTraitHierarchy) (Scala.MemberTypeDecl sealedTrait))
                    )


{-| Collect functions where the last input argument is this type and turn them into methods on the type.
-}
mapFunctionsToMethods : Path -> Path -> Name -> List ( Name, Value.Specification ta ) -> List Scala.MemberDecl
mapFunctionsToMethods currentPackageName currentModuleName currentTypeName valueSpecifications =
    valueSpecifications
        |> List.filterMap
            (\( valueName, valueSpec ) ->
                case List.reverse valueSpec.inputs of
                    [] ->
                        -- if this is a value (function with no arguments) then we don't turn it into a method
                        Nothing

                    ( _, lastInputType ) :: restOfInputsReversed ->
                        -- if the last argument type of the function is
                        let
                            inputs =
                                List.reverse restOfInputsReversed
                        in
                        case lastInputType of
                            Type.Reference _ fQName [] ->
                                if fQName == FQName currentPackageName currentModuleName currentTypeName then
                                    Just
                                        (FunctionDecl
                                            { modifiers = []
                                            , name = valueName |> Name.toCamelCase
                                            , typeArgs = []
                                            , args =
                                                if List.isEmpty inputs then
                                                    []

                                                else
                                                    [ inputs
                                                        |> List.map
                                                            (\( argName, argType ) ->
                                                                { modifiers = []
                                                                , tpe = mapType argType
                                                                , name = argName |> Name.toCamelCase
                                                                , defaultValue = Nothing
                                                                }
                                                            )
                                                    ]
                                            , returnType =
                                                Just (mapType valueSpec.output)
                                            , body =
                                                let
                                                    ( path, name ) =
                                                        mapFQNameToPathAndName (FQName currentPackageName currentModuleName valueName)
                                                in
                                                Just
                                                    (Scala.Apply (Scala.Ref path (name |> Name.toCamelCase))
                                                        (List.append
                                                            (inputs
                                                                |> List.map
                                                                    (\( argName, _ ) ->
                                                                        Scala.ArgValue Nothing (Scala.Variable (argName |> Name.toCamelCase))
                                                                    )
                                                            )
                                                            [ Scala.ArgValue Nothing Scala.This ]
                                                        )
                                                    )
                                            }
                                        )

                                else
                                    Nothing

                            _ ->
                                Nothing
            )


mapType : Type a -> Scala.Type
mapType tpe =
    case tpe of
        Type.Variable a name ->
            Scala.TypeVar (name |> Name.toTitleCase)

        Type.Reference a fQName argTypes ->
            let
                typeRef =
                    mapFQNameToTypeRef fQName
            in
            if List.isEmpty argTypes then
                typeRef

            else
                Scala.TypeApply typeRef (argTypes |> List.map mapType)

        Type.Tuple a elemTypes ->
            Scala.TupleType (elemTypes |> List.map mapType)

        Type.Record a fields ->
            Scala.StructuralType
                (fields
                    |> List.map
                        (\field ->
                            Scala.FunctionDecl
                                { modifiers = []
                                , name = field.name |> Name.toCamelCase
                                , typeArgs = []
                                , args = []
                                , returnType = Just (mapType field.tpe)
                                , body = Nothing
                                }
                        )
                )

        Type.ExtensibleRecord a argName fields ->
            Scala.StructuralType
                (fields
                    |> List.map
                        (\field ->
                            Scala.FunctionDecl
                                { modifiers = []
                                , name = field.name |> Name.toCamelCase
                                , typeArgs = []
                                , args = []
                                , returnType = Just (mapType field.tpe)
                                , body = Nothing
                                }
                        )
                )

        Type.Function a argType returnType ->
            Scala.FunctionType (mapType argType) (mapType returnType)

        Type.Unit a ->
            Scala.TypeRef [ "scala" ] "Unit"


mapFunctionBody : Distribution -> Value ta (Type ()) -> Scala.Value
mapFunctionBody distribution val =
    let
        mapValue : Value ta (Type ()) -> Scala.Value
        mapValue value =
            case value of
                Literal tpe literal ->
                    let
                        wrap : List String -> String -> Scala.Lit -> Scala.Value
                        wrap modulePath moduleName lit =
                            Scala.Apply
                                (Scala.Ref modulePath moduleName)
                                [ Scala.ArgValue Nothing (Scala.Literal lit) ]
                    in
                    case literal of
                        BoolLiteral v ->
                            wrap [ "morphir", "sdk", "Basics" ] "Bool" (Scala.BooleanLit v)

                        CharLiteral v ->
                            wrap [ "morphir", "sdk", "Char" ] "Char" (Scala.CharacterLit v)

                        StringLiteral v ->
                            wrap [ "morphir", "sdk", "String" ] "String" (Scala.StringLit v)

                        IntLiteral v ->
                            case tpe of
                                Type.Reference () fQName [] ->
                                    if fQName == fqn "Morphir.SDK" "Basics" "Float" then
                                        wrap [ "morphir", "sdk", "Basics" ] "Float" (Scala.IntegerLit v)

                                    else
                                        wrap [ "morphir", "sdk", "Basics" ] "Int" (Scala.IntegerLit v)

                                _ ->
                                    wrap [ "morphir", "sdk", "Basics" ] "Int" (Scala.IntegerLit v)

                        FloatLiteral v ->
                            wrap [ "morphir", "sdk", "Basics" ] "Float" (Scala.FloatLit v)

                Constructor a fQName ->
                    let
                        ( path, name ) =
                            mapFQNameToPathAndName fQName
                    in
                    Scala.Ref path
                        (name |> Name.toTitleCase)

                Tuple a elemValues ->
                    Scala.Tuple
                        (elemValues |> List.map mapValue)

                List a itemValues ->
                    Scala.Apply
                        (Scala.Ref [ "morphir", "sdk" ] "List")
                        (itemValues
                            |> List.map mapValue
                            |> List.map (Scala.ArgValue Nothing)
                        )

                Record a fieldValues ->
                    Scala.StructuralValue
                        (fieldValues
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    ( fieldName |> Name.toCamelCase, mapValue fieldValue )
                                )
                        )

                Variable a name ->
                    Scala.Variable (name |> Name.toCamelCase)

                Reference a fQName ->
                    let
                        ( path, name ) =
                            mapFQNameToPathAndName fQName
                    in
                    Scala.Ref path (name |> Name.toCamelCase)

                Field a subjectValue fieldName ->
                    Scala.Select (mapValue subjectValue) (fieldName |> Name.toCamelCase)

                FieldFunction a fieldName ->
                    Scala.Select Scala.Wildcard (fieldName |> Name.toCamelCase)

                Apply a fun arg ->
                    let
                        ( bottomFun, args ) =
                            Value.uncurryApply fun arg
                    in
                    Scala.Apply (mapValue bottomFun)
                        (args
                            |> List.map
                                (\argValue ->
                                    Scala.ArgValue Nothing (mapValue argValue)
                                )
                        )

                Lambda a argPattern bodyValue ->
                    case argPattern of
                        AsPattern _ (WildcardPattern _) alias ->
                            Scala.Lambda [ alias |> Name.toCamelCase ] (mapValue bodyValue)

                        _ ->
                            Scala.MatchCases [ ( mapPattern argPattern, mapValue bodyValue ) ]

                LetDefinition _ _ _ _ ->
                    let
                        flattenLetDef : Value ta (Type ()) -> ( List ( Name, Value.Definition ta (Type ()) ), Value ta (Type ()) )
                        flattenLetDef v =
                            case v of
                                LetDefinition a dName d inV ->
                                    let
                                        ( nestedDefs, nestedInValue ) =
                                            flattenLetDef inV
                                    in
                                    ( ( dName, d ) :: nestedDefs, nestedInValue )

                                _ ->
                                    ( [], v )

                        ( defs, finalInValue ) =
                            flattenLetDef value
                    in
                    Scala.Block
                        (defs
                            |> List.map
                                (\( defName, def ) ->
                                    if List.isEmpty def.inputTypes then
                                        Scala.ValueDecl
                                            { modifiers = []
                                            , pattern = Scala.NamedMatch (defName |> Name.toCamelCase)
                                            , valueType = Just (mapType def.outputType)
                                            , value = mapValue def.body
                                            }

                                    else
                                        Scala.FunctionDecl
                                            { modifiers = []
                                            , name = defName |> Name.toCamelCase
                                            , typeArgs = []
                                            , args =
                                                [ def.inputTypes
                                                    |> List.map
                                                        (\( argName, _, argType ) ->
                                                            { modifiers = []
                                                            , tpe = mapType argType
                                                            , name = argName |> Name.toCamelCase
                                                            , defaultValue = Nothing
                                                            }
                                                        )
                                                ]
                                            , returnType =
                                                Just (mapType def.outputType)
                                            , body =
                                                Just (mapValue def.body)
                                            }
                                )
                        )
                        (mapValue finalInValue)

                LetRecursion a defs inValue ->
                    Scala.Block
                        (defs
                            |> Dict.toList
                            |> List.map
                                (\( defName, def ) ->
                                    Scala.FunctionDecl
                                        { modifiers = []
                                        , name = defName |> Name.toCamelCase
                                        , typeArgs = []
                                        , args =
                                            if List.isEmpty def.inputTypes then
                                                []

                                            else
                                                [ def.inputTypes
                                                    |> List.map
                                                        (\( argName, _, argType ) ->
                                                            { modifiers = []
                                                            , tpe = mapType argType
                                                            , name = argName |> Name.toCamelCase
                                                            , defaultValue = Nothing
                                                            }
                                                        )
                                                ]
                                        , returnType =
                                            Just (mapType def.outputType)
                                        , body =
                                            Just (mapValue def.body)
                                        }
                                )
                        )
                        (mapValue inValue)

                Destructure a bindPattern bindValue inValue ->
                    Scala.Block
                        [ Scala.ValueDecl
                            { modifiers = []
                            , pattern = mapPattern bindPattern
                            , valueType = Nothing
                            , value = mapValue bindValue
                            }
                        ]
                        (mapValue inValue)

                IfThenElse a condValue thenValue elseValue ->
                    Scala.IfElse (mapValue condValue) (mapValue thenValue) (mapValue elseValue)

                PatternMatch a onValue cases ->
                    Scala.Match (mapValue onValue)
                        (cases
                            |> List.map
                                (\( casePattern, caseValue ) ->
                                    ( mapPattern casePattern, mapValue caseValue )
                                )
                            |> Scala.MatchCases
                        )

                UpdateRecord a subjectValue fieldUpdates ->
                    Scala.Apply
                        (Scala.Select (mapValue subjectValue) "copy")
                        (fieldUpdates
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    Scala.ArgValue
                                        (Just (fieldName |> Name.toCamelCase))
                                        (mapValue fieldValue)
                                )
                        )

                Unit a ->
                    Scala.Unit
    in
    mapValue val


mapPattern : Pattern a -> Scala.Pattern
mapPattern pattern =
    case pattern of
        WildcardPattern a ->
            Scala.WildcardMatch

        AsPattern a (WildcardPattern _) alias ->
            Scala.NamedMatch (alias |> Name.toCamelCase)

        AsPattern a aliasedPattern alias ->
            Scala.AliasedMatch (alias |> Name.toCamelCase) (mapPattern aliasedPattern)

        TuplePattern a itemPatterns ->
            Scala.TupleMatch (itemPatterns |> List.map mapPattern)

        ConstructorPattern a fQName argPatterns ->
            let
                ( path, name ) =
                    mapFQNameToPathAndName fQName
            in
            Scala.UnapplyMatch path
                (name |> Name.toTitleCase)
                (argPatterns
                    |> List.map mapPattern
                )

        EmptyListPattern a ->
            Scala.EmptyListMatch

        HeadTailPattern a headPattern tailPattern ->
            Scala.HeadTailMatch
                (mapPattern headPattern)
                (mapPattern tailPattern)

        LiteralPattern a literal ->
            let
                map l =
                    case l of
                        BoolLiteral v ->
                            Scala.BooleanLit v

                        CharLiteral v ->
                            Scala.CharacterLit v

                        StringLiteral v ->
                            Scala.StringLit v

                        IntLiteral v ->
                            Scala.IntegerLit v

                        FloatLiteral v ->
                            Scala.FloatLit v
            in
            Scala.LiteralMatch (map literal)

        UnitPattern a ->
            Scala.WildcardMatch


reservedValueNames : Set String
reservedValueNames =
    Set.fromList
        -- we cannot use any method names in java.lamg.Object because values are represented as functions/values in a Scala object
        [ "clone"
        , "equals"
        , "finalize"
        , "getClass"
        , "hashCode"
        , "notify"
        , "notifyAll"
        , "toString"
        , "wait"
        ]
