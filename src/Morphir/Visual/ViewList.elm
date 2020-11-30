module Morphir.Visual.ViewList exposing (..)

import Dict
import Html exposing (Html)
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


view : (Value ta (Type ta) -> Html msg) -> Type ta -> List (Value ta (Type ta)) -> Html msg
view viewValue itemType items =
    Html.table []
        [ Html.tbody []
            (items
                |> List.map (viewItemAsRow viewValue itemType)
            )
        ]


viewItemAsRow : (Value ta (Type ta) -> Html msg) -> Type ta -> Value ta (Type ta) -> Html msg
viewItemAsRow viewValue itemType item =
    case ( itemType, item ) of
        ( Type.Record _ fieldTypes, Value.Record _ fields ) ->
            fieldTypes
                |> List.map
                    (\field ->
                        Html.td []
                            [ fields |> Dict.fromList |> Dict.get field.name |> Maybe.map viewValue |> Maybe.withDefault (Html.text "???")
                            ]
                    )
                |> Html.tr []

        _ ->
            Html.tr []
                [ Html.td [] [ viewValue item ]
                ]
