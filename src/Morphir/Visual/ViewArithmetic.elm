module Morphir.Visual.ViewArithmetic exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, centerX, column, padding, paddingEach, rgb, row, spacing, text, width)
import Element.Border as Border
import Morphir.Visual.Components.AritmeticExpressions exposing (ArithmeticOperator(..), ArithmeticOperatorTree(..))
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding, smallSpacing)


view : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> ArithmeticOperatorTree -> Element msg
view config viewValue arithmeticOperatorTree =
    let
        reduceZIndex : Int -> Config msg -> Config msg
        reduceZIndex i conf =
            let
                state : Morphir.Visual.Config.VisualState
                state =
                    conf.state
            in
            { conf | state = { state | zIndex = state.zIndex - i } }
    in
    case arithmeticOperatorTree of
        ArithmeticOperatorBranch arithmeticOperator arithmeticOperatorTrees ->
            let
                separator =
                    row
                        [ spacing 5
                        , width Element.fill
                        , centerX
                        ]
                        [ text (Maybe.withDefault "" (Dict.get (functionNameHelper arithmeticOperator) inlineBinaryOperators))
                        ]
            in
            arithmeticOperatorTrees
                |> List.indexedMap
                    (\ind a -> view (config |> reduceZIndex ind) viewValue a)
                |> List.indexedMap
                    (\i b ->
                        if dropInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator && i < List.length arithmeticOperatorTrees - 1 then
                            row
                                [ padding 2
                                , spacing 5
                                , centerX
                                ]
                                [ text "(", b, text ")", separator ]

                        else if dropInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator then
                            row
                                [ padding 2
                                , spacing 5
                                , centerX
                                ]
                                [ text "(", b, text ")" ]

                        else if riseInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator && i < List.length arithmeticOperatorTrees - 1 then
                            row
                                [ padding 2
                                , spacing 5
                                , centerX
                                ]
                                [ b, separator ]

                        else if riseInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator then
                            row
                                [ padding 2
                                , spacing 5
                                , centerX
                                ]
                                [ b ]

                        else if i < List.length arithmeticOperatorTrees - 1 then
                            row
                                [ padding 2
                                , spacing 5
                                , centerX
                                ]
                                [ b, separator ]

                        else
                            row
                                [ padding 2
                                , spacing 5
                                , centerX
                                ]
                                [ b ]
                    )
                |> Element.row [ spacing 5, width Element.fill, centerX ]

        ArithmeticDivisionBranch [ arithmeticOperatorTree1, arithmeticOperatorTree2 ] ->
            case arithmeticOperatorTree1 of
                ArithmeticValueLeaf typedValue1 ->
                    case arithmeticOperatorTree2 of
                        ArithmeticValueLeaf typedValue2 ->
                            row [ centerX, width Element.fill, spacing 5 ]
                                [ column [ centerX, width Element.fill ]
                                    [ row [ centerX, width Element.fill ]
                                        [ row
                                            [ width Element.fill
                                            , smallSpacing config.state.theme |> spacing
                                            , Border.color (rgb 0 0.7 0)
                                            , smallPadding config.state.theme |> padding
                                            , centerX
                                            ]
                                            [ viewValue (config |> reduceZIndex 2) typedValue1
                                            ]
                                        ]
                                    , row
                                        [ centerX
                                        , width Element.fill
                                        , Border.solid
                                        , Border.widthEach { bottom = 0, left = 0, right = 0, top = 1 }
                                        , smallPadding config.state.theme |> padding
                                        ]
                                        [ viewValue (config |> reduceZIndex 3) typedValue2
                                        ]
                                    ]
                                ]

                        ArithmeticOperatorBranch arithmeticOperator arithmeticOperatorTrees ->
                            case arithmeticOperator of
                                _ ->
                                    let
                                        separator =
                                            row
                                                [ smallSpacing config.state.theme |> spacing
                                                , width Element.fill
                                                , centerX
                                                ]
                                                [ text (Maybe.withDefault "" (Dict.get (functionNameHelper arithmeticOperator) inlineBinaryOperators))
                                                ]

                                        mainBody =
                                            arithmeticOperatorTrees
                                                |> List.indexedMap
                                                    (\ind a -> view (config |> reduceZIndex ind) viewValue a)
                                                |> List.indexedMap
                                                    (\i b ->
                                                        if dropInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator && i < List.length arithmeticOperatorTrees - 1 then
                                                            row
                                                                [ padding 2
                                                                , spacing 5
                                                                , centerX
                                                                ]
                                                                [ text "(", b, text ")", separator ]

                                                        else if dropInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator then
                                                            row
                                                                [ padding 2
                                                                , spacing 5
                                                                , centerX
                                                                ]
                                                                [ text "(", b, text ")" ]

                                                        else if riseInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator && i < List.length arithmeticOperatorTrees - 1 then
                                                            row
                                                                [ padding 2
                                                                , spacing 5
                                                                , centerX
                                                                ]
                                                                [ b, separator ]

                                                        else if riseInPrecedence arithmeticOperatorTrees i 0 (currentPrecedence (functionName arithmeticOperator)) arithmeticOperator then
                                                            row
                                                                [ padding 2
                                                                , spacing 5
                                                                , centerX
                                                                ]
                                                                [ b ]

                                                        else if i < List.length arithmeticOperatorTrees - 1 then
                                                            row
                                                                [ padding 2
                                                                , spacing 5
                                                                , centerX
                                                                ]
                                                                [ b, separator ]

                                                        else
                                                            row
                                                                [ padding 2
                                                                , spacing 5
                                                                , centerX
                                                                ]
                                                                [ b ]
                                                    )
                                    in
                                    column [ centerX, width Element.fill ]
                                        [ row [ centerX, width Element.fill ]
                                            [ row
                                                [ spacing 5
                                                , Border.color (rgb 0 0.7 0)
                                                , paddingEach { left = 0, top = 0, right = 0, bottom = 4 }
                                                , centerX
                                                ]
                                                [ viewValue (config |> reduceZIndex 1) typedValue1
                                                ]
                                            ]
                                        , row
                                            [ centerX
                                            , width Element.fill
                                            , Border.solid
                                            , Border.widthEach { bottom = 0, left = 0, right = 0, top = 1 }
                                            , paddingEach { left = 0, bottom = 0, right = 0, top = 10 }
                                            ]
                                            [ Element.row [ spacing 5, width Element.fill, centerX ] mainBody
                                            ]
                                        ]

                        _ ->
                            Element.none

                _ ->
                    Element.none

        ArithmeticValueLeaf typedValue ->
            viewValue (config |> reduceZIndex 1) typedValue

        _ ->
            Element.none


