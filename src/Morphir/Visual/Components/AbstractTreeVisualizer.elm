module Morphir.Visual.Components.AbstractTreeVisualizer exposing (..)

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import List
import Svg exposing (..)
import Svg.Attributes exposing (..)


type alias Model =
    List Int


initialModel : Model
initialModel =
    []


absString : String
absString =
    "AOB -> Add -> [ AVL (Variables) -> F1 , ADB -> Divides-> [ AVL (Variable) -> F2 , AVL (Apply): AVL (Apply): AVL (Reference) -> Morphir.SDK:Basics:multiply __ AVL (Variable) -> F3 __ AVL (Variable) -> F4 ] ]"


chopWord : List Int -> Int -> Int -> String -> List String -> List String
chopWord indices beg end stringy listy =
    if List.length indices > 0 then
        chopWord (List.drop 1 indices) (end + 2) (Maybe.withDefault 0 (List.head (List.drop 1 indices))) stringy (listy ++ [ String.slice beg end stringy ])

    else
        listy ++ [ String.slice beg (String.length stringy) stringy ]


createTreeFromString : String -> List (List String)
createTreeFromString inputString =
    chopWord (String.indexes "," absString) 0 (Maybe.withDefault 0 (List.head (String.indexes "," absString))) inputString []
        |> createFurtherTree []


createFurtherTree : List String -> List String -> List (List String)
createFurtherTree finalList listy =
    List.map (\step -> String.split "->" step) listy


maxStringLengthInList : List String -> Int
maxStringLengthInList listInner =
    Maybe.withDefault 0 (List.maximum (List.map String.length listInner))


populatePositions : List (List String) -> Int -> Float -> List Float -> List Float
populatePositions listAll index movingMaximum positions =
    if index == List.length listAll then
        positions

    else if List.member movingMaximum positions then
        populatePositions listAll
            (index + 1)
            (movingMaximum
                + toFloat
                    (Maybe.withDefault 0
                        (List.maximum
                            (List.indexedMap
                                (\ind elem ->
                                    if ind == index then
                                        maxStringLengthInList elem

                                    else
                                        0
                                )
                                listAll
                            )
                        )
                    )
            )
            positions

    else
        populatePositions listAll
            (index + 1)
            (movingMaximum
                + toFloat
                    (Maybe.withDefault 0
                        (List.maximum
                            (List.indexedMap
                                (\ind elem ->
                                    if ind == index then
                                        maxStringLengthInList elem

                                    else
                                        0
                                )
                                listAll
                            )
                        )
                    )
            )
            (positions ++ [ movingMaximum ])


previousIndexMax : List (List String) -> Int -> Float -> List Float -> Float
previousIndexMax listAll index movingMaximum positions =
    if index < 0 then
        movingMaximum

    else if List.member movingMaximum positions then
        previousIndexMax listAll
            (index - 1)
            (movingMaximum
                + toFloat
                    (Maybe.withDefault 0
                        (List.maximum
                            (List.indexedMap
                                (\ind elem ->
                                    if ind == index then
                                        maxStringLengthInList elem

                                    else
                                        0
                                )
                                listAll
                            )
                        )
                    )
            )
            positions

    else
        previousIndexMax listAll
            (index - 1)
            (movingMaximum
                + toFloat
                    (Maybe.withDefault 0
                        (List.maximum
                            (List.indexedMap
                                (\ind elem ->
                                    if ind == index then
                                        maxStringLengthInList elem

                                    else
                                        0
                                )
                                listAll
                            )
                        )
                    )
            )
            (positions ++ [ movingMaximum ])


