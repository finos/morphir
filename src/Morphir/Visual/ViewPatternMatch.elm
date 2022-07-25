module Morphir.Visual.ViewPatternMatch exposing (..)

import Element exposing (Element)
import List
import Morphir.IR.Literal as Value
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, TypedValue)
import Morphir.Value.Interpreter exposing (matchPattern)
import Morphir.Visual.Components.DecisionTable as DecisionTable exposing (DecisionTable, Match(..), Rule, TypedPattern)
import Morphir.Visual.Config as Config exposing (Config, HighlightState(..))
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)


view : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> EnrichedValue -> List ( Pattern ( Int, Type () ), EnrichedValue ) -> Element msg
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
        ( Value.WildcardPattern _, _ ) ->
            let
                wildcardMatch : Match
                wildcardMatch =
                    DecisionTable.Pattern (Tuple.first match)
            in
            [ ( List.repeat (List.length subject) wildcardMatch, Tuple.second match ) ]

        ( Value.LiteralPattern _ _, _ ) ->
            let
                literalMatch : Match
                literalMatch =
                    DecisionTable.Pattern (Tuple.first match)
            in
            [ ( [ literalMatch ], Tuple.second match ) ]

        ( Value.TuplePattern _ matches, _ ) ->
            let
                tupleMatch : List Match
                tupleMatch =
                    List.map DecisionTable.Pattern matches
            in
            [ ( tupleMatch, Tuple.second match ) ]

        ( Value.ConstructorPattern _ _ _, _ ) ->
            let
                constructorMatch : Match
                constructorMatch =
                    DecisionTable.Pattern (Tuple.first match)
            in
            [ ( [ constructorMatch ], Tuple.second match ) ]

        ( Value.AsPattern _ _ _, _ ) ->
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
    case config.state.highlightState of
        Nothing ->
            List.foldl (comparePreviousHighlightStates config) [] referencedPatterns

        Just highlightState ->
            case highlightState of
                Matched ->
                    List.foldl (comparePreviousHighlightStates config) [] referencedPatterns

                _ ->
                    List.map (\x -> List.repeat (List.length x) Default) patterns


comparePreviousHighlightStates : Config msg -> List ( TypedValue, Match ) -> List (List HighlightState) -> List (List HighlightState)
comparePreviousHighlightStates config matches previousStates =
    let
        mostRecentRow : List HighlightState
        mostRecentRow =
            case List.reverse previousStates of
                x :: _ ->
                    x

                [] ->
                    []

        nextMatches : List HighlightState
        nextMatches =
            --check whether the previous row is either untouched or fully matched, meaning we should stop checking highlight logic.
            case mostRecentRow of
                _ :: _ ->
                    if isFullyMatchedRow mostRecentRow || isFullyDefaultRow mostRecentRow then
                        List.repeat (List.length matches + 1) Default

                    else
                        --if we haven't matched a result yet, we need to check logic for the next row
                        let
                            nextStates : List HighlightState
                            nextStates =
                                List.foldl (getNextHighlightState config) [] matches
                        in
                        if isFullyMatchedRow nextStates then
                            List.append nextStates [ Matched ]

                        else
                            List.append nextStates [ Default ]

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


isNotDefaultHighlightState : HighlightState -> Bool
isNotDefaultHighlightState highlightState =
    highlightState /= Default


isFullyMatchedRow : List HighlightState -> Bool
isFullyMatchedRow highlightStates =
    List.length (List.filter isNotMatchedHighlightState highlightStates) == 0


isFullyDefaultRow : List HighlightState -> Bool
isFullyDefaultRow highlightStates =
    List.length (List.filter isNotDefaultHighlightState highlightStates) == 0


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
                                    in
                                    case Config.evaluate (Value.toRawValue subject) config of
                                        Ok value ->
                                            case matchPattern rawPattern value of
                                                Ok _ ->
                                                    Matched

                                                Err _ ->
                                                    Unmatched

                                        _ ->
                                            Default

                                _ ->
                                    Default

                _ ->
                    Default
    in
    List.append previousStates [ nextState ]


toTypedValue : EnrichedValue -> TypedValue
toTypedValue visualTypedValue =
    visualTypedValue
        |> Value.mapValueAttributes (always ()) (always Tuple.second (Value.valueAttribute visualTypedValue))


toTypedPattern : Pattern ( Int, Type () ) -> TypedPattern
toTypedPattern match =
    match |> Value.mapPatternAttributes (always Tuple.second (Value.patternAttribute match))
