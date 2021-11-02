module Morphir.Visual.ViewIfThenElseNEW exposing (view)

import Dict exposing (Dict)
import Element exposing (Element)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value, toRawValue)
import Morphir.Visual.Components.MultiaryDecisionTree as MultiaryDecisionTree exposing (Node)

import Morphir.Visual.Config as Config exposing (Config)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)


view : Config msg -> (VisualTypedValue -> Element msg) -> VisualTypedValue -> Element msg
view config viewValue value =
     MultiaryDecisionTree.layout config viewValue (valueToTree config True value)


valueToTree : Config msg -> Bool -> VisualTypedValue -> MultiaryDecisionTree.Node
valueToTree config doEval value =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                result =
                    if doEval then
                        case config |> Config.evaluate (Value.toRawValue condition) of
                            Ok (Value.Literal _ (BoolLiteral v)) ->
                                Value.toRawValue v

                            _ ->
                                Nothing

                    else
                        Nothing
                --mybranches : List (Node)
                --mybranches =
                --   [ valueToTree config (result == Just True) thenBranch ]
                --thenBranch = valueToTree config (result == Just True) thenBranch
                --elseBranch = valueToTree config (result == Just False) elseBranch
                --
            in
            MultiaryDecisionTree.Branch
                { subject = condition
                , subjectEvaluationResult = result
                , branches = valueToTree config (result == Just True) thenBranch
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
            MultiaryDecisionTree.Leaf value
