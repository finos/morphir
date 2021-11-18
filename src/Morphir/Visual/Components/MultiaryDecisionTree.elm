module Morphir.Visual.Components.MultiaryDecisionTree exposing (..)

import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)


type Node
    = Branch BranchNode
    | Leaf EnrichedValue


type alias BranchNode =
    { subject : EnrichedValue
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
