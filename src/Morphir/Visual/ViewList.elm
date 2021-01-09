module Morphir.Visual.ViewList exposing (view)

import Dict
import Element exposing (Element, fill, none, spacing, table, text)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


view : Distribution -> (Value () (Type ()) -> Element msg) -> Type () -> List (Value () (Type ())) -> Element msg
view distribution viewValue itemType items =
    case itemType of
        Type.Record _ fields ->
            table
                [ spacing 10
                ]
                { data =
                    items
                        |> List.map
                            (\item ->
                                distribution |> Distribution.resolveRecordConstructors item
                            )
                , columns =
                    fields
                        |> List.map
                            (\field ->
                                { header = text (field.name |> Name.toHumanWords |> String.join " ")
                                , width = fill
                                , view =
                                    \item ->
                                        -- TODO: Use interpreter to get field values
                                        case item of
                                            Value.Record _ fieldValues ->
                                                fieldValues
                                                    |> Dict.fromList
                                                    |> Dict.get field.name
                                                    |> Maybe.map viewValue
                                                    |> Maybe.withDefault (text "???")

                                            _ ->
                                                viewValue item
                                }
                            )
                }

        Type.Reference _ fQName typeArgs ->
            case distribution |> Distribution.resolveTypeReference fQName typeArgs of
                Ok resolvedItemType ->
                    view distribution viewValue resolvedItemType items

                Err error ->
                    Element.text error

        _ ->
            table
                [ spacing 10
                ]
                { data = items
                , columns =
                    [ { header = none
                      , width = fill
                      , view = viewValue
                      }
                    ]
                }
