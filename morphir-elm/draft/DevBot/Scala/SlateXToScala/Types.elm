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


module SlateX.DevBot.Scala.SlateXToScala.Types exposing (extractTypeArgNames, mapExp, mapRecordTypeAlias, mapRecordTypeAliasToTrait, mapUnionType)

import Set
import SlateX.AST.Name exposing (Name)
import SlateX.AST.Path exposing (Path)
import SlateX.AST.Type as T
import SlateX.AST.Type.Collect as TypeCollect
import SlateX.DevBot.Scala.AST as S
import SlateX.DevBot.Scala.SlateXToScala.CoreTypes as SlateXCore
import SlateX.DevBot.Scala.SlateXToScala.Report as Report
import SlateX.Mapping.Naming as Naming


mapExp : T.Exp -> S.Type
mapExp exp =
    case exp of
        T.Variable name ->
            S.TypeVar (name |> Naming.toTitleCase)

        T.Constructor ( [ [ "slate", "x" ], [ "core" ], moduleName ], typeName ) args ->
            SlateXCore.mapConstructor
                (moduleName |> Naming.toTitleCase)
                (typeName |> Naming.toTitleCase)
                (args |> List.map mapExp)

        T.Constructor ( [ [ "morphir" ], [ "s", "d", "k" ], moduleName ], typeName ) args ->
            SlateXCore.mapConstructor
                (moduleName |> Naming.toTitleCase)
                (typeName |> Naming.toTitleCase)
                (args |> List.map mapExp)

        T.Constructor ( modulePath, localName ) args ->
            let
                typeRef =
                    S.TypeRef
                        (modulePath |> List.map (Naming.toCamelCase >> String.toLower))
                        (localName |> Naming.toTitleCase)
            in
            if List.isEmpty args then
                typeRef

            else
                S.TypeApply typeRef (args |> List.map mapExp)

        T.Tuple elems ->
            S.TupleType (elems |> List.map mapExp)

        T.Record fields ->
            S.StructuralType
                (fields
                    |> List.map
                        (\( fieldName, fieldType ) ->
                            S.FunctionDecl
                                { modifiers = []
                                , name = fieldName |> Naming.toCamelCase
                                , typeArgs = extractTypeArgNames [ fieldType ] |> List.map (T.Variable >> mapExp)
                                , args = []
                                , returnType = fieldType |> mapExp |> Just
                                , body = Nothing
                                }
                        )
                )

        T.ExtensibleRecord target fields ->
            S.StructuralType
                (fields
                    |> List.map
                        (\( fieldName, fieldType ) ->
                            S.FunctionDecl
                                { modifiers = []
                                , name = fieldName |> Naming.toCamelCase
                                , typeArgs = extractTypeArgNames [ fieldType ] |> List.map (T.Variable >> mapExp)
                                , args = []
                                , returnType = fieldType |> mapExp |> Just
                                , body = Nothing
                                }
                        )
                )

        T.Function argType returnType ->
            S.FunctionType (argType |> mapExp) (returnType |> mapExp)


mapRecordTypeAlias : Name -> T.TypeAliasDeclaration -> List S.TypeDecl
mapRecordTypeAlias name aliasDecl =
    case aliasDecl.exp of
        T.Record fields ->
            let
                recordTypeName =
                    name |> Naming.toTitleCase
            in
            [ S.Class
                { modifiers = [ S.Final, S.Case ]
                , name = recordTypeName
                , typeArgs = []
                , ctorArgs =
                    [ fields
                        |> List.map
                            (\( fieldName, fieldType ) ->
                                { modifiers = []
                                , tpe = mapExp fieldType
                                , name = fieldName |> Naming.toCamelCase
                                , defaultValue = Nothing
                                }
                            )
                    ]
                , extends =
                    [ S.TypeRef
                        [ recordTypeName ]
                        ([ "repr" ] |> Naming.toTitleCase)
                    ]
                }
            , S.Object
                { modifiers = []
                , name = name |> Naming.toTitleCase
                , extends = []
                , members =
                    let
                        typeRef =
                            S.TypeRef [] ([ "repr" ] |> Naming.toTitleCase)

                        convertFromFunction =
                            [ S.FunctionDecl
                                { modifiers = [ S.Implicit ]
                                , name = [ "convert", "from" ] |> Naming.toCamelCase
                                , typeArgs = []
                                , args =
                                    [ { modifiers = []
                                      , tpe = typeRef
                                      , name = "repr"
                                      , defaultValue = Maybe.Nothing
                                      }
                                        |> List.singleton
                                    ]
                                , returnType = S.TypeRef [] (name |> Naming.toTitleCase) |> Maybe.Just
                                , body =
                                    S.Apply
                                        (S.Ref [] recordTypeName)
                                        (fields
                                            |> List.map
                                                (\( fieldName, _ ) ->
                                                    S.ArgValue
                                                        (fieldName |> Naming.toCamelCase |> Maybe.Just)
                                                        (S.Select
                                                            (S.Ref [] "repr")
                                                            (fieldName |> Naming.toCamelCase)
                                                        )
                                                )
                                        )
                                        |> Maybe.Just
                                }
                            ]

                        typeAlias =
                            [ S.TypeAlias
                                { alias = name |> Naming.withSuffix "repr" |> Naming.toTitleCase
                                , typeArgs = []
                                , tpe = typeRef
                                }
                            ]

                        members =
                            mapRecordTypeAliasToTrait [ "repr" ] aliasDecl
                                |> List.map (\td -> S.MemberTypeDecl td)
                    in
                    typeAlias ++ members ++ convertFromFunction
                }
            ]

        _ ->
            []


