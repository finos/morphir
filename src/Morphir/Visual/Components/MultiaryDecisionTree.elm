module Morphir.Visual.Components.MultiaryDecisionTree exposing (..)

import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
import Dict
import Element exposing (Color, Column, Element, el, fill, height, padding, rgb255, row, spacing, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.FQName exposing (getLocalName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value, indexedMapValue)
import Morphir.Value.Interpreter exposing (matchPattern)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config as Config exposing (Config, HighlightState(..), VisualState)
import Morphir.Visual.Theme exposing (mediumPadding)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)


import Element exposing (Attribute, Color, Element, alignLeft, alignTop, centerX, centerY, column, el, fill, height, html, padding, paddingEach, paddingXY, rgb255, row, shrink, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Html exposing (Html)
import Html.Attributes
import Morphir.Visual.Common exposing (element)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme exposing (mediumPadding, mediumSpacing, smallSpacing)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
import Svg
import Svg.Attributes


type Node
    = Branch BranchNode
    | Leaf VisualTypedValue


type alias BranchNode =
    { subject : VisualTypedValue
    , subjectEvaluationResult : Maybe RawValue
    , branches : List ( Node )
    }


type Color
    = Color Int Int Int

toElementColor : Color -> Element.Color
toElementColor (Color r g b) =
    rgb255 r g b


toCssColor : Color -> String
toCssColor (Color r g b) =
    String.concat [ "rgb(", String.fromInt r, ",", String.fromInt g, ",", String.fromInt b, ")" ]

{-| Sample data structure. Should be moved into a test module.
-}
--exampleTree : Node
--exampleTree =
--    Branch
--        { subject = Value.Variable ( 0, Type.Unit () ) [ "foo" ]
--        , subjectEvaluationResult = Nothing
--        , branches =
--            [ ( Value.ConstructorPattern () ( [], [], [ "yes" ] ) [], Leaf (Value.Variable ( 0, Type.Unit () ) [ "foo" ]) )
--            , ( Value.WildcardPattern (), Leaf (Value.Variable ( 0, Type.Unit () ) [ "foo" ]) )
--            , ( Value.WildcardPattern (), Leaf (Value.Variable ( 0, Type.Unit () ) [ "foo" ]) )
--            ]
--        }

layout : Config msg -> (VisualTypedValue -> Element msg) -> Node -> Element msg
layout config viewValue rootNode =
    layoutHelp config viewValue rootNode


layoutHelp : Config msg -> (VisualTypedValue -> Element msg) -> Node -> Element msg
layoutHelp config viewValue rootNode =
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
            --let
            --
            --
            --in
            verticalLayout
            config
                (el
                    [ Border.width 10
                    , Border.rounded 6
                    , Border.color (Color 100 100 100 |> toElementColor)
                    , mediumPadding config.state.theme |> padding
                    ]
                    (viewValue branch.subject)
                )
                (el
                    [ Font.color (Color 100 100 100 |> toElementColor)
                    ]
                    (text "Yes")
                )
                ( List.map (\x -> layoutHelp config viewValue x) branch.branches )
                (el
                    [ Font.color (Color 200 200 200 |> toElementColor)
                    ]
                    (text "No")
                )
                (layoutHelp config viewValue branch.elseBranch)
------

verticalLayout : Config msg -> Element msg -> Element msg -> Element msg -> Element msg -> Element msg -> Element msg
verticalLayout config condition branch1Label branch1 branch2Label branch2 =
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
                        (downArrow config )
                    , el
                        [ centerY
                        , paddingXY 0 (mediumPadding config.state.theme)
                        ]
                        branch1Label
                    ]
                ]
            , column [ alignTop ]
                [ el
                    [ width fill
                    , paddingEach { noPadding | top = mediumPadding config.state.theme }
                    ]
                    (rightArrow config )
                , el [ centerX, paddingXY (mediumPadding config.state.theme) 0 ]
                    branch2Label
                ]
            , el [ alignTop, paddingEach { noPadding | bottom = mediumPadding config.state.theme } ] branch2
            ]
        , branch1
        ]


rightArrow : Config msg ->  Element msg
rightArrow config  =
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
                        [ Html.Attributes.style "border-bottom" (String.concat [ "solid ", 100 |> String.fromInt, "px ", Color 20 20 20 |> toCssColor ])
                        , Html.Attributes.style "width" "100%"
                        ]
                        []
                    , Html.td
                        [ Html.Attributes.rowspan 2 ]
                        [ element
                            (el
                                [ centerY ]
                                (html (rightArrowHead config ))
                            )
                        ]
                    ]
                , Html.tr []
                    [ Html.td [] []
                    ]
                ]
            )
        )


downArrow : Config msg -> Element msg
downArrow config  =
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
                    [ Html.td [ Html.Attributes.style "border-right" (String.concat [ "solid ", 20 |> String.fromInt, "px ", Color 300 333 333 |> toCssColor ]) ] []
                    , Html.td [] []
                    ]
                , Html.tr []
                    [ Html.td
                        [ Html.Attributes.colspan 2 ]
                        [ element
                            (el
                                [ centerX ]
                                (html (downArrowHead config ))
                            )
                        ]
                    ]
                ]
            )
        )


rightArrowHead : Config msg -> Html msg
rightArrowHead config  =
    Svg.svg
        [ Svg.Attributes.width
            ( String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.height
            (
                String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 200,100 0,200"]
            []
        ]


downArrowHead : Config msg -> Html msg
downArrowHead config =
    Svg.svg
        [ Svg.Attributes.width
            (String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.height
            ( String.fromInt (mediumSpacing config.state.theme)
            )
        , Svg.Attributes.viewBox "0 0 200 200"
        ]
        [ Svg.polygon
            [ Svg.Attributes.points "0,0 100,200 200,0"]
            []
        ]


noPadding =
    { right = 0
    , left = 0
    , top = 0
    , bottom = 0
    }


