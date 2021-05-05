module Morphir.Visual.DecisionTable exposing
    ( DecisionTable, Match(..)
    , TypedPattern, displayTable
    )

{-| This module contains a generic decision table representation that is relatively easy to map to a visualization.

@docs DecisionTable, Match

-}

import Element exposing (Column, Element, fill, spacing, table, text)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, Value, indexedMapValue)
import Morphir.Visual.Common exposing (VisualTypedValue, nameToText)


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
    table [ spacing 10 ]
        { data = Debug.log "hi" rows
        , columns = List.append (headerFunctions |> getColumnFromHeader viewValue 0) [ Column (text "Result") fill (\rules -> viewValue (toVisualTypedValue (Tuple.second rules))) ]
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
    case header of
        Value.Variable _ name ->
            [ Column (text (nameToText name)) fill (\rules -> getCaseFromIndex viewValue (Tuple.first rules |> List.drop index |> List.head)) ]

        _ ->
            []


getCaseFromIndex : (VisualTypedValue -> Element msg) -> Maybe Match -> Element msg
getCaseFromIndex viewValue rules =
    case rules of
        Just match ->
            case match of
                Pattern pattern ->
                    case pattern of
                        Value.WildcardPattern _ ->
                            text "*"

                        Value.LiteralPattern va literal ->
                            let
                                value : VisualTypedValue
                                value =
                                    toVisualTypedValue (Value.Literal va literal)
                            in
                            viewValue value

                        _ ->
                            text "other pattern"

                _ ->
                    text "guard"

        Nothing ->
            text "nothing"


toVisualTypedValue : TypedValue -> VisualTypedValue
toVisualTypedValue typedValue =
    typedValue
        |> indexedMapValue Tuple.pair 0
        |> Tuple.first
