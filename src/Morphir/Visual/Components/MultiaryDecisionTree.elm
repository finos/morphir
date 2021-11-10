module Morphir.Visual.Components.MultiaryDecisionTree exposing (..)

import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)


type Node
    = Branch BranchNode
    | Leaf VisualTypedValue


type alias BranchNode =
    { subject : VisualTypedValue
    , subjectEvaluationResult : Maybe RawValue
    , branches : List ( Pattern (), Node )
    }


{-| Sample data structure. Should be moved into a test module.
-}
exampleTree : Node
exampleTree =
    Branch
        { subject = Value.Variable ( 0, Type.Unit () ) [ "foo" ]
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.ConstructorPattern () ( [], [], [ "yes" ] ) [], Leaf (Value.Variable ( 0, Type.Unit () ) [ "foo" ]) )
            , ( Value.WildcardPattern (), Leaf (Value.Variable ( 0, Type.Unit () ) [ "foo" ]) )
            , ( Value.WildcardPattern (), Leaf (Value.Variable ( 0, Type.Unit () ) [ "foo" ]) )
            ]
        }
