module Morphir.Visual.ViewMultiaryDecisionTree exposing (..)

import Dict exposing (Dict)
import Element exposing (Attribute, Column, Element, fill, row, spacing, table, text, width)
import List exposing (concat)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, RawValue, TypedValue, Value)
import Morphir.Visual.Config as Config exposing (Config, HighlightState(..))
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
import Morphir.Value.Interpreter exposing (matchPattern)

import Morphir.Visual.Components.DecisionTree as DecisionTree exposing (LeftOrRight(..))
import Morphir.Visual.Components.MultiaryDecisionTree as MultiaryDecisionTree exposing (..)

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
                            Ok(Value.Literal _ (BoolLiteral v)) ->
                                Just v
                            _ -> Nothing
                    else
                        Nothing
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
        _ ->  MultiaryDecisionTree.Leaf value
