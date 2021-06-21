module Morphir.Visual.DecisionTable exposing
    ( DecisionTable, Match(..)
    , TypedPattern, displayTable
    )

{-| This module contains a generic decision table representation that is relatively easy to map to a visualization.

@docs DecisionTable, Match

-}

import Element exposing (Column, Element, el, fill, padding, rgb255, row, spacing, table, text)
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.FQName exposing (getLocalName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue, typedToVisualTypedValue)


type alias TypedValue =
    Value () (Type ())


type alias TypedPattern =
    Pattern (Type ())


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
    , rules : List ( List Match, TypedValue )
    }


{-| Represents a match which is visualized as a cell in the decision table. It could either be a pattern or a guard
which is a function that takes some input and returns a boolean.
-}
type Match
    = Pattern TypedPattern
    | Guard TypedValue


displayTable : (VisualTypedValue -> Element msg) -> DecisionTable -> Element msg
displayTable viewValue table =
    tableHelp viewValue table.decomposeInput table.rules


tableHelp : (VisualTypedValue -> Element msg) -> List TypedValue -> List ( List Match, TypedValue ) -> Element msg
tableHelp viewValue headerFunctions rows =
    table [ spacing 10, padding 10, Border.solid, Border.width 1 ]
        { data = rows
        , columns =
            List.append (headerFunctions |> getColumnFromHeader viewValue 0)
                [ Column
                    (el
                        [ Border.widthEach { bottom = 1, top = 0, right = 0, left = 0 }
                        ]
                        (text "Result")
                    )
                    fill
                    (\rules -> viewValue (typedToVisualTypedValue (Tuple.second rules)))
                ]
        }


getColumnFromHeader : (VisualTypedValue -> Element msg) -> Int -> List TypedValue -> List (Column ( List Match, TypedValue ) msg)
getColumnFromHeader viewValue index decomposeInput =
    case decomposeInput of
        inputHead :: [] ->
            columnHelper viewValue inputHead index

        inputHead :: inputTail ->
            List.concat [ columnHelper viewValue inputHead index, getColumnFromHeader viewValue (index + 1) inputTail ]

        _ ->
            []


columnHelper : (VisualTypedValue -> Element msg) -> TypedValue -> Int -> List (Column ( List Match, TypedValue ) msg)
columnHelper viewValue header index =
    let
        head : VisualTypedValue
        head =
            typedToVisualTypedValue header
    in
    [ Column
        (el
            [ Border.widthEach { bottom = 1, top = 0, right = 0, left = 0 }
            ]
            (viewValue head)
        )
        fill
        (\rules -> getCaseFromIndex viewValue (Tuple.first rules |> List.drop index |> List.head))
    ]


getCaseFromIndex : (VisualTypedValue -> Element msg) -> Maybe Match -> Element msg
getCaseFromIndex viewValue rules =
    case rules of
        Just match ->
            case match of
                Pattern pattern ->
                    case pattern of
                        Value.WildcardPattern _ ->
                            el [ Background.color (rgb255 200 200 200) ] (text " ")

                        Value.LiteralPattern va literal ->
                            let
                                value : VisualTypedValue
                                value =
                                    typedToVisualTypedValue (Value.Literal va literal)
                            in
                            viewValue value

                        Value.ConstructorPattern tpe fQName matches ->
                            let
                                patternToMaybeMatch : Pattern (Type ()) -> Maybe Match
                                patternToMaybeMatch input =
                                    Just (patternToMatch input)

                                maybeMatches : List (Maybe Match)
                                maybeMatches =
                                    List.map patternToMaybeMatch matches

                                parsedMatches : List (Element msg)
                                parsedMatches =
                                    List.map (getCaseFromIndex viewValue) maybeMatches
                            in
                            row [ spacing 5, Border.widthEach { bottom = 0, top = 0, right = 0, left = 2 } ] (List.concat [ [ text (nameToText (getLocalName fQName)) ], parsedMatches ])

                        Value.AsPattern tpe asPattern name ->
                            getCaseFromIndex viewValue (Just (patternToMatch asPattern))

                        _ ->
                            text "pattern type not implemented"

                _ ->
                    text "guard"

        Nothing ->
            text "nothing"


toTypedPattern : Pattern (Type ()) -> TypedPattern
toTypedPattern match =
    match |> Value.mapPatternAttributes (always (Value.patternAttribute match))


patternToMatch : Pattern (Type ()) -> Match
patternToMatch pattern =
    Pattern (toTypedPattern pattern)
