module Morphir.Visual.Components.DecisionTree exposing (BranchNode, LeftOrRight(..), Node(..), defaultColor, downArrow, downArrowHead, highlightColor, horizontalLayout, layout, noPadding, rightArrow, rightArrowHead, verticalLayout)

import Element exposing (Color, Element, alignLeft, alignTop, centerX, centerY, column, el, explain, fill, height, html, padding, paddingEach, paddingXY, rgb, row, shrink, spacing, text, width)
import Element.Border as Border
import Html exposing (Html)
import Html.Attributes
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (TypedValue)
import Morphir.Visual.Common exposing (element)
import Morphir.Visual.Context exposing (Context)
import Svg
import Svg.Attributes


type Node
    = Branch BranchNode
    | Leaf TypedValue


type alias BranchNode =
    { condition : TypedValue
    , thenBranch : Node
    , elseBranch : Node
    }


type LeftOrRight
    = Left
    | Right


defaultColor =
    "black"


highlightColor =
    "green"


layout : Context -> (TypedValue -> Element msg) -> Node -> Element msg
layout ctx viewValue rootNode =
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
                borderColor : Color
                borderColor =
                    case ctx.evaluate (Value.toRawValue branch.condition) |> Debug.log "eval" of
                        Ok (Value.Literal _ (BoolLiteral v)) ->
                            if v then
                                rgb 0 1 0

                            else
                                rgb 1 0 0

                        _ ->
                            rgb 0.4 0.4 0.4
            in
            -- TODO: choose vertical/horizontal left/right layout based on some heuristics
            horizontalLayout
                (el
                    [ Border.width 2
                    , Border.rounded 7
                    , Border.color borderColor
                    , padding 10
                    ]
                    (viewValue branch.condition)
                )
                (text "Yes")
                (layout ctx viewValue branch.thenBranch)
                (text "No")
                (layout ctx viewValue branch.elseBranch)

        Leaf value ->
            el
                [ Border.width 1
                , Border.rounded 7
                , padding 10
                ]
                (viewValue value)


horizontalLayout : Element msg -> Element msg -> Element msg -> Element msg -> Element msg -> Element msg
horizontalLayout condition branch1Label branch1 branch2Label branch2 =
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
                        , spacing 10
                        ]
                        [ el
                            [ paddingEach { noPadding | left = 10 }
                            , height fill
                            ]
                            (downArrow defaultColor)
                        , el
                            [ centerY
                            , paddingXY 0 15
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
                        , paddingEach { noPadding | top = 10 }
                        ]
                        (rightArrow defaultColor)
                    , el
                        [ centerX
                        , paddingXY 20 5
                        ]
                        branch2Label
                    ]
                ]
            , el
                [ paddingEach { noPadding | right = 40 }
                ]
                branch1
            ]
        , el
            [ alignTop
            ]
            branch2
        ]


verticalLayout : Element msg -> Element msg -> Element msg -> Element msg -> Element msg -> Element msg
verticalLayout condition branch1Label branch1 branch2Label branch2 =
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
                    , spacing 10
                    ]
                    [ el
                        [ paddingEach { noPadding | left = 10 }
                        , height fill
                        ]
                        (downArrow defaultColor)
                    , el
                        [ centerY
                        , paddingXY 0 10
                        ]
                        branch1Label
                    ]
                ]
            , column [ alignTop ]
                [ el
                    [ width fill
                    , paddingEach { noPadding | top = 5 }
                    ]
                    (rightArrow defaultColor)
                , el [ centerX, paddingXY 10 0 ]
                    branch2Label
                ]
            , el [ alignTop, paddingEach { noPadding | bottom = 20 } ] branch2
            ]
        , branch1
        ]


rightArrow : String -> Element msg
rightArrow color =
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
                    [ Html.td [ Html.Attributes.style "border-bottom" ("solid 2px " ++ color), Html.Attributes.style "width" "100%" ] []
                    , Html.td
                        [ Html.Attributes.rowspan 2 ]
                        [ element
                            (el
                                [ centerY ]
                                (html (rightArrowHead color))
                            )
                        ]
                    ]
                , Html.tr []
                    [ Html.td [] []
                    ]
                ]
            )
        )


downArrow : String -> Element msg
downArrow color =
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
                    [ Html.td [ Html.Attributes.style "border-right" ("solid 2px " ++ color) ] []
                    , Html.td [] []
                    ]
                , Html.tr []
                    [ Html.td
                        [ Html.Attributes.colspan 2 ]
                        [ element
                            (el
                                [ centerX ]
                                (html (downArrowHead color))
                            )
                        ]
                    ]
                ]
            )
        )


rightArrowHead : String -> Html msg
rightArrowHead color =
    Svg.svg
        [ Svg.Attributes.width "10"
        , Svg.Attributes.height "10"
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 200,100 0,200"
            , Svg.Attributes.style ("fill:" ++ color)
            ]
            []
        ]


downArrowHead : String -> Html msg
downArrowHead color =
    Svg.svg
        [ Svg.Attributes.width "10"
        , Svg.Attributes.height "10"
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 100,200 200,0"
            , Svg.Attributes.style ("fill:" ++ color)
            ]
            []
        ]


noPadding =
    { right = 0
    , left = 0
    , top = 0
    , bottom = 0
    }
