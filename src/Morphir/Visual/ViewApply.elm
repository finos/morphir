module Morphir.Visual.ViewApply exposing (view)

import Element exposing (Element, column, moveRight, spacing, wrappedRow)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)


view : (Value ta (Type ta) -> Element msg) -> Value ta (Type ta) -> List (Value ta (Type ta)) -> Element msg
view viewValue functionValue argValues =
    column
        [ spacing 10 ]
        [ viewValue functionValue
        , column
            [ moveRight 10
            , spacing 10
            ]
            (argValues
                |> List.map viewValue
            )
        ]
