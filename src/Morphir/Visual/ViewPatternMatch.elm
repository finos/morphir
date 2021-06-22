module Morphir.Visual.ViewPatternMatch exposing (..)

import Dict exposing (Dict)
import Element exposing (Attribute, Column, Element, fill, row, spacing, table, text, width)
import List exposing (concat)
import Morphir.IR.Literal as Value
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, TypedValue, Value)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.DecisionTable as DecisionTable exposing (DecisionTable, Match(..), TypedPattern)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)


view : Config msg -> (VisualTypedValue -> Element msg) -> VisualTypedValue -> List ( Pattern ( Int, Type () ), VisualTypedValue ) -> Element msg
view config viewValue subject matches =
    let
        typedSubject : TypedValue
        typedSubject =
            toTypedValue subject

        typedMatches : List ( TypedPattern, TypedValue )
        typedMatches =
            List.map (\( a, b ) -> ( toTypedPattern a, toTypedValue b )) matches

        decisionTable : DecisionTable
        decisionTable =
            toDecisionTable typedSubject typedMatches
    in
    DecisionTable.displayTable viewValue decisionTable


toDecisionTable : TypedValue -> List ( TypedPattern, TypedValue ) -> DecisionTable
toDecisionTable subject matches =
    let
        decomposedInput : List TypedValue
        decomposedInput =
            decomposeInput subject
    in
    { decomposeInput = decomposedInput
    , rules = getRules decomposedInput matches
    }


decomposeInput : TypedValue -> List TypedValue
decomposeInput subject =
    case subject of
        Value.Tuple _ elems ->
            elems |> List.concatMap decomposeInput

        _ ->
            [ subject ]


getRules : List TypedValue -> List ( TypedPattern, TypedValue ) -> List ( List Match, TypedValue )
getRules subject matches =
    matches |> List.concatMap (decomposePattern subject)


decomposePattern : List TypedValue -> ( TypedPattern, TypedValue ) -> List ( List Match, TypedValue )
decomposePattern subject match =
    case match of
        ( Value.WildcardPattern tpe, _ ) ->
            let
                wildcardMatch : Match
                wildcardMatch =
                    DecisionTable.Pattern (Tuple.first match)
            in
            [ ( List.repeat (List.length subject) wildcardMatch, Tuple.second match ) ]

        ( Value.LiteralPattern tpe literal, _ ) ->
            let
                literalMatch : Match
                literalMatch =
                    DecisionTable.Pattern (Tuple.first match)
            in
            [ ( [ literalMatch ], Tuple.second match ) ]

        ( Value.TuplePattern tpe matches, _ ) ->
            let
                tupleMatch : List Match
                tupleMatch =
                    List.map DecisionTable.Pattern matches
            in
            [ ( tupleMatch, Tuple.second match ) ]

        ( Value.ConstructorPattern tpe fQName matches, _ ) ->
            let
                constructorMatch : Match
                constructorMatch =
                    DecisionTable.Pattern (Tuple.first match)
            in
            [ ( [ constructorMatch ], Tuple.second match ) ]

        ( Value.AsPattern tpe pattern name, _ ) ->
            let
                asMatch : Match
                asMatch =
                    DecisionTable.Pattern (Tuple.first match)
            in
            [ ( [ asMatch ], Tuple.second match ) ]

        _ ->
            []


toTypedValue : VisualTypedValue -> TypedValue
toTypedValue visualTypedValue =
    visualTypedValue
        |> Value.mapValueAttributes (always ()) (always Tuple.second (Value.valueAttribute visualTypedValue))


toTypedPattern : Pattern ( Int, Type () ) -> TypedPattern
toTypedPattern match =
    match |> Value.mapPatternAttributes (always Tuple.second (Value.patternAttribute match))
