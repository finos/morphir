module Morphir.Visual.Components.DecisionTree exposing (BranchNode, LeftOrRight(..), Node(..), downArrow, downArrowHead, highlightColor, horizontalLayout, layout, noPadding, rightArrow, rightArrowHead, verticalLayout)

import Element exposing (Attribute, Color, Element, alignLeft, alignTop, centerX, centerY, column, el, fill, height, html, padding, paddingEach, paddingXY, rgb255, row, shrink, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Html exposing (Html)
import Html.Attributes
import Morphir.IR.Value exposing (RawValue, TypedValue)
import Morphir.Visual.Common exposing (element)
import Morphir.Visual.Config exposing (Config)
import Svg
import Svg.Attributes


type Node
    = Branch BranchNode
    | Leaf TypedValue


type alias BranchNode =
    { condition : TypedValue
    , conditionValue : Maybe Bool
    , thenBranch : Node
    , elseBranch : Node
    }


type LeftOrRight
    = Left
    | Right


highlightColor =
    { true = Color 100 180 100
    , false = Color 180 100 100
    , default = Color 120 120 120
    }


type Color
    = Color Int Int Int


type HighlightState
    = Highlighted Bool
    | NotHighlighted


highlighStateToColor : HighlightState -> Color
highlighStateToColor state =
    case state of
        Highlighted bool ->
            if bool then
                highlightColor.true

            else
                highlightColor.false

        NotHighlighted ->
            highlightColor.default


highlighStateToBorderWidth : HighlightState -> Int
highlighStateToBorderWidth state =
    case state of
        Highlighted _ ->
            4

        NotHighlighted ->
            2


highlighStateToFontWeight : HighlightState -> Attribute msg
highlighStateToFontWeight state =
    case state of
        Highlighted _ ->
            Font.bold

        NotHighlighted ->
            Font.regular


toElementColor : Color -> Element.Color
toElementColor (Color r g b) =
    rgb255 r g b


toCssColor : Color -> String
toCssColor (Color r g b) =
    String.concat [ "rgb(", String.fromInt r, ",", String.fromInt g, ",", String.fromInt b, ")" ]


layout : Config msg -> (TypedValue -> Element msg) -> Node -> Element msg
layout config viewValue rootNode =
    layoutHelp config NotHighlighted viewValue rootNode


layoutHelp : Config msg -> HighlightState -> (TypedValue -> Element msg) -> Node -> Element msg
layoutHelp config highlightState viewValue rootNode =
    let
        depthOf : (BranchNode -> Node) -> Node -> Int
        depthOf f node =
            case node of
                Branch branch ->
                    depthOf f (f branch) + 1

                Leaf _ ->
                    1
    in
    case rootNode of
        Branch branch ->
            let
                conditionState : HighlightState
                conditionState =
                    case branch.conditionValue of
                        Just v ->
                            Highlighted v

                        _ ->
                            NotHighlighted

                thenState : HighlightState
                thenState =
                    case branch.conditionValue of
                        Just v ->
                            if v then
                                Highlighted True

                            else
                                NotHighlighted

                        _ ->
                            NotHighlighted

                elseState : HighlightState
                elseState =
                    case branch.conditionValue of
                        Just v ->
                            if v then
                                NotHighlighted

                            else
                                Highlighted False

                        _ ->
                            NotHighlighted
            in
            -- TODO: choose vertical/horizontal left/right layout based on some heuristics
            horizontalLayout
                config
                (el
                    [ conditionState |> highlighStateToBorderWidth |> Border.width
                    , Border.rounded 7
                    , Border.color (conditionState |> highlighStateToColor |> toElementColor)
                    , padding config.state.theme.mediumPadding
                    ]
                    (viewValue branch.condition)
                )
                (el
                    [ Font.color (thenState |> highlighStateToColor |> toElementColor)
                    , thenState |> highlighStateToFontWeight
                    ]
                    (text "Yes")
                )
                thenState
                (layoutHelp config thenState viewValue branch.thenBranch)
                (el
                    [ Font.color (elseState |> highlighStateToColor |> toElementColor)
                    , elseState |> highlighStateToFontWeight
                    ]
                    (text "No")
                )
                elseState
                (layoutHelp config elseState viewValue branch.elseBranch)

        Leaf value ->
            el
                [ highlightState |> highlighStateToBorderWidth |> Border.width
                , Border.rounded 7
                , Border.color (highlightState |> highlighStateToColor |> toElementColor)
                , padding config.state.theme.mediumPadding
                ]
                (viewValue value)


horizontalLayout : Config msg -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg
horizontalLayout config condition branch1Label branch1State branch1 branch2Label branch2State branch2 =
    row
        []
        [ column
            [ alignTop
            ]
            [ row
                [ width fill
                ]
                [ column
                    [ alignTop
                    , width shrink
                    ]
                    [ el [ width shrink ]
                        condition
                    , row
                        [ alignLeft
                        , height fill
                        , width fill
                        , spacing config.state.theme.smallSpacing
                        ]
                        [ el
                            [ paddingEach { noPadding | left = config.state.theme.mediumPadding }
                            , height fill
                            ]
                            (downArrow branch1State)
                        , el
                            [ centerY
                            , paddingXY 0 config.state.theme.largePadding
                            ]
                            branch1Label
                        ]
                    ]
                , column
                    [ alignTop
                    , width fill
                    ]
                    [ el
                        [ width fill
                        , paddingEach { noPadding | top = config.state.theme.mediumPadding }
                        ]
                        (rightArrow branch2State)
                    , el
                        [ centerX
                        , padding config.state.theme.mediumPadding
                        ]
                        branch2Label
                    ]
                ]
            , el
                [ paddingEach { noPadding | right = config.state.theme.largePadding }
                ]
                branch1
            ]
        , el
            [ alignTop
            ]
            branch2
        ]


verticalLayout : Config msg -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg -> HighlightState -> Element msg -> Element msg
verticalLayout config condition branch1Label branch1State branch1 branch2Label branch2State branch2 =
    column
        []
        [ row []
            [ column
                [ alignTop
                , height fill
                ]
                [ condition
                , row
                    [ alignLeft
                    , height fill
                    , width fill
                    , spacing config.state.theme.mediumSpacing
                    ]
                    [ el
                        [ paddingEach { noPadding | left = config.state.theme.mediumPadding }
                        , height fill
                        ]
                        (downArrow branch1State)
                    , el
                        [ centerY
                        , paddingXY 0 config.state.theme.mediumPadding
                        ]
                        branch1Label
                    ]
                ]
            , column [ alignTop ]
                [ el
                    [ width fill
                    , paddingEach { noPadding | top = config.state.theme.smallPadding }
                    ]
                    (rightArrow branch2State)
                , el [ centerX, paddingXY config.state.theme.mediumPadding 0 ]
                    branch2Label
                ]
            , el [ alignTop, paddingEach { noPadding | bottom = config.state.theme.largePadding } ] branch2
            ]
        , branch1
        ]


rightArrow : HighlightState -> Element msg
rightArrow highlightState =
    el
        [ width fill
        , height fill
        ]
        (html
            (Html.table
                [ Html.Attributes.style "border-collapse" "collapse"
                , Html.Attributes.style "width" "100%"
                ]
                [ Html.tr []
                    [ Html.td
                        [ Html.Attributes.style "border-bottom" (String.concat [ "solid ", highlightState |> highlighStateToBorderWidth |> String.fromInt, "px ", highlightState |> highlighStateToColor |> toCssColor ])
                        , Html.Attributes.style "width" "100%"
                        ]
                        []
                    , Html.td
                        [ Html.Attributes.rowspan 2 ]
                        [ element
                            (el
                                [ centerY ]
                                (html (rightArrowHead highlightState))
                            )
                        ]
                    ]
                , Html.tr []
                    [ Html.td [] []
                    ]
                ]
            )
        )


downArrow : HighlightState -> Element msg
downArrow highlightState =
    el
        [ width fill
        , height fill
        ]
        (html
            (Html.table
                [ Html.Attributes.style "border-collapse" "collapse"
                , Html.Attributes.style "height" "100%"
                ]
                [ Html.tr [ Html.Attributes.style "height" "100%" ]
                    [ Html.td [ Html.Attributes.style "border-right" (String.concat [ "solid ", highlightState |> highlighStateToBorderWidth |> String.fromInt, "px ", highlightState |> highlighStateToColor |> toCssColor ]) ] []
                    , Html.td [] []
                    ]
                , Html.tr []
                    [ Html.td
                        [ Html.Attributes.colspan 2 ]
                        [ element
                            (el
                                [ centerX ]
                                (html (downArrowHead highlightState))
                            )
                        ]
                    ]
                ]
            )
        )


rightArrowHead : HighlightState -> Html msg
rightArrowHead highlightState =
    Svg.svg
        [ Svg.Attributes.width
            (if highlightState == NotHighlighted then
                "10"

             else
                "15"
            )
        , Svg.Attributes.height
            (if highlightState == NotHighlighted then
                "10"

             else
                "15"
            )
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 200,100 0,200"
            , Svg.Attributes.style ("fill:" ++ (highlightState |> highlighStateToColor |> toCssColor))
            ]
            []
        ]


downArrowHead : HighlightState -> Html msg
downArrowHead highlightState =
    Svg.svg
        [ Svg.Attributes.width
            (if highlightState == NotHighlighted then
                "10"

             else
                "15"
            )
        , Svg.Attributes.height
            (if highlightState == NotHighlighted then
                "10"

             else
                "15"
            )
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 100,200 200,0"
            , Svg.Attributes.style ("fill:" ++ (highlightState |> highlighStateToColor |> toCssColor))
            ]
            []
        ]


noPadding =
    { right = 0
    , left = 0
    , top = 0
    , bottom = 0
    }
