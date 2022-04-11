module Morphir.Web.DevelopApp.Common exposing (..)

import Element exposing (Element, column, el, fill, height, minimum, padding, rgb, shrink, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.Visual.Theme as Theme exposing (Theme)


viewAsCard : Theme -> Element msg -> Element msg -> Element msg
viewAsCard theme header content =
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
            , Font.size (theme |> Theme.scaled 2)
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


ifThenElse : Bool -> a -> a -> a
ifThenElse boolValue ifTrue ifFalse =
    if boolValue then
        ifTrue

    else
        ifFalse


pathToUrl : Path -> String
pathToUrl path =
    "/" ++ Path.toString Name.toTitleCase "." path

pathToFullUrl : List Path -> String
pathToFullUrl path =
    "/home" ++ String.concat(List.map pathToUrl path)


pathToDisplayString : Path -> String
pathToDisplayString =
    Path.toString (Name.toHumanWords >> String.join " ") " > "


urlFragmentToNodePath : String -> List Path
urlFragmentToNodePath f =
    let
        makeNodePath : String -> List Path -> List Path
        makeNodePath s l =
            case s of
                "" ->
                    l

                _ ->
                    makeNodePath (s |> String.split "." |> List.reverse |> List.drop 1 |> List.reverse |> String.join ".") (l ++ [ Path.fromString s ])
    in
    makeNodePath f []
