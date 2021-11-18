module Morphir.Visual.ViewList exposing (view)

import Dict
import Element exposing (Element, centerX, centerY, el, fill, height, indexedTable, none, padding, spacing, table, text, width)
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding, smallSpacing)


view : Config msg -> (EnrichedValue -> Element msg) -> Type () -> List EnrichedValue -> Element msg
view config viewValue itemType items =
    if List.isEmpty items then
        el []
            (text "[ ]")

    else
        case itemType of
            Type.Record _ fields ->
                indexedTable
                    [ centerX, centerY ]
                    { data =
                        items
                            |> List.map
                                (\item ->
                                    config.irContext.distribution |> Distribution.resolveRecordConstructors item
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
                                                ]
                                                -- TODO: Use interpreter to get field values
                                                (el [ centerX, centerY ]
                                                    (case item of
                                                        Value.Record _ fieldValues ->
                                                            fieldValues
                                                                |> Dict.fromList
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

            Type.Reference _ fQName typeArgs ->
                case config.irContext.distribution |> Distribution.resolveTypeReference fQName typeArgs of
                    Ok resolvedItemType ->
                        view config viewValue resolvedItemType items

                    Err _ ->
                        viewAsList config viewValue items

            _ ->
                viewAsList config viewValue items


viewAsList config viewValue items =
    table
        [ smallSpacing config.state.theme |> spacing
        ]
        { data = items
        , columns =
            [ { header = none
              , width = fill
              , view = viewValue
              }
            ]
        }
