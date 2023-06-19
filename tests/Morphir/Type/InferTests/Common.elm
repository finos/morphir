module Morphir.Type.InferTests.Common exposing (..)

import Expect exposing (Expectation)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Type.Infer as Infer


{-| Utility function that takes a value with types on each node, erases the type information, calls the type inference
to infer the types again and compares the result with the original. This makes it very easy to check if the inferred
types align with the expectations even on complex expressions.
-}
checkValueTypes : Distribution -> Value () (Type ()) -> Expectation
checkValueTypes ir typedValue =
    let
        untypedValue : Value () ()
        untypedValue =
            typedValue
                |> Value.mapValueAttributes identity (always ())
    in
    Infer.inferValue ir untypedValue
        |> Result.map (Value.mapValueAttributes identity Tuple.second)
        |> Expect.equal (Ok typedValue)


{-| Utility function that takes a value with types on each node, erases the type information, calls the type inference
to infer the types again and compares the result with the original. This makes it very easy to check if the inferred
types align with the expectations even on complex expressions.
-}
checkValueDefinitionTypes : Distribution -> Value.Definition () (Type ()) -> Expectation
checkValueDefinitionTypes ir typedValueDef =
    let
        untypedValueDef : Value.Definition () ()
        untypedValueDef =
            typedValueDef
                |> Value.mapDefinitionAttributes identity (always ())
    in
    Infer.inferValueDefinition ir untypedValueDef
        |> Result.map (Value.mapDefinitionAttributes identity Tuple.second)
        |> Expect.equal (Ok typedValueDef)
