module Morphir.Visual.Components.DecisionTree exposing (BranchNode, Node(..), downArrow, downArrowHead, horizontalLayout, layout, noPadding, rightArrow, rightArrowHead, verticalLayout)

import Dict
import Element exposing (Attribute, Color, Element, alignLeft, alignTop, centerX, centerY, column, el, fill, height, html, padding, paddingEach, paddingXY, rgb255, row, shrink, spacing, text, toRgb, width)
import Element.Border as Border
import Element.Font as Font
import Html exposing (Html)
import Html.Attributes
import Morphir.Value.Interpreter exposing (Variables)
import Morphir.Visual.Common exposing (element)
import Morphir.Visual.Config exposing (Config, HighlightState(..))
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (mediumPadding, mediumSpacing, smallPadding, smallSpacing)
import Svg
import Svg.Attributes


type Node
    = Branch BranchNode
    | Leaf Variables EnrichedValue


type alias BranchNode =
    { condition : EnrichedValue
    , isThenBranchSelected : Maybe Bool
    , thenBranch : Node
    , elseBranch : Node
    , thenLabel : String
    , elseLabel : String
    }


type Direction
    = Horizontal
    | Vertical


highlightStateToColor : Config msg -> Bool -> Color
highlightStateToColor config highlighted =
    if highlighted then
        config.state.theme.colors.highlighted

    else
        config.state.theme.colors.notHighlighted


highlightStateToBorderWidth : Bool -> Int
highlightStateToBorderWidth highlighted =
    if highlighted then
        4

    else
        2


highlightStateToFontWeight : Bool -> Attribute msg
highlightStateToFontWeight highlighted =
    if highlighted then
        Font.bold

    else
        Font.regular


toCssColor : Color -> String
toCssColor color =
    let
        rgb =
            toRgb color
    in
    String.concat [ "rgb(", String.fromFloat (rgb.red * 255), ",", String.fromFloat (rgb.green * 255), ",", String.fromFloat (rgb.blue * 255), ")" ]


layout : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> Node -> Element msg
layout config viewValue rootNode =
    layoutHelp Vertical config False viewValue rootNode


layoutHelp : Direction -> Config msg -> Bool -> (Config msg -> EnrichedValue -> Element msg) -> Node -> Element msg
layoutHelp currentDirection config highlightState viewValue rootNode =
    let
        stateConfig =
            config.state

        isThenBranchLonger : BranchNode -> Bool
        isThenBranchLonger node =
            let
                depthOf : (BranchNode -> Node) -> Node -> Int
                depthOf f n =
                    case n of
                        Branch branch ->
                            depthOf f (f branch) + 1

                        Leaf _ _ ->
                            1
            in
            max (depthOf .thenBranch node.thenBranch) (depthOf .elseBranch node.thenBranch) <= max (depthOf .thenBranch node.elseBranch) (depthOf .elseBranch node.elseBranch)
    in
    case rootNode of
        Branch branch ->
            let
                conditionState : Bool
                conditionState =
                    branch.isThenBranchSelected |> Maybe.map (always True) |> Maybe.withDefault False

                thenState : Bool
                thenState =
                    branch.isThenBranchSelected |> Maybe.withDefault False

                elseState : Bool
                elseState =
                    branch.isThenBranchSelected |> Maybe.map not |> Maybe.withDefault False

                thenBranchWithDirection : Direction -> Element msg
                thenBranchWithDirection direction =
                    layoutHelp direction { config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight thenState } } thenState viewValue branch.thenBranch

                elseBranchWithDirection : Direction -> Element msg
                elseBranchWithDirection direction =
                    layoutHelp direction { config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight elseState } } elseState viewValue branch.elseBranch

                conditionElement : Element msg
                conditionElement =
                    el
                        [ conditionState |> highlightStateToBorderWidth |> Border.width
                        , Border.rounded 6
                        , Border.color (conditionState |> highlightStateToColor config)
                        , smallPadding config.state.theme |> padding
                        , width fill
                        ]
                        (el [ centerX, centerY ] (viewValue { config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight conditionState } } branch.condition))

                oppositeDirection : Direction
                oppositeDirection =
                    case currentDirection of
                        Vertical ->
                            Horizontal

                        Horizontal ->
                            Vertical
            in
            if currentDirection == Vertical then
                verticalLayout
                    config
                    conditionElement
                    (if isThenBranchLonger branch then
                        el
                            [ Font.color (thenState |> highlightStateToColor config)
                            , thenState |> highlightStateToFontWeight
                            ]
                            (text branch.thenLabel)

                     else
                        el
                            [ Font.color (elseState |> highlightStateToColor config)
                            , elseState |> highlightStateToFontWeight
                            ]
                            (text branch.elseLabel)
                    )
                    (if isThenBranchLonger branch then
                        thenState

                     else
                        elseState
                    )
                    (if isThenBranchLonger branch then
                        thenBranchWithDirection currentDirection

                     else
                        elseBranchWithDirection oppositeDirection
                    )
                    (if isThenBranchLonger branch then
                        el
                            [ Font.color (elseState |> highlightStateToColor config)
                            , elseState |> highlightStateToFontWeight
                            ]
                            (text branch.elseLabel)

                     else
                        el
                            [ Font.color (thenState |> highlightStateToColor config)
                            , thenState |> highlightStateToFontWeight
                            ]
                            (text branch.thenLabel)
                    )
                    (if isThenBranchLonger branch then
                        elseState

                     else
                        thenState
                    )
                    (if isThenBranchLonger branch then
                        elseBranchWithDirection currentDirection

                     else
                        thenBranchWithDirection oppositeDirection
                    )

            else
                horizontalLayout
                    config
                    conditionElement
                    (el
                        [ Font.color (elseState |> highlightStateToColor config)
                        , elseState |> highlightStateToFontWeight
                        ]
                        (text branch.elseLabel)
                    )
                    elseState
                    (elseBranchWithDirection oppositeDirection)
                    (el
                        [ Font.color (thenState |> highlightStateToColor config)
                        , thenState |> highlightStateToFontWeight
                        ]
                        (text branch.thenLabel)
                    )
                    thenState
                    (thenBranchWithDirection currentDirection)

        Leaf variables value ->
            el
                [ highlightState |> highlightStateToBorderWidth |> Border.width
                , Border.rounded 6
                , Border.color (highlightState |> highlightStateToColor config)
                , smallPadding config.state.theme |> padding
                ]
                (viewValue { config | state = { stateConfig | highlightState = Just <| branchHighlightToConfigHighLight highlightState, variables = variables } } value)


