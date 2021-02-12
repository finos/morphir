module Morphir.Visual.ViewList exposing (view)

import Dict
import Element exposing (Element, centerX, centerY, el, fill, height, indexedTable, none, paddingXY, spacing, table, text, width)
import Element.Border as Border
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Config exposing (Config)


view : Config msg -> (Value () (Type ()) -> Element msg) -> Type () -> List (Value () (Type ())) -> Element msg
view config viewValue itemType items =
    if List.isEmpty items then
        el []
            (text "[]")

    else
        case itemType of
            Type.Record _ fields ->
                indexedTable
                    []
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
                                            [ Border.widthEach { bottom = 1, top = 0, right = 0, left = 0 }
                                            , paddingXY config.state.theme.smallPadding (config.state.theme.smallPadding // 2)
                                            ]
                                            (text (field.name |> Name.toHumanWords |> String.join " "))
                                    , width = fill
                                    , view =
                                        \rowIndex item ->
                                            el
                                                [ paddingXY config.state.theme.smallPadding (config.state.theme.smallPadding // 2)
                                                , width fill
                                                , height fill
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

                    Err error ->
                        Element.text error

            _ ->
                table
                    [ spacing config.state.theme.smallSpacing
                    ]
                    { data = items
                    , columns =
                        [ { header = none
                          , width = fill
                          , view = viewValue
                          }
                        ]
                    }
