module Morphir.Visual.ViewIfThenElse exposing (view)

import Dict exposing (Dict)
import Element exposing (Element)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue, Value)
import Morphir.Visual.Components.DecisionTree as DecisionTree exposing (LeftOrRight(..))
import Morphir.Visual.Context as Context exposing (Context)


view : Context -> (TypedValue -> Element msg) -> Value () (Type ()) -> Dict Name (Value () ()) -> Element msg
view ctx viewValue value variables =
    DecisionTree.layout viewValue (valueToTree ctx True value)


valueToTree : Context -> Bool -> TypedValue -> DecisionTree.Node
valueToTree ctx doEval value =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                result =
                    if doEval then
                        case ctx |> Context.evaluate (Value.toRawValue condition) of
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
                , thenBranch = valueToTree ctx (result == Just True) thenBranch
                , elseBranch = valueToTree ctx (result == Just False) elseBranch
                }

        Value.LetDefinition _ defName defValue inValue ->
            valueToTree
                { ctx
                    | variables =
                        ctx
                            |> Context.evaluate
                                (defValue
                                    |> Value.mapDefinitionAttributes identity (always ())
                                    |> Value.definitionToValue
                                )
                            |> Result.map
                                (\evaluatedDefValue ->
                                    ctx.variables
                                        |> Dict.insert defName evaluatedDefValue
                                )
                            |> Result.withDefault ctx.variables
                }
                doEval
                inValue

        _ ->
            DecisionTree.Leaf value
