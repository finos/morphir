module Morphir.Web.DecisionTreeTest exposing (..)

import Element exposing (Element, column, el, padding, spacing, text)
import Element.Border as Border
import Morphir.Visual.Components.DecisionTree exposing (Node(..), horizontalLayout, layout, verticalLayout)


main =
    let
        node label =
            el
                [ Border.width 2
                , Border.rounded 7
                , padding 5
                ]
                (text label)
    in
    Element.layout
        []
        (column [ spacing 60 ]
            (layouts node text horizontalLayout ++ layouts node text verticalLayout)
        )


layouts : (String -> a) -> (String -> a) -> (a -> a -> a -> a -> a -> a) -> List a
layouts node text layout =
    [ layout
        (node "condition")
        (text "Yes")
        (node "then branch")
        (text "No")
        (node "else branch")
    , layout
        (node "condition wefewfwef")
        (text "Yes")
        (layout
            (node "condition 2")
            (text "Yes")
            (node "then branch 2")
            (text "No")
            (node "else branch 2")
        )
        (text "No")
        (node "else branch")
    , layout
        (node "condition wefewfwef")
        (text "Yes")
        (layout
            (node "condition 2")
            (text "Yes")
            (node "then branch 2")
            (text "No")
            (node "else branch 2")
        )
        (text "No")
        (layout
            (node "condition 3")
            (text "Yes")
            (node "then branch 3")
            (text "No")
            (node "else branch 3")
        )
    , layout
        (node "condition wefewfwef")
        (text "Yes")
        (layout
            (node "condition 2")
            (text "Yes")
            (layout
                (node "condition 3")
                (text "Yes")
                (node "then branch 3")
                (text "No")
                (node "else branch 3")
            )
            (text "No")
            (node "else branch 2")
        )
        (text "No")
        (node "else branch")
    , layout
        (node "condition wefewfwef")
        (text "No")
        (node "else branch")
        (text "Yes")
        (layout
            (node "condition 2")
            (text "No")
            (node "else branch 2")
            (text "Yes")
            (layout
                (node "condition 3")
                (text "Yes")
                (node "then branch 3")
                (text "No")
                (node "else branch 3")
            )
        )
    ]
