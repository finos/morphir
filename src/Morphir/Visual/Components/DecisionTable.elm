module Morphir.Visual.Components.DecisionTable exposing
    ( DecisionTable, Match(..)
    , Rule, TypedPattern, displayTable
    )

{-| This module contains a generic decision table representation that is relatively easy to map to a visualization.

@docs DecisionTable, Match

-}

import Element exposing (Color, Column, Element, el, fill, height, padding, rgb255, row, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.FQName exposing (getLocalName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value, indexedMapValue)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config, HighlightState(..), VisualState)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (mediumPadding)


type alias TypedValue =
    Value () (Type ())


type alias TypedPattern =
    Pattern (Type ())



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
    { decomposeInput : List TypedValue
    , rules : List Rule
    }

{-| Represents a match which is visualized as a cell in the decision table. It could either be a pattern or a guard
which is a function that takes some input and returns a boolean.
-}
type Match
    = Pattern TypedPattern
    | Guard TypedValue


type alias Rule =
    { matches : List Match
    , result : TypedValue
    , highlightStates : List HighlightState
    }


displayTable : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> DecisionTable -> Element msg
displayTable config viewValue table =
    tableHelp config viewValue table.decomposeInput table.rules


tableHelp : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> List TypedValue -> List Rule -> Element msg
tableHelp config viewValue headerFunctions rows =
    table [ Border.solid, Border.width 1 ]
        { data = rows
        , columns =
            List.append (headerFunctions |> getColumnFromHeader config viewValue 0)
                [ Column
                    (el
                        [ Border.widthEach { bottom = 1, top = 0, right = 0, left = 0 }
                        , mediumPadding config.state.theme |> padding
                        , height fill
                        ]
                        (text "Result")
                    )
                    fill
                    (\rules ->
                        el
                            [ Background.color (highlightStateToColor (List.head (List.reverse rules.highlightStates)))
                            , mediumPadding config.state.theme |> padding
                            ]
                            (viewValue (updateConfig config (List.head (List.reverse rules.highlightStates))) (toVisualTypedValue rules.result))
                    )
                ]
        }


getColumnFromHeader : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> Int -> List TypedValue -> List (Column Rule msg)
getColumnFromHeader config viewValue index decomposeInput =
    case decomposeInput of
        inputHead :: [] ->
            columnHelper config viewValue inputHead index

        inputHead :: inputTail ->
            List.concat [ columnHelper config viewValue inputHead index, getColumnFromHeader config viewValue (index + 1) inputTail ]

        _ ->
            []


columnHelper : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> TypedValue -> Int -> List (Column Rule msg)
columnHelper config viewValue header index =
    let
        head : EnrichedValue
        head =
            toVisualTypedValue header
    in
    [ Column
        (el
            [ Border.widthEach { bottom = 1, top = 0, right = 0, left = 0 }
            , mediumPadding config.state.theme |> padding
            , height fill
            ]
            (viewValue config head)
        )
        fill
        (\rules -> getCaseFromIndex config head viewValue (rules.highlightStates |> List.drop index |> List.head) (rules.matches |> List.drop index |> List.head))
    ]


updateConfig : Config msg -> Maybe HighlightState -> Config msg
updateConfig config highlightState =
    let
        tableState : VisualState
        tableState =
            config.state

        updatedTableState : VisualState
        updatedTableState =
            { tableState | highlightState = highlightState }
    in
    { config | state = updatedTableState }


getCaseFromIndex : Config msg -> EnrichedValue -> (Config msg -> EnrichedValue -> Element msg) -> Maybe HighlightState -> Maybe Match -> Element msg
getCaseFromIndex config head viewValue highlightState rule =
    case rule of
        Just match ->
            case match of
                Pattern pattern ->
                    let
                        updatedConfig : Config msg
                        updatedConfig =
                            updateConfig config highlightState

                        result : Color
                        result =
                            highlightStateToColor highlightState
                    in
                    case pattern of
                        Value.WildcardPattern _ ->
                            el [ Background.color result, mediumPadding config.state.theme |> padding ] (text "_")

                        Value.LiteralPattern va literal ->
                            let
                                value : EnrichedValue
                                value =
                                    toVisualTypedValue (Value.Literal va literal)
                            in
                            el [ Background.color result, mediumPadding config.state.theme |> padding ] (viewValue updatedConfig value)

                        Value.ConstructorPattern _ fQName matches ->
                            let
                                parsedMatches : List (Element msg)
                                parsedMatches =
                                    List.map (getCaseFromIndex config head viewValue highlightState << Just << Pattern << toTypedPattern) matches

                                --enclose in parentheses for nested constructors
                            in
                            row [ width fill, Background.color result, mediumPadding config.state.theme |> padding ] (List.concat [ [ text "(", text (nameToText (getLocalName fQName)) ], List.intersperse (text ",") parsedMatches, [ text ")" ] ])

                        Value.AsPattern _ (Value.WildcardPattern _) name ->
                            el [ Background.color result, mediumPadding config.state.theme |> padding ] (text (nameToText name))

                        Value.AsPattern _ asPattern _ ->
                            getCaseFromIndex config head viewValue highlightState (Just (patternToMatch asPattern))

                        _ ->
                            text "pattern type not implemented"

                _ ->
                    text "guard"

        Nothing ->
            text "nothing"


toVisualTypedValue : TypedValue -> EnrichedValue
toVisualTypedValue typedValue =
    typedValue
        |> indexedMapValue Tuple.pair 0
        |> Tuple.first


toTypedPattern : Pattern (Type ()) -> TypedPattern
toTypedPattern match =
    match |> Value.mapPatternAttributes (always (Value.patternAttribute match))


patternToMatch : Pattern (Type ()) -> Match
patternToMatch pattern =
    Pattern (toTypedPattern pattern)


highlightStateToColor : Maybe HighlightState -> Color
highlightStateToColor highlightState =
    case highlightState of
        Just state ->
            case state of
                Matched ->
                    highlightColor.true

                Unmatched ->
                    highlightColor.false

                Default ->
                    highlightColor.default

        Nothing ->
            highlightColor.default


highlightColor : { true : Color, false : Color, default : Color }
highlightColor =
    { true = rgb255 100 180 100
    , false = rgb255 180 100 100
    , default = rgb255 255 255 255
    }
