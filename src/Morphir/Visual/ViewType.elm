module Morphir.Visual.ViewType exposing (..)

{-| Display detailed information of a Type on the UI
-}

import Dict
import Element exposing (..)
import Element.Font as Font
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.Visual.Common exposing (nameToText, nameToTitleText, pathToUrl)
import Morphir.Visual.Components.Card as Card
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.XRayView as XRayView


viewType : Theme -> Name -> Type.Definition () -> String -> Element msg
viewType theme typeName typeDef docs =
    let
        cardTitle =
            link [ pointer ]
                { url =
                    "/module/" ++ ([] |> List.map Name.toTitleCase |> String.join ".") ++ "?filter=" ++ nameToText typeName
                , label =
                    el [ Font.extraBold, Font.size 30 ] (text (nameToText typeName))
                }
    in
    case typeDef of
        Type.TypeAliasDefinition _ (Type.Record _ _) ->
            Card.viewAsCard theme
                cardTitle
                "record"
                theme.colors.backgroundColor
                docs
                none

        Type.TypeAliasDefinition _ body ->
            Card.viewAsCard theme
                cardTitle
                "is a"
                theme.colors.backgroundColor
                docs
                none

        Type.CustomTypeDefinition _ accessControlledConstructors ->
            let
                isNewType : Maybe (Type ())
                isNewType =
                    case accessControlledConstructors.value |> Dict.toList of
                        [ ( ctorName, [ ( _, baseType ) ] ) ] ->
                            if ctorName == typeName then
                                Just baseType

                            else
                                Nothing

                        _ ->
                            Nothing

                isEnum : Bool
                isEnum =
                    accessControlledConstructors.value
                        |> Dict.values
                        |> List.all List.isEmpty
            in
            Card.viewAsCard theme
                cardTitle
                (case isNewType of
                    Just _ ->
                        "wrapper"

                    Nothing ->
                        if isEnum then
                            "enum"

                        else
                            "one of"
                )
                theme.colors.backgroundColor
                (if docs /= "" then
                    docs

                 else
                    "This type has no associated documentation"
                )
                none