drawTree : List (List String) -> List (Html msg) -> List (List (Html msg))
drawTree listAll htmlAggregation =
    List.indexedMap
        (\indO elem ->
            List.indexedMap
                (\indI elemInner ->
                    div
                        [ Html.Attributes.style "font-family" "consolas"
                        , Html.Attributes.style "z-index" "100"
                        , Html.Attributes.style "padding" "10px 15px"
                        , Html.Attributes.style "position" "absolute"
                        , Html.Attributes.style "background-color" "#333"
                        , Html.Attributes.style "color" "rgb(96, 202, 245)"
                        , Html.Attributes.style "border-top" "3px solid rgb(90, 196, 229)"
                        , Html.Attributes.style "border-bottom" "3px solid rgb(90, 196, 229)"
                        , Html.Attributes.style "box-shadow" "2px 3px 3px #999, -1px 1px 2px #999"
                        , Html.Attributes.style "top" (String.fromInt (400 + ((indO + indI) * 60)) ++ "px")
                        , Html.Attributes.style "left" (String.fromFloat (30 + previousIndexMax listAll (indO - 1) 0 positionsX * 12.3) ++ "px")
                        ]
                        [ Html.text (String.replace "]" "" (String.replace "[" "" elemInner)) ]
                )
                elem
        )
        listAll


displayTextTree : List (List String) -> List (Html msg)
displayTextTree listAll =
    List.map
        (\i ->
            div
                [ Html.Attributes.style "font-family" "consolas"
                , Html.Attributes.style "background-color" "rgb(96, 202, 245)"
                , Html.Attributes.style "color" "#111"
                , Html.Attributes.style "margin-bottom" "5px"
                , Html.Attributes.style "padding" "10px 20px"
                ]
                (List.map
                    (\j ->
                        div
                            []
                            [ Html.text j ]
                    )
                    i
                )
        )
        listAll


positionsX : List Float
positionsX =
    []


isVisible : List Int -> Int -> String
isVisible l ind =
    if List.member ind l then
        "block"

    else
        "none"


update : Msg -> Model -> Model
update msg model =
    case msg of
        Open ->
            model ++ [ 0, 1, 2, 3, 4, 5, 6, 7, 8 ]


type Msg
    = Open


outerView : Model -> String -> Html Msg
outerView model str =
    div [ onClick Open ] [ view model str ]


view model stringy1 =
    let
        listy =
            populatePositions (createTreeFromString absString) 0 0 []
    in
    div []
        [ div []
            [ div []
                (List.indexedMap
                    (\ind p ->
                        let
                            visible =
                                isVisible model ind
                        in
                        div []
                            [ div
                                [ Html.Attributes.style "display" visible
                                , Html.Attributes.class ("tree-container-" ++ String.fromInt ind)
                                ]
                                p
                            ]
                    )
                    (drawTree (createTreeFromString stringy1) [])
                )
            ]
        , svg
            [ Svg.Attributes.width "1200"
            , Svg.Attributes.height "1200"
            , viewBox "0 0 1200 1200"
            , Html.Attributes.style "position" "absolute"
            ]
            (List.concat
                (List.indexedMap
                    (\ind1 elm ->
                        [ polygon [ fill "#6ec0ff", points ("" ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (425 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt (425 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt (460 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (460 + (ind1 * 60))) ] []
                        , polygon [ fill "#6ec0ff", points ("" ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (550 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (590 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt (590 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt (425 + (ind1 * 60))) ] []
                        , polygon [ fill "#6ec0ff", points ("" ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ ",610 " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ ",650 " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ ",650 " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ ",610") ] []
                        , polygon [ fill "#6ec0ff", points (String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (425 + ((ind1 + 1) * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop ind1 listy)) * 12.3) + 55) ++ "," ++ String.fromInt (425 + ((ind1 + 1) * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop ind1 listy)) * 12.3) + 55) ++ "," ++ String.fromInt (430 + ((ind1 + 1) * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop 1 listy)) * 12.3) + 55) ++ "," ++ String.fromInt (430 + ((ind1 + 1) * 60))) ] []
                        ]
                    )
                    (List.map (\e -> Just e) listy)
                )
            )
        ]
