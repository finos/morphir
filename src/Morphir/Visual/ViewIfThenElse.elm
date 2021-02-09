module Morphir.Visual.ViewIfThenElse exposing (view)

import Dict exposing (Dict)
import Element exposing (Element)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue, Value)
import Morphir.Visual.Components.DecisionTree as DecisionTree exposing (LeftOrRight(..))
import Morphir.Visual.Config as Config exposing (Config)


view : Config msg -> (TypedValue -> Element msg) -> Value () (Type ()) -> Element msg
view config viewValue value =
    DecisionTree.layout viewValue (valueToTree config True value)


valueToTree : Config msg -> Bool -> TypedValue -> DecisionTree.Node
valueToTree config doEval value =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                result =
                    if doEval then
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
                , conditionValue = result
                , thenBranch = valueToTree config (result == Just True) thenBranch
                , elseBranch = valueToTree config (result == Just False) elseBranch
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
            DecisionTree.Leaf value
