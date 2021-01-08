module Morphir.Visual.Components.DecisionTree exposing (..)

import Element exposing (Element, alignLeft, alignTop, centerX, centerY, column, el, explain, fill, height, html, padding, paddingEach, paddingXY, row, shrink, spacing, text, width)
import Element.Border as Border
import Html exposing (Html)
import Html.Attributes


type Node a
    = Branch (BranchNode a)
    | Leaf a


type alias BranchNode a =
    { nodeLabel : a
    , leftBranchLabel : a
    , leftBranch : Node a
    , rightBranchLabel : a
    , rightBranch : Node a
    }


layout : (a -> Element msg) -> Node a -> Element msg
layout viewA rootNode =
    let
        depthOf : (BranchNode a -> Node a) -> Node a -> Int
        depthOf f node =
            case node of
                Branch branch ->
                    depthOf f (f branch) + 1

                Leaf _ ->
                    1
    in
    case rootNode of
        Branch branch ->
            -- TODO: choose vertical/horizontal left/right layout based on some heuristics
            horizontalLayout
                (el
                    [ Border.width 1
                    , Border.rounded 7
                    , padding 10
                    ]
                    (viewA branch.nodeLabel)
                )
                (viewA branch.leftBranchLabel)
                (layout viewA branch.leftBranch)
                (viewA branch.rightBranchLabel)
                (layout viewA branch.rightBranch)

        Leaf label ->
            el
                [ Border.width 1
                , Border.rounded 7
                , padding 10
                ]
                (viewA label)


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
                            downArrow
                        , el
                            [ centerY
                            , paddingXY 0 10
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
                        , paddingEach { noPadding | top = 5 }
                        ]
                        rightArrow
                    , el
                        [ centerX
                        , paddingXY 10 0
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
                        downArrow
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
                    rightArrow
                , el [ centerX, paddingXY 10 0 ]
                    branch2Label
                ]
            , el [ alignTop, paddingEach { noPadding | bottom = 20 } ] branch2
            ]
        , branch1
        ]


element : Element msg -> Html msg
element elem =
    Element.layoutWith
        { options =
            [ Element.noStaticStyleSheet
            ]
        }
        [ width shrink
        , height shrink
        ]
        elem


rightArrow : Element msg
rightArrow =
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
                    [ Html.td [ Html.Attributes.style "border-bottom" "solid 2px black", Html.Attributes.style "width" "100%" ] []
                    , Html.td
                        [ Html.Attributes.rowspan 2 ]
                        [ element
                            (el
                                [ centerY ]
                                (text ">")
                            )
                        ]
                    ]
                , Html.tr []
                    [ Html.td [] []
                    ]
                ]
            )
        )


downArrow : Element msg
downArrow =
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
                    [ Html.td [ Html.Attributes.style "border-right" "solid 2px black" ] []
                    , Html.td [] []
                    ]
                , Html.tr []
                    [ Html.td
                        [ Html.Attributes.colspan 2 ]
                        [ element
                            (el
                                [ centerX ]
                                (text "V")
                            )
                        ]
                    ]
                ]
            )
        )


noPadding =
    { right = 0
    , left = 0
    , top = 0
    , bottom = 0
    }
