module Morphir.Visual.ViewPatternMatch exposing (..)

import Dict exposing (Dict)
import Element exposing (Attribute, Column, Element, fill, row, spacing, table, text, width)
import List exposing (concat)
import Morphir.IR.Literal as Value
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, TypedValue, Value)
import Morphir.Value.Interpreter exposing (matchPattern)
import Morphir.Visual.Components.DecisionTable as DecisionTable exposing (DecisionTable, HighlightState(..), Match(..), Rule, TypedPattern)
import Morphir.Visual.Config exposing (Config)
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
            toDecisionTable config typedSubject typedMatches
    in
    DecisionTable.displayTable config viewValue decisionTable


toDecisionTable : Config msg -> TypedValue -> List ( TypedPattern, TypedValue ) -> DecisionTable
toDecisionTable config subject matches =
    let
        decomposedInput : List TypedValue
        decomposedInput =
            decomposeInput subject

        rules : List ( List Match, TypedValue )
        rules =
            getRules decomposedInput matches

        highlights : List (List HighlightState)
        highlights =
            getHighlightStates config decomposedInput rules
    in
    { decomposeInput = decomposedInput
    , rules = List.map2 (\rows highlightStates -> Rule (Tuple.first rows) (Tuple.second rows) highlightStates) rules highlights
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


getHighlightStates : Config msg -> List TypedValue -> List ( List Match, TypedValue ) -> List (List HighlightState)
getHighlightStates config subject matches =
    let
        patterns : List (List Match)
        patterns =
            List.map (\x -> Tuple.first x) matches

        referencedPatterns : List (List ( TypedValue, Match ))
        referencedPatterns =
            List.map (List.map2 Tuple.pair subject) patterns
    in
    List.foldl (comparePreviousHighlightStates config) [] referencedPatterns


comparePreviousHighlightStates : Config msg -> List ( TypedValue, Match ) -> List (List HighlightState) -> List (List HighlightState)
comparePreviousHighlightStates config matches previousStates =
    let
        mostRecentRow : List HighlightState
        mostRecentRow =
            case previousStates of
                x :: _ ->
                    x

                [] ->
                    []

        nextMatches : List HighlightState
        nextMatches =
            --get the highlight state for the result, which is representative of the highlight states for all the variables in the row
            case List.reverse mostRecentRow of
                x :: _ ->
                    case x of
                        --if we haven't matched a result yet, we need to check logic for the next row
                        Default ->
                            let
                                nextStates : List HighlightState
                                nextStates =
                                    List.foldl (getNextHighlightState config) [] matches
                            in
                            if isFullyMatchedRow nextStates then
                                List.append nextStates [ Matched ]

                            else
                                List.append nextStates [ Default ]

                        _ ->
                            List.repeat (List.length matches + 1) Default

                [] ->
                    let
                        nextStates : List HighlightState
                        nextStates =
                            List.foldl (getNextHighlightState config) [] matches
                    in
                    if isFullyMatchedRow nextStates then
                        List.append nextStates [ Matched ]

                    else
                        List.append nextStates [ Default ]
    in
    List.append previousStates [ nextMatches ]


isNotMatchedHighlightState : HighlightState -> Bool
isNotMatchedHighlightState highlightState =
    highlightState /= Matched


isFullyMatchedRow : List HighlightState -> Bool
isFullyMatchedRow highlightStates =
    List.length (List.filter isNotMatchedHighlightState highlightStates) == 0


getNextHighlightState : Config msg -> ( TypedValue, Match ) -> List HighlightState -> List HighlightState
getNextHighlightState config currentMatch previousStates =
    let
        lastState : HighlightState
        lastState =
            case List.reverse previousStates of
                x :: _ ->
                    x

                [] ->
                    Matched

        nextState : HighlightState
        nextState =
            case lastState of
                Matched ->
                    case currentMatch of
                        ( subject, match ) ->
                            case match of
                                Pattern pattern ->
                                    let
                                        rawPattern : Pattern ()
                                        rawPattern =
                                            pattern |> Value.mapPatternAttributes (always ())

                                        variable : Maybe Name
                                        variable =
                                            case subject of
                                                Value.Variable _ name ->
                                                    Just name

                                                _ ->
                                                    Nothing
                                    in
                                    case subject of
                                        Value.Variable _ name ->
                                            case Dict.get name config.state.variables of
                                                Just value ->
                                                    case matchPattern rawPattern value of
                                                        Ok _ ->
                                                            Matched

                                                        Err _ ->
                                                            Unmatched

                                                Nothing ->
                                                    Default

                                        _ ->
                                            Default

                                _ ->
                                    Default

                _ ->
                    Default
    in
    List.append previousStates [ nextState ]


toTypedValue : VisualTypedValue -> TypedValue
toTypedValue visualTypedValue =
    visualTypedValue
        |> Value.mapValueAttributes (always ()) (always Tuple.second (Value.valueAttribute visualTypedValue))


toTypedPattern : Pattern ( Int, Type () ) -> TypedPattern
toTypedPattern match =
    match |> Value.mapPatternAttributes (always Tuple.second (Value.patternAttribute match))
