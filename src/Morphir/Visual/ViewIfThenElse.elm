module Morphir.Visual.ViewIfThenElse exposing (view)

import Element exposing (Element, column, el, moveRight, spacing, text, wrappedRow)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)


view : (Value ta (Type ta) -> Element msg) -> Value ta (Type ta) -> Value ta (Type ta) -> Value ta (Type ta) -> Element msg
view viewValue condition thenBranch elseBranch =
    column
        [ spacing 10 ]
        [ text "if"
        , el [ moveRight 10 ] (viewValue condition)
        , text "then"
        , el [ moveRight 10 ] (viewValue thenBranch)
        , text "else"
        , el [ moveRight 10 ] (viewValue elseBranch)
        ]
