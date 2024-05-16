module Morphir.AbstractTreeVisualizer exposing (..)

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import List
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Value exposing (Value(..))
import Morphir.Visual.Components.AritmeticExpressions exposing (ArithmeticOperator(..), ArithmeticOperatorTree(..))
import Svg exposing (..)
import Svg.Attributes exposing (..)
import Morphir.SDK.Decimal exposing (Decimal)
import UUID
import Decimal



-- Add line below to ( else if Basics.isNumber valueType then ) branch to visualize AST
-- Element.column [] [ ViewArithmetic.view (viewValueByLanguageFeature ctx argumentValues) arithmeticOperatorTree, Element.html (div [ Html.Attributes.style "display" "block", Html.Attributes.style "padding" "10", Html.Attributes.style "background-color" "rgb (50 50 50)", Html.Attributes.style "font-size" "16", Html.Attributes.style "color" "rgb(255 78 185 255)" ] [ view [] (parseArithmeticOperatorTree arithmeticOperatorTree) ]) ]


type alias Model =
    List Int


initialModel : Model
initialModel =
    []


chopWord : List Int -> Int -> Int -> String -> List String -> List String
chopWord indices beg end stringy listy =
    if List.length indices > 0 then
        chopWord (List.drop 1 indices) (end + 2) (Maybe.withDefault 0 (List.head (List.drop 1 indices))) stringy (listy ++ [ String.slice beg end stringy ])

    else
        listy ++ [ String.slice beg (String.length stringy) stringy ]


createTreeFromString : String -> List (List String)
createTreeFromString inputString =
    chopWord (String.indexes "," inputString) 0 (Maybe.withDefault 0 (List.head (String.indexes "," inputString))) inputString []
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
                        , Html.Attributes.style "top" (String.fromInt (425 + ((indO + indI) * 60)) ++ "px")
                        , Html.Attributes.style "left" (String.fromFloat (30 + previousIndexMax listAll (indO - 1) 0 [] * 12.3) ++ "px")
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


findLastString : List Float -> Maybe Float -> Int -> String
findLastString listy elm ind1 =
    if ind1 == 0 then
        String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (400 + ((ind1 + 1) * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop ind1 listy)) * 12.3) + 55) ++ "," ++ String.fromInt (405 + ((ind1 + 1) * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop 1 listy)) * 12.3) + 55) ++ "," ++ String.fromInt (405 + ((ind1 + 1) * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop 1 listy)) * 12.3) + 55) ++ "," ++ String.fromInt (400 + ((ind1 + 1) * 60))

    else
        String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (400 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop ind1 listy)) * 12.3) + 55) ++ "," ++ String.fromInt (405 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop (ind1 - 1) listy)) * 12.3) + 55) ++ "," ++ String.fromInt (405 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 (List.head (List.drop (ind1 - 1) listy)) * 12.3) + 55) ++ "," ++ String.fromInt (400 + (ind1 * 60))


view model stringy1 =
    let
        listy =
            populatePositions (createTreeFromString stringy1) 0 0 []

        tough =
            Debug.log "daily visit    " stringy1
    in
    div []
        [ div []
            [ div []
                (List.indexedMap
                    (\ind p ->
                        div []
                            [ div
                                [ Html.Attributes.style "display" "block"
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
                        [ polygon [ fill "#6ec0ff", points ("" ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (400 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt (400 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt (450 + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt (450 + (ind1 * 60))) ] []
                        , polygon [ fill "#6ec0ff", points (findLastString listy elm ind1) ] []
                        ]
                            ++ List.concat
                                (List.indexedMap
                                    (\ind3 ni ->
                                        if ind3 == ind1 then
                                            List.indexedMap
                                                (\ind2 ne ->
                                                    if ind2 < (List.length ni - 2) then
                                                        polygon [ fill "#6ec0ff", points ("" ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt ((480 + (40 * ind2)) + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 55) ++ "," ++ String.fromInt ((520 + (40 * ind2)) + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt ((520 + (40 * ind2)) + (ind1 * 60)) ++ " " ++ String.fromFloat ((Maybe.withDefault 0.0 elm * 12.3) + 50) ++ "," ++ String.fromInt ((480 + (40 * ind2)) + (ind1 * 60))) ] []

                                                    else
                                                        circle [ cx "60", cy "60", r "0" ] []
                                                )
                                                ni

                                        else
                                            []
                                    )
                                    (drawTree (createTreeFromString stringy1) [])
                                )
                    )
                    (List.map (\e -> Just e) listy)
                )
            )
        ]


parseArithmeticOperatorTree : ArithmeticOperatorTree -> String
parseArithmeticOperatorTree arithmeticOperatorTree =
    case arithmeticOperatorTree of
        ArithmeticValueLeaf typedValue ->
            helperFunctionValue typedValue

        ArithmeticDivisionBranch [ arithmeticOperatorTree1, arithmeticOperatorTree2 ] ->
            "ADB" ++ " -> Divide -> [ " ++ parseArithmeticOperatorTree arithmeticOperatorTree1 ++ " , " ++ parseArithmeticOperatorTree arithmeticOperatorTree2 ++ " ]"

        ArithmeticOperatorBranch arithmeticOperator arithmeticOperatorTrees ->
            case arithmeticOperator of
                Add ->
                    "AOB" ++ " -> Add -> [ " ++ String.join " , " (List.map parseArithmeticOperatorTree arithmeticOperatorTrees) ++ " ]"

                Subtract ->
                    "AOB" ++ " -> Subtract -> [ " ++ String.join " , " (List.map parseArithmeticOperatorTree arithmeticOperatorTrees) ++ " ]"

                Multiply ->
                    "AOB" ++ " -> Multiply -> [ " ++ String.join " , " (List.map parseArithmeticOperatorTree arithmeticOperatorTrees) ++ " ]"

        _ ->
            ""


helperFunctionValue : Value ta va -> String
helperFunctionValue value1 =
    case value1 of
        Literal _ literal ->
            case literal of
                BoolLiteral bool ->
                    case bool of
                        True ->
                            "AVL (Bool) = True"

                        False ->
                            "AVL (Bool) = False"

                CharLiteral char ->
                    "AVL (char) = " ++ String.fromChar char

                StringLiteral string ->
                    "AVL (String) = " ++ string

                WholeNumberLiteral int ->
                    "AVL (Int) = " ++ String.fromInt int

                FloatLiteral float ->
                    "AVL (Float) = " ++ String.fromFloat float

                DecimalLiteral decimal ->
                    "AVL (Decimal) = " ++ Decimal.toString decimal

        Variable _ name ->
            "AVL (Variable) -> " ++ Name.toTitleCase name

        Reference va fQName ->
            "AVL (Reference) -> " ++ FQName.toString fQName

        Apply va value2 value3 ->
            "AVL (Apply): " ++ helperFunctionValue value2 ++ " __ " ++ helperFunctionValue value3

        _ ->
            "Some other format"
