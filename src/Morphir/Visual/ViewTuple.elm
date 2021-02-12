module Morphir.Visual.ViewTuple exposing (..)

import Element exposing (Element, column, el, moveRight, spacing, text, wrappedRow)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)
import Morphir.Visual.Config exposing (Config)


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
        [ spacing config.state.theme.smallSpacing ]
        [ text (tupleCase ++ " of")
        , column
            [ moveRight 10
            , spacing config.state.theme.smallSpacing
            ]
            (elems
                |> List.map viewValue
            )
        ]
