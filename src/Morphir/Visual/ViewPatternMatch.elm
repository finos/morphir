module Morphir.Visual.ViewPatternMatch exposing (..)

import Dict
import Element exposing (Element)
import List
import Morphir.IR.Literal as Value
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, TypedValue)
import Morphir.Value.Interpreter exposing (Variables, matchPattern)
import Morphir.Visual.Components.DecisionTable as DecisionTable exposing (DecisionTable, Rule, TypedPattern)
import Morphir.Visual.Config as Config exposing (Config, HighlightState(..))
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)


view : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> EnrichedValue -> List ( Pattern ( Int, Type () ), EnrichedValue ) -> Element msg
view config viewValue subject matches =
    let
        typedMatches : List ( TypedPattern, EnrichedValue )
        typedMatches =
            List.map (\( a, b ) -> ( toTypedPattern a, b )) matches

        decisionTable : DecisionTable
        decisionTable =
            toDecisionTable config subject typedMatches
    in
    DecisionTable.displayTable config viewValue decisionTable


toDecisionTable : Config msg -> EnrichedValue -> List ( TypedPattern, EnrichedValue ) -> DecisionTable
toDecisionTable config subject matches =
    let
        decomposedInput : List EnrichedValue
        decomposedInput =
            decomposeInput subject

        rules : List ( List TypedPattern, EnrichedValue )
        rules =
            getRules decomposedInput matches

        highlights : List (List HighlightState)
        highlights =
            getHighlightStates config decomposedInput rules
    in
    { decomposeInput = decomposedInput
    , rules = List.map2 (\rows highlightStates -> Rule (Tuple.first rows) (Tuple.second rows) highlightStates) rules highlights
    }


decomposeInput : EnrichedValue -> List EnrichedValue
decomposeInput subject =
    case subject of
        Value.Tuple _ elems ->
            elems |> List.concatMap decomposeInput

        _ ->
            [ subject ]


getRules : List EnrichedValue -> List ( TypedPattern, EnrichedValue ) -> List ( List TypedPattern, EnrichedValue )
getRules subject matches =
    matches |> List.concatMap (decomposePattern subject)


decomposePattern : List EnrichedValue -> ( TypedPattern, EnrichedValue ) -> List ( List TypedPattern, EnrichedValue )
decomposePattern subject match =
    case match of
        ( Value.WildcardPattern _, _ ) ->
            let
                wildcardMatch : TypedPattern
                wildcardMatch =
                    Tuple.first match
            in
            [ ( List.repeat (List.length subject) wildcardMatch, Tuple.second match ) ]

        ( Value.LiteralPattern _ _, _ ) ->
            let
                literalMatch : TypedPattern
                literalMatch =
                    Tuple.first match
            in
            [ ( [ literalMatch ], Tuple.second match ) ]

        ( Value.TuplePattern _ matches, _ ) ->
            let
                tupleMatch : List TypedPattern
                tupleMatch =
                    matches
            in
            [ ( tupleMatch, Tuple.second match ) ]

        ( Value.ConstructorPattern _ _ _, _ ) ->
            let
                constructorMatch : TypedPattern
                constructorMatch =
                    Tuple.first match
            in
            [ ( [ constructorMatch ], Tuple.second match ) ]

        ( Value.AsPattern _ _ _, _ ) ->
            let
                asMatch : TypedPattern
                asMatch =
                    Tuple.first match
            in
            [ ( [ asMatch ], Tuple.second match ) ]

        _ ->
            []


