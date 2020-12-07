module Morphir.Visual.ViewApply exposing (view)

import Element exposing (Element, column, fill, moveRight, row, spacing, text, width, wrappedRow)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)


view : (Value ta (Type ta) -> Element msg) -> Value ta (Type ta) -> List (Value ta (Type ta)) -> Element msg
view viewValue functionValue argValues =
    case ( functionValue, argValues ) of
        ( Value.Reference _ (FQName _ _ (("is" :: _) as localName)), [ argValue ] ) ->
            row
                [ width fill
                , spacing 10
                ]
                [ viewValue argValue
                , text (nameToText localName)
                ]

        _ ->
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
