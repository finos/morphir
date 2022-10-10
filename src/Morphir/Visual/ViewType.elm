module Morphir.Visual.ViewType exposing (..)

{-| Display detailed information of a Type on the UI
-}

import Dict
import Element exposing (..)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.Visual.Common exposing (nameToText, nameToTitleText, pathToUrl)
import Morphir.Visual.Components.Card as Card
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.XRayView as XRayView


viewType : Theme -> Name -> Type.Definition () -> String -> Element msg
viewType theme typeName typeDef docs =
    case typeDef of
        Type.TypeAliasDefinition _ (Type.Record _ fields) ->
            let
                fieldNames : { a | name : Name } -> Element msg
                fieldNames =
                    \field ->
                        el
                            (Theme.boldLabelStyles theme)
                            (text (nameToText field.name))

                fieldTypes : { a | tpe : Type () } -> Element msg
                fieldTypes =
                    \field ->
                        el
                            (Theme.labelStyles theme)
                            (XRayView.viewType pathToUrl field.tpe)

                viewFields : Element msg
                viewFields =
                    Theme.twoColumnTableView
                        fields
                        fieldNames
                        fieldTypes
            in
            Card.viewAsCard theme
                (typeName |> nameToTitleText |> text)
                "record"
                theme.colors.backgroundColor
                docs
                viewFields

        Type.TypeAliasDefinition _ body ->
            Card.viewAsCard theme
                (typeName |> nameToTitleText |> text)
                "is a"
                theme.colors.backgroundColor
                docs
                (el
                    [ paddingXY 10 5
                    ]
                    (XRayView.viewType pathToUrl body)
                )

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

                viewConstructors : Element msg
                viewConstructors =
                    if isEnum then
                        accessControlledConstructors.value
                            |> Dict.toList
                            |> List.map
                                (\( ctorName, _ ) ->
                                    el
                                        (Theme.boldLabelStyles theme)
                                        (text (nameToTitleText ctorName))
                                )
                            |> column [ width fill ]

                    else
                        case isNewType of
                            Just baseType ->
                                el [ padding (theme |> Theme.scaled -2) ] (XRayView.viewType pathToUrl baseType)

                            Nothing ->
                                let
                                    constructorNames =
                                        \( ctorName, _ ) ->
                                            el
                                                (Theme.boldLabelStyles theme)
                                                (text (nameToTitleText ctorName))

                                    constructorArgs =
                                        \( _, ctorArgs ) ->
                                            el
                                                (Theme.labelStyles theme)
                                                (ctorArgs
                                                    |> List.map (Tuple.second >> XRayView.viewType pathToUrl)
                                                    |> row [ spacing 5 ]
                                                )
                                in
                                Theme.twoColumnTableView
                                    (Dict.toList accessControlledConstructors.value)
                                    constructorNames
                                    constructorArgs
            in
            Card.viewAsCard theme
                (typeName |> nameToTitleText |> text)
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
                docs
                viewConstructors