getHighlightStates : Config msg -> List EnrichedValue -> List ( List TypedPattern, EnrichedValue ) -> List (List HighlightState)
getHighlightStates config subject matches =
    let
        patterns : List (List TypedPattern)
        patterns =
            List.map (\x -> Tuple.first x) matches

        referencedPatterns : List (List ( EnrichedValue, TypedPattern ))
        referencedPatterns =
            List.map (List.map2 Tuple.pair subject) patterns
    in
    case config.state.highlightState of
        Nothing ->
            List.foldl (comparePreviousHighlightStates config) [] referencedPatterns

        Just highlightState ->
            case highlightState of
                Matched v ->
                    List.foldl (comparePreviousHighlightStates config) [] referencedPatterns

                _ ->
                    List.map (\x -> List.repeat (List.length x) Default) patterns


comparePreviousHighlightStates : Config msg -> List ( EnrichedValue, TypedPattern ) -> List (List HighlightState) -> List (List HighlightState)
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
            let
                nextRow =
                    let
                        nextStates : List HighlightState
                        nextStates =
                            List.foldl (getNextHighlightState config) [] matches

                        variablesSoFar : Variables
                        variablesSoFar =
                            let
                                getVars state =
                                    case state of
                                        Matched v ->
                                            v

                                        _ ->
                                            Dict.empty
                            in
                            nextStates |> List.map getVars |> List.foldl Dict.union Dict.empty
                    in
                    if isFullyMatchedRow nextStates then
                        List.append nextStates [ Matched variablesSoFar ]

                    else
                        List.append nextStates [ Default ]
            in
            --check whether the previous row is either untouched or fully matched, meaning we should stop checking highlight logic.
            case mostRecentRow of
                _ :: _ ->
                    if isFullyMatchedRow mostRecentRow || isFullyDefaultRow mostRecentRow then
                        List.repeat (List.length matches + 1) Default

                    else
                        --if we haven't matched a result yet, we need to check logic for the next row
                        nextRow

                [] ->
                    nextRow
    in
    List.append previousStates [ nextMatches ]


isNotMatchedHighlightState : HighlightState -> Bool
isNotMatchedHighlightState highlightState =
    case highlightState of
        Matched _ ->
            False

        _ ->
            True


isNotDefaultHighlightState : HighlightState -> Bool
isNotDefaultHighlightState highlightState =
    highlightState /= Default


isFullyMatchedRow : List HighlightState -> Bool
isFullyMatchedRow highlightStates =
    List.length (List.filter isNotMatchedHighlightState highlightStates) == 0


isFullyDefaultRow : List HighlightState -> Bool
isFullyDefaultRow highlightStates =
    List.length (List.filter isNotDefaultHighlightState highlightStates) == 0


getNextHighlightState : Config msg -> ( EnrichedValue, TypedPattern ) -> List HighlightState -> List HighlightState
getNextHighlightState config currentMatch previousStates =
    let
        lastState : HighlightState
        lastState =
            case List.reverse previousStates of
                x :: _ ->
                    x

                [] ->
                    Matched Dict.empty

        nextState : HighlightState
        nextState =
            case lastState of
                Matched variables ->
                    case currentMatch of
                        ( subject, match ) ->
                            let
                                rawPattern : Pattern ()
                                rawPattern =
                                    match |> Value.mapPatternAttributes (always ())

                                isDefaultValue : Value.Value ta () -> Bool
                                isDefaultValue v =
                                    -- A Unit value indicates that the user has not provided an input yet.
                                    -- In this case, instead of indicating that Unit does not match the given pattern, we don't highlight anything
                                    v == Value.Unit ()
                            in
                            case Config.evaluate (Value.toRawValue subject) config of
                                Ok value ->
                                    if isDefaultValue value then
                                        Default

                                    else
                                        case matchPattern rawPattern value of
                                            Ok newVariables ->
                                                Matched (Dict.union variables newVariables)

                                            Err _ ->
                                                Unmatched

                                _ ->
                                    Default

                _ ->
                    Default
    in
    List.append previousStates [ nextState ]


toTypedPattern : Pattern ( Int, Type () ) -> TypedPattern
toTypedPattern match =
    match |> Value.mapPatternAttributes (always Tuple.second (Value.patternAttribute match))
