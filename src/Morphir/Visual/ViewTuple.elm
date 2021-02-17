module Morphir.Visual.ViewTuple exposing (..)

import Element exposing (Element, column, moveRight, spacing, text)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme exposing (smallSpacing)


view : Config msg -> (Value ta (Type ta) -> Element msg) -> List (Value ta (Type ta)) -> Element msg
view config viewValue elems =
    let
        tupleCase : String
        tupleCase =
            case List.length elems of
                2 ->
                    "pair"

                3 ->
                    "triple"

                _ ->
                    "tuple"
    in
    column
        [ smallSpacing config.state.theme |> spacing ]
        [ text (tupleCase ++ " of")
        , column
            [ moveRight 10
            , smallSpacing config.state.theme |> spacing
            ]
            (elems
                |> List.map viewValue
            )
        ]
