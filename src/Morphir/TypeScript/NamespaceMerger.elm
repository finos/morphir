module Morphir.TypeScript.NamespaceMerger exposing (mergeNamespaces)

{-| This module contains the TypeScript backend that translates the Morphir IR into TypeScript.
-}

import Morphir.TypeScript.AST exposing (Privacy(..), TypeDef(..))


mergeNamespaces : List TypeDef -> List TypeDef
mergeNamespaces inputList =
    let
        isNamespace : TypeDef -> Bool
        isNamespace typeDef =
            case typeDef of
                Namespace _ ->
                    True

                _ ->
                    False

        nonNamespaces : List TypeDef
        nonNamespaces =
            inputList |> List.filter (isNamespace >> not)

        originalNamespaces : List TypeDef
        originalNamespaces =
            inputList |> List.filter isNamespace

        hasMatchInList : List TypeDef -> TypeDef -> Bool
        hasMatchInList typeDefList typedef =
            case typedef of
                Namespace first ->
                    typeDefList
                        |> List.any
                            (\secondType ->
                                case secondType of
                                    Namespace second ->
                                        second.name == first.name

                                    _ ->
                                        False
                            )

                _ ->
                    False

        emptyListOfNamespaces : List TypeDef
        emptyListOfNamespaces =
            []

        insertNameSpaceIntoList : TypeDef -> List TypeDef -> List TypeDef
        insertNameSpaceIntoList insertDef listTypeDef =
            case insertDef of
                Namespace joinThisTo ->
                    if hasMatchInList listTypeDef insertDef then
                        listTypeDef
                            |> List.map
                                (\targetDef ->
                                    case targetDef of
                                        Namespace joinToThis ->
                                            if joinThisTo.name == joinToThis.name then
                                                let
                                                    joinedPrivacy : Privacy
                                                    joinedPrivacy =
                                                        if
                                                            (joinThisTo.privacy == Public)
                                                                || (joinToThis.privacy == Public)
                                                        then
                                                            Public

                                                        else
                                                            Private
                                                in
                                                Namespace
                                                    { name = joinThisTo.name
                                                    , privacy = joinedPrivacy
                                                    , content =
                                                        joinThisTo.content ++ joinToThis.content
                                                    }

                                            else
                                                targetDef

                                        _ ->
                                            targetDef
                                )

                    else
                        insertDef :: listTypeDef

                _ ->
                    insertDef :: listTypeDef
    in
    List.concat
        [ nonNamespaces
        , originalNamespaces
            |> List.foldr insertNameSpaceIntoList emptyListOfNamespaces
            |> List.map
                (\typeDef ->
                    case typeDef of
                        Namespace namespace ->
                            Namespace { namespace | content = mergeNamespaces namespace.content }

                        _ ->
                            typeDef
                )
        ]
