module Morphir.Visual.ViewIfThenElse exposing (view)

import Dict
import Element exposing (Element)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Type exposing (Type(..))
import Morphir.IR.Value as Value exposing (RawValue, Value(..))
import Morphir.Value.Interpreter exposing (matchPattern)
import Morphir.Visual.Components.DecisionTree as DecisionTree
import Morphir.Visual.Config as Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)


view : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> EnrichedValue -> Element msg
view config viewValue value =
    DecisionTree.layout config viewValue (valueToTree config True value)


valueToTree : Config msg -> Bool -> EnrichedValue -> DecisionTree.Node
valueToTree config doEval value =
    let
        maybeToDecisionTree : EnrichedValue -> ( Value.Pattern ( Int, Type () ), EnrichedValue ) -> ( Value.Pattern ( Int, Type () ), EnrichedValue ) -> DecisionTree.Node
        maybeToDecisionTree caseOf ( justPattern, justBody ) ( nothingPattern, nothingBody ) =
            let
                maybeCaseOfValue : Maybe RawValue
                maybeCaseOfValue =
                    if doEval then
                        Config.evalIfPathTaken config caseOf

                    else
                        Nothing

                isSet : Bool
                isSet =
                    not <| (maybeCaseOfValue == Just (Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] )))

                justBranchConfig : Config msg
                justBranchConfig =
                    if isSet then
                        case maybeCaseOfValue of
                            Just caseOfValue ->
                                case matchPattern (Value.mapPatternAttributes (always ()) justPattern) caseOfValue of
                                    Ok patternVariables ->
                                        let
                                            configState =
                                                config.state
                                        in
                                        { config | state = { configState | variables = Dict.union configState.variables patternVariables } }

                                    _ ->
                                        config

                            Nothing ->
                                config

                    else
                        config

                isThenBranchSelected =
                    case maybeCaseOfValue of
                        Just _ ->
                            Just isSet

                        _ ->
                            Nothing
            in
            DecisionTree.Branch
                { condition = caseOf
                , isThenBranchSelected = isThenBranchSelected
                , thenBranch = valueToTree justBranchConfig isSet justBody
                , elseBranch = valueToTree config (not isSet) nothingBody
                , thenLabel = "set"
                , elseLabel = "not set"
                }
    in
    case value of
        Value.PatternMatch _ caseOf [ ( Value.ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) [ _ ], _ ) as case1, ( Value.ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) [], _ ) as case2 ] ->
            maybeToDecisionTree caseOf case1 case2

        Value.PatternMatch _ caseOf [ ( Value.ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) [], _ ) as case1, ( Value.ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) [ _ ], _ ) as case2 ] ->
            maybeToDecisionTree caseOf case2 case1

        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                pathTaken : Bool
                pathTaken =
                    not (config.state.highlightState == Just Config.Unmatched || config.state.highlightState == Just Config.Default)

                result =
                    if doEval && pathTaken then
                        case config |> Config.evaluate (Value.toRawValue condition) of
                            Ok (Value.Literal _ (BoolLiteral v)) ->
                                Just v

                            _ ->
                                Nothing

                    else
                        Nothing
            in
            DecisionTree.Branch
                { condition = condition
                , isThenBranchSelected = result
                , thenBranch = valueToTree config (result == Just True) thenBranch
                , elseBranch = valueToTree config (result == Just False) elseBranch
                , thenLabel = "Yes"
                , elseLabel = "No"
                }

        Value.LetDefinition _ defName defValue inValue ->
            let
                currentState =
                    config.state

                newState =
                    { currentState
                        | variables =
                            config
                                |> Config.evaluate
                                    (defValue
                                        |> Value.mapDefinitionAttributes identity (always ())
                                        |> Value.definitionToValue
                                    )
                                |> Result.map
                                    (\evaluatedDefValue ->
                                        currentState.variables
                                            |> Dict.insert defName evaluatedDefValue
                                    )
                                |> Result.withDefault currentState.variables
                    }
            in
            valueToTree
                { config
                    | state = newState
                }
                doEval
                inValue

        _ ->
            DecisionTree.Leaf config.state.variables value
