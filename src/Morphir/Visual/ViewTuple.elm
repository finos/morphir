module Morphir.Visual.ViewTuple exposing (..)

import Element exposing (Element, column, el, moveRight, spacing, text, wrappedRow)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)


view : (Value ta (Type ta) -> Element msg) -> List (Value ta (Type ta)) -> Element msg
view viewValue elems =
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
        [ spacing 10 ]
        [ text (tupleCase ++ " of")
        , column
            [ moveRight 10
            , spacing 10
            ]
            (elems
                |> List.map viewValue
            )
        ]
