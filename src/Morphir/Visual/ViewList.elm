module Morphir.Visual.ViewList exposing (view)

import Dict
import Element exposing (Element, centerX, centerY, el, fill, height, indexedTable, none, padding, row, spacing, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.Distribution as Distribution
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Visual.Config exposing (Config, evaluate)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding, smallSpacing)


view : Config msg -> (EnrichedValue -> Element msg) -> Type () -> List EnrichedValue -> Maybe EnrichedValue -> Element msg
view config viewValue itemType items maybeItemToHighlight =
    let
        shouldHighLight : EnrichedValue -> Bool
        shouldHighLight currentItem =
            case maybeItemToHighlight of
                Nothing ->
                    False

                Just i ->
                    case
                        evaluate (Value.toRawValue i) config
                            |> Result.andThen (\res1 -> evaluate (Value.toRawValue currentItem) config |> Result.andThen (\res2 -> Ok (res1 == res2)))
                    of
                        Ok a ->
                            a

                        Err _ ->
                            False
    in
    if List.isEmpty items then
        el [ centerX, centerY ]
            (text " [ ] ")

    else
        let
            defaultDisplay : List EnrichedValue -> Element msg
            defaultDisplay i =
                table
                    [ smallSpacing config.state.theme |> spacing
                    ]
                    { data = i
                    , columns =
                        [ { header = none
                          , width = fill
                          , view =
                                \item ->
                                    el
                                        [ if shouldHighLight item then
                                            Background.color config.state.theme.colors.positiveLight

                                          else
                                            Background.color config.state.theme.colors.lightest
                                        ]
                                    <|
                                        viewValue item
                          }
                        ]
                    }
        in
        case config.ir |> Distribution.resolveType itemType of
            Type.Record _ fields ->
                indexedTable
                    [ centerX, centerY ]
                    { data =
                        items
                            |> List.map
                                (\item ->
                                    config.ir |> Distribution.resolveRecordConstructors item
                                )
                    , columns =
                        fields
                            |> List.map
                                (\field ->
                                    { header =
                                        el
                                            [ Border.width 1
                                            , smallPadding config.state.theme |> padding
                                            , Font.bold
                                            ]
                                            (el [ centerY, centerX ] (text (field.name |> Name.toHumanWords |> String.join " ")))
                                    , width = fill
                                    , view =
                                        \rowIndex item ->
                                            el
                                                [ smallPadding config.state.theme |> padding
                                                , width fill
                                                , height fill
                                                , Border.widthEach { bottom = 1, top = 0, right = 1, left = 1 }
                                                , if shouldHighLight item then
                                                    Background.color config.state.theme.colors.positiveLight

                                                  else
                                                    Background.color config.state.theme.colors.lightest
                                                ]
                                                -- TODO: Use interpreter to get field values
                                                (el
                                                    [ centerX
                                                    , centerY
                                                    ]
                                                    (case item of
                                                        Value.Record _ fieldValues ->
                                                            fieldValues
                                                                |> Dict.get field.name
                                                                |> Maybe.map viewValue
                                                                |> Maybe.withDefault (text "???")

                                                        _ ->
                                                            viewValue item
                                                    )
                                                )
                                    }
                                )
                    }

            Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], _ ) _ ->
                -- display small lists of simple values horizontally
                if List.length items < 6 then
                    row
                        [ smallSpacing config.state.theme |> spacing
                        ]
                        ((el [ Font.bold ] <| text "[")
                            :: (items
                                    |> List.map
                                        (\item ->
                                            el
                                                [ if shouldHighLight item then
                                                    Background.color config.state.theme.colors.positiveLight

                                                  else
                                                    Background.color config.state.theme.colors.lightest
                                                ]
                                            <|
                                                viewValue item
                                        )
                                    |> List.intersperse (text ",")
                               )
                            ++ [ el [ Font.bold ] <| text "]" ]
                        )

                else
                    defaultDisplay items

            _ ->
                defaultDisplay items
