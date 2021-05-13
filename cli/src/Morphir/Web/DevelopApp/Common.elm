module Morphir.Web.DevelopApp.Common exposing (..)

import Element exposing (Element, column, el, fill, height, minimum, padding, rgb, shrink, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font


scaled : Int -> Int
scaled =
    Element.modular 10 1.25 >> round


viewAsCard : Element msg -> Element msg -> Element msg
viewAsCard header content =
    let
        gray =
            rgb 0.9 0.9 0.9

        white =
            rgb 1 1 1
    in
    column
        [ Background.color gray
        , Border.rounded 3
        , height (shrink |> minimum 200)
        , width (shrink |> minimum 200)
        , padding 5
        , spacing 5
        ]
        [ el
            [ width fill
            , padding 2
            , Font.size (scaled 2)
            ]
            header
        , el
            [ Background.color white
            , Border.rounded 3
            , padding 5
            , height fill
            , width fill
            ]
            content
        ]


insertInList : Int -> List a -> List a
insertInList index list =
    let
        list2 =
            list |> List.drop index
    in
    List.append (list2 |> List.take 1)
        list2
        |> List.append (list |> List.take index)
