module Morphir.Visual.ViewTuple exposing (..)

import Element exposing (Element, column, padding, spacing, text)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme exposing (mediumSpacing, smallPadding, smallSpacing)


view : Config msg -> (Value ta ( Int, Type ta ) -> Element msg) -> List (Value ta ( Int, Type ta )) -> Element msg
view config viewValue elems =
    column
        [ mediumSpacing config.state.theme |> spacing
        ]
        [ Element.row
            [ mediumSpacing config.state.theme |> spacing
            , smallPadding config.state.theme |> padding
            ]
            [ text "("
            , elems
                |> List.map viewValue
                |> List.intersperse (text ",")
                |> Element.row [ smallSpacing config.state.theme |> spacing ]
            , text ")"
            ]
        ]