horizontalLayout : Config msg -> Element msg -> Element msg -> Bool -> Element msg -> Element msg -> Bool -> Element msg -> Element msg
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
                    [ condition
                    , row
                        [ alignLeft
                        , height fill
                        , width fill
                        , smallSpacing config.state.theme |> spacing
                        ]
                        [ el
                            [ paddingEach { noPadding | left = mediumPadding config.state.theme }
                            , height fill
                            ]
                            (downArrow config branch1State)
                        , el
                            [ centerY
                            , paddingXY 0 (mediumPadding config.state.theme)
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
                        , paddingEach { noPadding | top = mediumPadding config.state.theme }
                        ]
                        (rightArrow config branch2State)
                    , el
                        [ centerX
                        , mediumPadding config.state.theme |> padding
                        ]
                        branch2Label
                    ]
                ]
            , el
                [ paddingEach { noPadding | right = mediumPadding config.state.theme }
                ]
                branch1
            ]
        , el
            [ alignTop
            ]
            branch2
        ]


verticalLayout : Config msg -> Element msg -> Element msg -> Bool -> Element msg -> Element msg -> Bool -> Element msg -> Element msg
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
                    , mediumSpacing config.state.theme |> spacing
                    ]
                    [ el
                        [ paddingEach { noPadding | left = mediumPadding config.state.theme }
                        , height fill
                        ]
                        (downArrow config branch2State)
                    , el
                        [ centerY
                        , paddingXY 0 (mediumPadding config.state.theme)
                        ]
                        branch2Label
                    ]
                ]
            , column [ alignTop ]
                [ el
                    [ width fill
                    , paddingEach { noPadding | top = mediumPadding config.state.theme }
                    ]
                    (rightArrow config branch1State)
                , el [ centerX, paddingXY (mediumPadding config.state.theme) 0 ]
                    branch1Label
                ]
            , el [ alignTop, paddingEach { noPadding | bottom = mediumPadding config.state.theme } ] branch1
            ]
        , branch2
        ]


rightArrow : Config msg -> Bool -> Element msg
rightArrow config highlightState =
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
                        [ Html.Attributes.style "border-bottom" (String.concat [ "solid ", highlightState |> highlightStateToBorderWidth |> String.fromInt, "px ", highlightState |> highlightStateToColor config |> toCssColor ])
                        , Html.Attributes.style "width" "100%"
                        ]
                        []
                    , Html.td
                        [ Html.Attributes.rowspan 2 ]
                        [ element
                            (el
                                [ centerY ]
                                (html (rightArrowHead config highlightState))
                            )
                        ]
                    ]
                , Html.tr []
                    [ Html.td [] []
                    ]
                ]
            )
        )


downArrow : Config msg -> Bool -> Element msg
downArrow config highlightState =
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
                    [ Html.td [ Html.Attributes.style "border-right" (String.concat [ "solid ", highlightState |> highlightStateToBorderWidth |> String.fromInt, "px ", highlightState |> highlightStateToColor config |> toCssColor ]) ] []
                    , Html.td [] []
                    ]
                , Html.tr []
                    [ Html.td
                        [ Html.Attributes.colspan 2 ]
                        [ element
                            (el
                                [ centerX ]
                                (html (downArrowHead config highlightState))
                            )
                        ]
                    ]
                ]
            )
        )


rightArrowHead : Config msg -> Bool -> Html msg
rightArrowHead config highlightState =
    Svg.svg
        [ Svg.Attributes.width
            (String.fromInt (mediumSpacing config.state.theme))
        , Svg.Attributes.height
            (String.fromInt (mediumSpacing config.state.theme))
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 200,100 0,200"
            , Svg.Attributes.style ("fill:" ++ (highlightState |> highlightStateToColor config |> toCssColor))
            ]
            []
        ]


downArrowHead : Config msg -> Bool -> Html msg
downArrowHead config highlightState =
    Svg.svg
        [ Svg.Attributes.width
            (String.fromInt (mediumSpacing config.state.theme))
        , Svg.Attributes.height
            (String.fromInt (mediumSpacing config.state.theme))
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 100,200 200,0"
            , Svg.Attributes.style ("fill:" ++ (highlightState |> highlightStateToColor config |> toCssColor))
            ]
            []
        ]


noPadding : { right : number, left : number, top : number, bottom : number }
noPadding =
    { right = 0
    , left = 0
    , top = 0
    , bottom = 0
    }


branchHighlightToConfigHighLight : Bool -> Morphir.Visual.Config.HighlightState
branchHighlightToConfigHighLight branchHL =
    if branchHL then
        Matched Dict.empty
    else
        Unmatched