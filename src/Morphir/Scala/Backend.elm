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


module Morphir.Scala.Backend exposing
    ( mapDistribution, mapFunctionBody, mapType, mapTypeMember
    , Options
    )

{-| This module encapsulates the Scala backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated. The consumer is responsible for getting the input IR and saving the output
to the file-system.

@docs mapDistribution, mapFunctionBody, mapType, mapTypeMember


# Options

@docs Options

-}

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
import Morphir.Scala.AST as Scala exposing (Annotated, MemberDecl(..))
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Set exposing (Set)


{-| Placeholder for code generator options. Currently empty.
-}
type alias Options =
    {}


{-| Entry point for the Scala backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
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


{-| Map a module level type declaration in Morphir to a Scala member declaration.
-}
mapTypeMember : Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> ( Name, AccessControlled (Documented (Type.Definition ta)) ) -> List (Scala.Annotated Scala.MemberDecl)
mapTypeMember currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) =
    case accessControlledDocumentedTypeDef.value.value of
        Type.TypeAliasDefinition typeParams (Type.Record _ fields) ->
            [ Scala.withoutAnnotation
                (Scala.MemberTypeDecl
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
                        , members = []
                        }
                    )
                )
            ]

        Type.TypeAliasDefinition typeParams typeExp ->
            [ Scala.withoutAnnotation
                (Scala.TypeAlias
                    { alias =
                        typeName |> Name.toTitleCase
                    , typeArgs =
                        typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                    , tpe =
                        mapType typeExp
                    }
                )
            ]

        Type.CustomTypeDefinition typeParams accessControlledCtors ->
            mapCustomTypeDefinition
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

        typeMembers : List (Scala.Annotated Scala.MemberDecl)
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\types ->
                        mapTypeMember currentPackagePath currentModulePath accessControlledModuleDef types
                    )

        functionMembers : List (Scala.Annotated Scala.MemberDecl)
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
                                    accessControlledValueDef.value.inputTypes
                                        |> List.map
                                            (\( argName, a, argType ) ->
                                                [ { modifiers = []
                                                  , tpe = mapType argType
                                                  , name = argName |> Name.toCamelCase
                                                  , defaultValue = Nothing
                                                  }
                                                ]
                                            )
                            , returnType =
                                Just (mapType accessControlledValueDef.value.outputType)
                            , body =
                                Just (mapFunctionBody distribution accessControlledValueDef.value.body)
                            }
                        ]
                    )
                |> List.map Scala.withoutAnnotation

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Scala.Annotated []
                        (Scala.Object
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
                    )
                ]
            }
    in
    [ moduleUnit ]


mapCustomTypeDefinition : Package.PackageName -> Path -> Module.Definition ta (Type ()) -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List (Scala.Annotated Scala.MemberDecl)
mapCustomTypeDefinition currentPackagePath currentModulePath moduleDef typeName typeParams accessControlledCtors =
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

        sealedTraitHierarchy : List Scala.TypeDecl
        sealedTraitHierarchy =
            List.concat
                [ [ Scala.Trait
                        { modifiers = [ Scala.Sealed ]
                        , name = typeName |> Name.toTitleCase
                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> Scala.TypeVar)
                        , extends = []
                        , members = []
                        }
                  ]
                , accessControlledCtors.value
                    |> Dict.toList
                    |> List.map
                        (\( ctorName, ctorArgs ) ->
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
    case accessControlledCtors.value |> Dict.toList of
        [ ( ctorName, ctorArgs ) ] ->
            if ctorName == typeName then
                [ Scala.withoutAnnotation
                    (Scala.MemberTypeDecl
                        (caseClass ctorName ctorArgs [])
                    )
                ]

            else
                sealedTraitHierarchy
                    |> List.map (Scala.MemberTypeDecl >> Scala.withoutAnnotation)

        _ ->
            sealedTraitHierarchy
                |> List.map (Scala.MemberTypeDecl >> Scala.withoutAnnotation)


{-| Map a Morphir type to a Scala type.
-}
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


{-| Generate Scala for a Morphir function body.
-}
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
                            Scala.Literal (Scala.BooleanLit v)

                        CharLiteral v ->
                            wrap [ "morphir", "sdk", "Char" ] "from" (Scala.CharacterLit v)

                        StringLiteral v ->
                            Scala.Literal (Scala.StringLit v)

                        IntLiteral v ->
                            case tpe of
                                Type.Reference () fQName [] ->
                                    if (distribution |> Distribution.lookupBaseTypeName fQName) == Just (fqn "Morphir.SDK" "Basics" "Float") then
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

                FieldFunction tpe fieldName ->
                    case tpe of
                        Type.Function _ inputType _ ->
                            Scala.Lambda
                                [ ( "x", Just (mapType inputType) ) ]
                                (Scala.Select (Scala.Variable "x") (fieldName |> Name.toCamelCase))

                        _ ->
                            Scala.Select Scala.Wildcard (fieldName |> Name.toCamelCase)

                Apply a fun arg ->
                    let
                        ( bottomFun, args ) =
                            Value.uncurryApply fun arg
                    in
                    case bottomFun of
                        Reference _ _ ->
                            Scala.Apply (mapValue fun)
                                [ Scala.ArgValue Nothing (mapValue arg)
                                ]

                        _ ->
                            Scala.Apply (mapValue bottomFun)
                                (args
                                    |> List.map
                                        (\argValue ->
                                            Scala.ArgValue Nothing (mapValue argValue)
                                        )
                                )

                Lambda a argPattern bodyValue ->
                    case argPattern of
                        AsPattern tpe (WildcardPattern _) alias ->
                            Scala.Lambda
                                [ ( alias |> Name.toCamelCase, Just (mapType tpe) ) ]
                                (mapValue bodyValue)

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