inlineBinaryOperators : Dict String String
inlineBinaryOperators =
    Dict.fromList
        [ ( "Basics.equal", "=" )
        , ( "Basics.lessThan", "<" )
        , ( "Basics.lessThanOrEqual", "<=" )
        , ( "Basics.greaterThan", ">" )
        , ( "Basics.greaterThanOrEqual", ">=" )
        , ( "Add", "+" )
        , ( "Subtract", "-" )
        , ( "Multiply", "*" )
        ]


nextOperator : List ArithmeticOperatorTree -> Int -> Int -> Bool
nextOperator arithmeticOperatorTrees index currentPointer =
    if currentPointer < index then
        nextOperator (List.drop 1 arithmeticOperatorTrees) index (currentPointer + 1)

    else
        case List.head arithmeticOperatorTrees of
            Just (ArithmeticDivisionBranch _) ->
                True

            Just (ArithmeticValueLeaf _) ->
                False

            Just (ArithmeticOperatorBranch _ _) ->
                False

            Nothing ->
                False


dropInPrecedence : List ArithmeticOperatorTree -> Int -> Int -> Int -> ArithmeticOperator -> Bool
dropInPrecedence arithmeticOperatorTrees index currentPointer currentPrecedenceValue previousOperator =
    if currentPointer < index then
        dropInPrecedence (List.drop 1 arithmeticOperatorTrees) index (currentPointer + 1) currentPrecedenceValue previousOperator

    else
        case List.head arithmeticOperatorTrees of
            Just a ->
                case a of
                    ArithmeticOperatorBranch arithmeticOperator arithmeticOperatorTrees1 ->
                        case arithmeticOperator of
                            _ ->
                                if currentPrecedence (functionName arithmeticOperator) < currentPrecedence (functionName previousOperator) then
                                    True

                                else
                                    False

                    ArithmeticValueLeaf typedValue ->
                        dropInPrecedence (List.drop 2 arithmeticOperatorTrees) index (currentPointer + 2) currentPrecedenceValue previousOperator

                    ArithmeticDivisionBranch [ arithmeticOperatorTree, arithmeticOperatorTree1 ] ->
                        if currentPrecedence "Basics.divide" < currentPrecedence (functionName previousOperator) then
                            True

                        else
                            False

                    _ ->
                        False

            Nothing ->
                False


riseInPrecedence : List ArithmeticOperatorTree -> Int -> Int -> Int -> ArithmeticOperator -> Bool
riseInPrecedence arithmeticOperatorTrees index currentPointer currentPrecedenceValue previousOperator =
    if currentPointer < index then
        riseInPrecedence (List.drop 1 arithmeticOperatorTrees) index (currentPointer + 1) currentPrecedenceValue previousOperator

    else
        case List.head arithmeticOperatorTrees of
            Just a ->
                case a of
                    ArithmeticOperatorBranch arithmeticOperator arithmeticOperatorTrees1 ->
                        case arithmeticOperator of
                            _ ->
                                if currentPrecedence (functionName arithmeticOperator) > currentPrecedence (functionName previousOperator) then
                                    True

                                else
                                    False

                    ArithmeticValueLeaf typedValue ->
                        riseInPrecedence (List.drop 2 arithmeticOperatorTrees) index (currentPointer + 2) currentPrecedenceValue previousOperator

                    ArithmeticDivisionBranch [ arithmeticOperatorTree, arithmeticOperatorTree1 ] ->
                        if currentPrecedence "Basics.divide" > currentPrecedence (functionName previousOperator) then
                            True

                        else
                            False

                    _ ->
                        False

            Nothing ->
                False


functionName : ArithmeticOperator -> String
functionName ao =
    case ao of
        Add ->
            "Basics.add"

        Subtract ->
            "Basics.subtract"

        Multiply ->
            "Basics.multiply"


functionNameHelper : ArithmeticOperator -> String
functionNameHelper ao =
    case ao of
        Add ->
            "Add"

        Subtract ->
            "Subtract"

        Multiply ->
            "Multiply"


currentPrecedence : String -> Int
currentPrecedence operatorName =
    case operatorName of
        "Basics.add" ->
            1

        "Basics.subtract" ->
            1

        "Basics.multiply" ->
            2

        "Basics.divide" ->
            2

        _ ->
            0
