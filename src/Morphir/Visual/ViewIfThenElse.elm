module Morphir.Visual.ViewIfThenElse exposing (view)

import Dict exposing (Dict)
import Element exposing (Element)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue, Value)
import Morphir.Visual.Components.DecisionTree as DecisionTree exposing (LeftOrRight(..))
import Morphir.Visual.Context exposing (Context)


view : Context -> (TypedValue -> Element msg) -> Value () (Type ()) -> Dict Name (Value () ()) -> Element msg
view ctx viewValue value variables =
    DecisionTree.layout False viewValue (valueToTree value)


valueToTree : Value () (Type ()) -> DecisionTree.Node (Value () (Type ()))
valueToTree value =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                withCondition : Value () (Type ()) -> Value () (Type ()) -> Value () (Type ()) -> DecisionTree.Node (Value () (Type ()))
                withCondition cond left right =
                    case cond of
                        --Value.Apply _ (Value.Apply _ (Value.Reference _ (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "basics" ] ] [ "or" ])) arg1) arg2 ->
                        --    DecisionTree.Branch
                        --        { nodeLabel = arg1
                        --        , leftBranchLabel = Value.Literal (Basics.boolType ()) (BoolLiteral True)
                        --        , leftBranch = valueToTree left
                        --        , rightBranchLabel = Value.Literal (Basics.boolType ()) (BoolLiteral False)
                        --        , rightBranch =
                        --            withCondition arg2 left right
                        --        , executionPath = Just Left
                        --        }
                        --
                        _ ->
                            DecisionTree.Branch
                                { nodeLabel = cond
                                , leftBranchLabel = Value.Literal (Basics.boolType ()) (BoolLiteral True)
                                , leftBranch = valueToTree left
                                , rightBranchLabel = Value.Literal (Basics.boolType ()) (BoolLiteral False)
                                , rightBranch = valueToTree right
                                , executionPath = Just Right
                                }
            in
            withCondition condition thenBranch elseBranch

        Value.LetDefinition _ _ _ inValue ->
            valueToTree inValue

        _ ->
            DecisionTree.Leaf value
