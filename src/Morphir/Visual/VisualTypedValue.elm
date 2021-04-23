module Morphir.Visual.VisualTypedValue exposing (VisualTypedValue, rawToVisualTypedValue, typedToVisualTypedValue)

import Morphir.IR exposing (IR)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value, indexedMapValue)
import Morphir.Type.Infer as Infer exposing (TypeError)


type alias VisualTypedValue =
    Value () ( Int, Type () )


rawToVisualTypedValue : IR -> RawValue -> Result TypeError VisualTypedValue
rawToVisualTypedValue references rawValue =
    Infer.inferValue references rawValue
        |> Result.andThen
            (\typedValue ->
                typedValue
                    |> Value.mapValueAttributes identity (\( _, tpe ) -> tpe)
                    |> typedToVisualTypedValue
                    |> Ok
            )


typedToVisualTypedValue : TypedValue -> VisualTypedValue
typedToVisualTypedValue typedValue =
    typedValue
        |> indexedMapValue Tuple.pair 0
        |> Tuple.first
