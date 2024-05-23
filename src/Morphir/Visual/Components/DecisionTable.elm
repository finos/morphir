module Morphir.Visual.Components.DecisionTable exposing
    ( DecisionTable
    , Rule, TypedPattern, displayTable
    )

{-| This module contains a generic decision table representation that is relatively easy to map to a visualization.

@docs DecisionTable, Match

-}

import Dict
import Element exposing (Color, Column, Element, el, fill, height, padding, rgb255, row, shrink, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.FQName exposing (getLocalName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value, indexedMapValue)
import Morphir.Value.Interpreter exposing (Variables)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config, HighlightState(..), VisualState)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (mediumPadding)
import Morphir.IR.Name exposing (toHumanWordsTitle)



--


{-| Represents a decision table. It has two fields:

  - `decomposeInput`
      - contains a list of functions that can be used to decomposed a single input value to a list of values
      - each function takes the input value as the input and return some other value (typically extracts a field of a record value)
      - each function corresponds to an input column in the decision table
  - `rules`
      - contains a list of rules specified as a pair of matches and an output value
      - each rule corresponds to a row in the decision table
      - the number of matches in each rule should be the same as the number of functions defined in `decomposeInput`

-}
type alias DecisionTable =
    { decomposeInput : List EnrichedValue
    , rules : List Rule
    }


type alias TypedPattern =
    Pattern (Type ())


type alias Rule =
    { matches : List TypedPattern
    , result : EnrichedValue
    , highlightStates : List HighlightState
    }


displayTable : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> DecisionTable -> Element msg
displayTable config viewValue table =
    tableHelp config viewValue table.decomposeInput table.rules


tableHelp : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> List EnrichedValue -> List Rule -> Element msg
tableHelp config viewValue headerFunctions rows =
    let
        whiteBg =
            Background.color <| rgb255 255 255 255
    in
    table [ Border.solid, Border.width 1, whiteBg ]
        { data = rows
        , columns =
            List.append (headerFunctions |> getColumnFromHeader config viewValue 0)
                [ Column
                    (el
                        [ Border.widthEach { bottom = 1, top = 0, right = 0, left = 0 }
                        , mediumPadding config.state.theme |> padding
                        , height fill
                        , whiteBg
                        ]
                        (text "Result")
                    )
                    shrink
                    (\rules ->
                        el
                            [ Border.color (highlightStateToColor config (List.head (List.reverse rules.highlightStates)))
                            , Border.width 5
                            , mediumPadding config.state.theme |> padding
                            ]
                            (viewValue (updateConfig config (List.head (List.reverse rules.highlightStates))) rules.result)
                    )
                ]
        }


getColumnFromHeader : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> Int -> List EnrichedValue -> List (Column Rule msg)
getColumnFromHeader config viewValue index decomposeInput =
    case decomposeInput of
        inputHead :: [] ->
            columnHelper config viewValue inputHead index

        inputHead :: inputTail ->
            List.concat [ columnHelper config viewValue inputHead index, getColumnFromHeader config viewValue (index + 1) inputTail ]

        _ ->
            []


columnHelper : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> EnrichedValue -> Int -> List (Column Rule msg)
columnHelper config viewValue header index =
    [ Column
        (el
            [ Border.widthEach { bottom = 1, top = 0, right = 0, left = 0 }
            , mediumPadding config.state.theme |> padding
            , height fill
            ]
            (viewValue config header)
        )
        fill
        (\rules -> getCaseFromIndex config header viewValue (rules.highlightStates |> List.drop index |> List.head) (rules.matches |> List.drop index |> List.head))
    ]


updateConfig : Config msg -> Maybe HighlightState -> Config msg
updateConfig config highlightState =
    let
        tableState : VisualState
        tableState =
            config.state

        updateVariables : Variables
        updateVariables =
            case highlightState of
                Just hls ->
                    case hls of
                        Matched vars ->
                            vars

                        _ ->
                            Dict.empty

                _ ->
                    Dict.empty

        updatedTableState : VisualState
        updatedTableState =
            { tableState | highlightState = highlightState, variables = Dict.union updateVariables config.state.variables }
    in
    { config | state = updatedTableState }


getCaseFromIndex : Config msg -> EnrichedValue -> (Config msg -> EnrichedValue -> Element msg) -> Maybe HighlightState -> Maybe (Pattern (Type ())) -> Element msg
getCaseFromIndex config head viewValue highlightState rule =
    case rule of
        Just match ->
            let
                updatedConfig : Config msg
                updatedConfig =
                    updateConfig config highlightState

                result : Color
                result =
                    highlightStateToColor config highlightState 
            in
            case match of
                Value.WildcardPattern _ ->
                    el [ Background.color result, mediumPadding config.state.theme |> padding, Font.italic ] (text "anything else")

                Value.LiteralPattern va literal ->
                    let
                        value : EnrichedValue
                        value =
                            Value.Literal va literal |> indexedMapValue Tuple.pair 0 |> Tuple.first
                    in
                    el [ Background.color result, mediumPadding config.state.theme |> padding ] (viewValue updatedConfig value)

                Value.ConstructorPattern _ fQName matches ->
                    let
                        parsedMatches : List (Element msg)
                        parsedMatches =
                            List.map (getCaseFromIndex config head viewValue highlightState << Just << toTypedPattern) matches

                        --enclose in parentheses for nested constructors
                    in
                    row [ width fill, Background.color result, mediumPadding config.state.theme |> padding ] (List.concat [ [ text "(", text ((toHumanWordsTitle >> String.join " ") (getLocalName fQName)) ], List.intersperse (text ",") parsedMatches, [ text ")" ] ])

                Value.AsPattern _ (Value.WildcardPattern _) name ->
                    el [ Background.color result, mediumPadding config.state.theme |> padding ] (text (nameToText name))

                Value.AsPattern _ asPattern _ ->
                    getCaseFromIndex config head viewValue highlightState (Just (toTypedPattern asPattern))

                _ ->
                    text "pattern type not implemented"

        Nothing ->
            text "nothing"


toTypedPattern : Pattern (Type ()) -> Pattern (Type ())
toTypedPattern match =
    match |> Value.mapPatternAttributes (always (Value.patternAttribute match))


highlightStateToColor : Config msg -> Maybe HighlightState -> Color
highlightStateToColor config highlightState =
    case highlightState of
        Just state ->
            case state of
                Matched _ ->
                    config.state.theme.colors.highlighted

                Unmatched ->
                    config.state.theme.colors.lightest

                Default ->
                    config.state.theme.colors.lightest

        Nothing ->
            config.state.theme.colors.lightest



