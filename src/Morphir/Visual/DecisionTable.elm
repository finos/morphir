module Morphir.Visual.DecisionTable exposing (DecisionTable, Match)

{-| This module contains a generic decision table representation that is relatively easy to map to a visualization.

@docs DecisionTable, Match

-}

import Element exposing (Element)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


type alias TypedValue =
    Value () (Type ())


type alias TypedPattern =
    Value.Pattern (Type ())



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


displayTable : DecisionTable -> Element msg
displayTable table =
    tableHelp table.decomposeInput table.rules


tableHelp : List TypedValue -> List ( List Match, TypedValue ) -> Element msg
tableHelp headerFunctions rows =
    Element.none



{- getDecomposedValues : List TypedValue -> List TypedValue -> List TypedValue
   getDecomposedValues input decomposeFunction =
       case input of
           [] ->
               []
           head :: tail ->
               case decomposeFunction of
                   decompHead :: decompTail ->

-}