mapRecordTypeAliasToTrait : Name -> T.TypeAliasDeclaration -> List S.TypeDecl
mapRecordTypeAliasToTrait name aliasDecl =
    case aliasDecl.exp of
        T.Record fields ->
            [ S.Trait
                { modifiers = []
                , name = name |> Naming.toTitleCase
                , typeArgs = []
                , extends = []
                , members =
                    fields
                        |> List.map
                            (\( fieldName, fieldType ) ->
                                S.FunctionDecl
                                    { modifiers = []
                                    , name = fieldName |> Naming.toCamelCase
                                    , typeArgs = []
                                    , args = []
                                    , returnType = mapExp fieldType |> Maybe.Just
                                    , body = Maybe.Nothing
                                    }
                            )
                }
            ]

        _ ->
            []


mapUnionType : Path -> Name -> T.UnionTypeDeclaration -> List S.TypeDecl
mapUnionType modulePath name unionType =
    let
        baseTraitName =
            name |> Naming.toTitleCase

        shouldGenerateValueClass =
            case unionType.cases of
                [ ( caseName, [ _ ] ) ] ->
                    (caseName |> Naming.toTitleCase) == baseTraitName

                _ ->
                    False

        traitName =
            case unionType.cases of
                [ ( caseName, _ ) ] ->
                    if (caseName |> Naming.toTitleCase) == baseTraitName then
                        baseTraitName ++ "Repr"

                    else
                        baseTraitName

                _ ->
                    baseTraitName

        trait =
            S.Trait
                { modifiers = [ S.Sealed ]
                , name = traitName
                , typeArgs = unionType.params |> List.map (T.Variable >> mapExp)
                , extends =
                    if shouldGenerateValueClass then
                        [ S.TypeRef [ "scala" ] "Any" ]

                    else
                        []
                , members = []
                }

        traitRef typeArgNames =
            let
                ref =
                    S.TypeRef (modulePath |> List.map (Naming.toCamelCase >> String.toLower)) traitName
            in
            case unionType.params of
                [] ->
                    ref

                _ ->
                    S.TypeApply ref
                        (unionType.params
                            |> List.map
                                (\paramName ->
                                    if typeArgNames |> List.member paramName then
                                        T.Variable paramName |> mapExp

                                    else
                                        S.TypeRef [ "scala" ] "Nothing"
                                )
                        )

        caseClasses =
            case unionType.cases of
                [ ( caseName, [ caseArg ] ) ] ->
                    let
                        caseArgs =
                            [ caseArg ]

                        typeArgNames =
                            extractTypeArgNames caseArgs

                        extendsClause =
                            if shouldGenerateValueClass then
                                [ S.TypeRef [ "scala" ] "AnyVal" ] ++ [ traitRef typeArgNames ]

                            else
                                [ traitRef typeArgNames ]
                    in
                    [ S.Class
                        { modifiers = [ S.Final, S.Case ]
                        , name = caseName |> Naming.toTitleCase
                        , typeArgs = typeArgNames |> List.map (T.Variable >> mapExp)
                        , ctorArgs =
                            [ caseArgs
                                |> List.map
                                    (\argType ->
                                        { modifiers = []
                                        , tpe = argType |> mapExp
                                        , name = "value"
                                        , defaultValue = Nothing
                                        }
                                    )
                            ]
                        , extends = extendsClause
                        }
                    ]

                _ ->
                    unionType.cases
                        |> List.map
                            (\( caseName, caseArgs ) ->
                                case caseArgs of
                                    [] ->
                                        S.Object
                                            { modifiers = [ S.Final, S.Case ]
                                            , name = caseName |> Naming.toTitleCase
                                            , members = []
                                            , extends = [ traitRef [] ]
                                            }

                                    _ ->
                                        let
                                            typeArgNames =
                                                extractTypeArgNames caseArgs
                                        in
                                        S.Class
                                            { modifiers = [ S.Final, S.Case ]
                                            , name = caseName |> Naming.toTitleCase
                                            , typeArgs = typeArgNames |> List.map (T.Variable >> mapExp)
                                            , ctorArgs =
                                                [ caseArgs
                                                    |> List.indexedMap
                                                        (\index argType ->
                                                            { modifiers = []
                                                            , tpe = argType |> mapExp
                                                            , name = "arg" ++ Debug.toString index
                                                            , defaultValue = Nothing
                                                            }
                                                        )
                                                ]
                                            , extends = [ traitRef typeArgNames ]
                                            }
                            )
    in
    trait :: caseClasses


extractTypeArgNames : List T.Exp -> List Name
extractTypeArgNames inputTypes =
    let
        collectVariables tpe =
            tpe
                |> TypeCollect.collectExp
                    { exp =
                        \exp ->
                            case exp of
                                T.Variable name ->
                                    [ name ]

                                _ ->
                                    []
                    }
    in
    inputTypes
        |> List.concatMap collectVariables
        |> Set.fromList
        |> Set.toList
