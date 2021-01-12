module Morphir.Visual.ViewIfThenElse exposing (view)

import Dict exposing (Dict)
import Element exposing (Element)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue, Value)
import Morphir.Visual.Components.DecisionTree as DecisionTree exposing (LeftOrRight(..))
import Morphir.Visual.Context as Context exposing (Context)


view : Context -> (TypedValue -> Element msg) -> Value () (Type ()) -> Dict Name (Value () ()) -> Element msg
view ctx viewValue value variables =
    DecisionTree.layout viewValue (valueToTree ctx value)


valueToTree : Context -> TypedValue -> DecisionTree.Node
valueToTree ctx value =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            DecisionTree.Branch
                { condition = condition
                , conditionValue =
                    ctx
                        |> Context.evaluate (Value.toRawValue condition)
                        |> Result.toMaybe
                , thenBranch = valueToTree ctx thenBranch
                , elseBranch = valueToTree ctx elseBranch
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
                inValue

        _ ->
            DecisionTree.Leaf value
