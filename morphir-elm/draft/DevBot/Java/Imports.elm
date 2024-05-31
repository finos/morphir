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


module SlateX.DevBot.Java.Imports exposing (..)


import Dict exposing (Dict)
import Set exposing (Set)
import SlateX.DevBot.Java.Ast exposing (..)
import SlateX.DevBot.Java.Ast.Collect exposing (collector)
import SlateX.DevBot.Java.Ast.Collect as Collect
import SlateX.DevBot.Java.Ast.Rewrite exposing (rewriter)
import SlateX.DevBot.Java.Ast.Rewrite as Rewrite


generate : CompilationUnit -> CompilationUnit
generate cu =
    let
        allQualifiedTypeNamesByLocalName =
            collectTypeNames cu
                |> listToDict

        allQualifiedValueNamesByLocalName =
            collectValueNames cu
                |> listToDict

        qualifiedTypeNameByLocalName =
            allQualifiedTypeNamesByLocalName
                |> Dict.toList
                |> List.filterMap
                    (\( lName, qualifiedNames ) ->
                        if Set.size qualifiedNames > 1 then
                            Nothing
                        else
                            case Set.toList qualifiedNames of
                                [ [ single ] ] ->
                                    Nothing

                                [ qualifiedName ] ->
                                    Just ( lName, qualifiedName )

                                _ ->
                                    Nothing
                    )
                |> Dict.fromList

        qualifiedValueNameByLocalName =
            allQualifiedValueNamesByLocalName
                |> Dict.toList
                |> List.filterMap
                    (\( lName, qualifiedNames ) ->
                        if Set.size qualifiedNames > 1 then
                            Nothing
                        else
                            case Set.toList qualifiedNames of
                                [ [ single ] ] ->
                                    Nothing

                                [ qualifiedName ] ->
                                    Just ( lName, qualifiedName )

                                _ ->
                                    Nothing
                    )
                |> Dict.fromList

        localTypeNameByQName =
            qualifiedTypeNameByLocalName
                |> Dict.toList
                |> List.map
                    (\( lName, qualifiedName ) ->
                        ( qualifiedName, lName )
                    )
                |> Dict.fromList

        typeImports =
            qualifiedTypeNameByLocalName
                |> Dict.toList
                |> List.map
                    (\( _, qualifiedName ) ->
                        Import qualifiedName False
                    )

        localValueNameByQName =
            qualifiedValueNameByLocalName
                |> Dict.toList
                |> List.map
                    (\( lName, qualifiedName ) ->
                        ( qualifiedName, lName )
                    )
                |> Dict.fromList

        valueImports =
            qualifiedValueNameByLocalName
                |> Dict.toList
                |> List.map
                    (\( _, qualifiedName ) ->
                        StaticImport qualifiedName False
                    )

    in
    { cu
        | imports = typeImports ++ valueImports
        , typeDecls =
            cu.typeDecls
                |> List.map (rewriteTypeNames localTypeNameByQName)
                |> List.map (rewriteValueNames localValueNameByQName)
    }


collectTypeNames : CompilationUnit -> List ( Identifier, QualifiedIdentifier )
collectTypeNames cu =
    let
        collectTypeExp typeExp =
            case typeExp of
                TypeRef name ->
                    [ ( localName name, name ) ]

                TypeConst name args ->
                    [ [ ( localName name, name ) ]
                    , args
                        |> List.concatMap collectTypeExp
                    ] |> List.concat

                _ ->
                    []

        typeNameCollector =
            { collector
                | typeExp = collectTypeExp
                , exp =
                    \exp ->
                        case exp of
                            ConstructorRef typeRef ->
                                [ ( localName typeRef, typeRef ) ]

                            _ ->
                                []
                , typeDeclaration =
                    \typeDeclaration ->
                        case typeDeclaration of
                            Class { name } ->
                                [ ( name, [ name ] ) ]

                            Interface { name } ->
                                [ ( name, [ name ] ) ]

                            Enum { name } ->
                                [ ( name, [ name ] ) ]
            }

    in
    cu.typeDecls
        |> List.concatMap (Collect.collectTypeDeclaration typeNameCollector)


rewriteTypeNames : Dict QualifiedIdentifier Identifier -> TypeDeclaration -> TypeDeclaration
rewriteTypeNames mapping typeDecl =
    let
        rewriteTypeExp typeExp =
            case typeExp of
                TypeRef name ->
                    mapping
                        |> Dict.get name
                        |> Maybe.map
                            (\lName ->
                                TypeRef [ lName ]
                            )

                TypeConst name args ->
                    mapping
                        |> Dict.get name
                        |> Maybe.map
                            (\lName ->
                                TypeConst
                                    [ lName ]
                                    (args 
                                        |> List.map 
                                            (\te -> 
                                                rewriteTypeExp te
                                                    |> Maybe.withDefault te
                                            )
                                    )
                            )

                _ ->
                    Nothing
        
        typeNameRewriter =
            { rewriter
                | typeExp = rewriteTypeExp
                , exp =
                    \exp ->
                        case exp of
                            ConstructorRef typeRef ->
                                mapping
                                    |> Dict.get typeRef
                                    |> Maybe.map
                                        (\lName ->
                                            ConstructorRef [ lName ]
                                        )

                            _ ->
                                Nothing
            }

    in
        typeDecl
            |> Rewrite.rewriteTypeDeclaration typeNameRewriter


collectValueNames : CompilationUnit -> List ( Identifier, QualifiedIdentifier )
collectValueNames cu =
    let
        packageName =
            cu.packageDecl
                |> Maybe.map .qualifiedName
                |> Maybe.withDefault []

        valueNameCollector =
            { collector
                | exp =
                    \exp ->
                        case exp of
                            ValueRef name ->
                                [ ( localName name, name ) ]

                            _ ->
                                []

                , memberDecl =
                    \memberDecl ->
                        case memberDecl of
                            Method { name } ->
                                [ ( name, [ name ] ) ]

                            _ ->
                                []
            }

    in
    cu.typeDecls
        |> List.concatMap (Collect.collectTypeDeclaration valueNameCollector)


rewriteValueNames : Dict QualifiedIdentifier Identifier -> TypeDeclaration -> TypeDeclaration
rewriteValueNames mapping typeDecl =
    let
        valueNameRewriter =
            { rewriter
                | exp =
                    \exp ->
                        case exp of
                            ValueRef name ->
                                mapping
                                    |> Dict.get name
                                    |> Maybe.map
                                        (\lName ->
                                            ValueRef [ lName ]
                                        )

                            _ ->
                                Nothing
            }

    in
        typeDecl
            |> Rewrite.rewriteTypeDeclaration valueNameRewriter


listToDict : List ( Identifier, QualifiedIdentifier ) -> Dict Identifier (Set QualifiedIdentifier)
listToDict pairs =
    List.foldl
        (\(nextLocalName, nextName) soFar ->
            soFar
                |> Dict.update nextLocalName
                    (\maybeOldValue ->
                        case maybeOldValue of
                            Nothing ->
                                Just (Set.singleton nextName)

                            Just oldValues ->
                                Just (oldValues |> Set.insert nextName)
                    )
        )
        Dict.empty
        pairs


localName : QualifiedIdentifier -> Identifier
localName qualifiedName =
    qualifiedName
        |> List.reverse
        |> List.head
        |> Maybe.withDefault ""
