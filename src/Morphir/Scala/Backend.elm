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
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.Scala.AST as Scala
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Set exposing (Set)


type alias Options =
    {}


mapDistribution : Options -> Package.Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Package.Library packagePath packageDef ->
            mapPackageDefinition opt packagePath packageDef


mapPackageDefinition : Options -> Package.PackagePath -> Package.Definition a -> FileMap
mapPackageDefinition opt packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                mapModuleDefinition opt packagePath modulePath moduleImpl
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


mapModuleDefinition : Options -> Package.PackagePath -> Path -> AccessControlled (Module.Definition a) -> List Scala.CompilationUnit
mapModuleDefinition opt currentPackagePath currentModulePath accessControlledModuleDef =
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
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
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
                                mapCustomTypeDefinition currentPackagePath currentModulePath typeName typeParams accessControlledCtors
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
                                Just (mapValue accessControlledValueDef.value.body)
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
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ])) <|
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
                        }
                ]
            }
    in
    [ moduleUnit ]


mapCustomTypeDefinition : Package.PackagePath -> Path -> Name -> List Name -> AccessControlled (Type.Constructors a) -> List Scala.MemberDecl
mapCustomTypeDefinition currentPackagePath currentModulePath typeName typeParams accessControlledCtors =
    let
        caseClass name args extends =
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
                        , members = []
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
                [ Scala.MemberTypeDecl (caseClass ctorName ctorArgs []) ]

            else
                sealedTraitHierarchy |> List.map Scala.MemberTypeDecl

        _ ->
            sealedTraitHierarchy |> List.map Scala.MemberTypeDecl


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


mapValue : Value a -> Scala.Value
mapValue value =
    case value of
        Literal a literal ->
            let
                wrap : String -> Scala.Lit -> Scala.Value
                wrap moduleName lit =
                    Scala.Apply
                        (Scala.Ref [ "morphir", "sdk" ] moduleName)
                        [ Scala.ArgValue Nothing (Scala.Literal lit) ]
            in
            case literal of
                BoolLiteral v ->
                    wrap "Bool" (Scala.BooleanLit v)

                CharLiteral v ->
                    wrap "Char" (Scala.CharacterLit v)

                StringLiteral v ->
                    wrap "String" (Scala.StringLit v)

                IntLiteral v ->
                    wrap "Int" (Scala.IntegerLit v)

                FloatLiteral v ->
                    wrap "Float" (Scala.FloatLit v)

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

        LetDefinition a defName def inValue ->
            Scala.Block
                [ Scala.FunctionDecl
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
                ]
                (mapValue inValue)

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
