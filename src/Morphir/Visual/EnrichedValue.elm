module Morphir.Visual.EnrichedValue exposing (EnrichedValue, fromRawValue, fromTypedValue, getId)

{-| This module contains utilities to work with values that are enriched with attributes that make visualization tasks
easier.

@docs EnrichedValue, fromRawValue, fromTypedValue, getId

-}

import Morphir.IR exposing (IR)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value, indexedMapValue)
import Morphir.Type.Infer as Infer exposing (TypeError)


{-| Values that is enriched with attributes that make visualization tasks easier. The attributes are:

  - a unique `Int` ID for each value
  - the inferred type of the value

-}
type alias EnrichedValue =
    Value () ( Int, Type () )


{-| Enrich a raw value. It requires access to the whole IR for type inference.
-}
fromRawValue : IR -> RawValue -> Result TypeError EnrichedValue
fromRawValue ir rawValue =
    Infer.inferValue ir rawValue
        |> Result.andThen
            (\typedValue ->
                typedValue
                    |> Value.mapValueAttributes identity (\( _, tpe ) -> tpe)
                    |> fromTypedValue
                    |> Ok
            )


{-| Enrich a value that has type information with a unique ID.
-}
fromTypedValue : TypedValue -> EnrichedValue
fromTypedValue typedValue =
    typedValue
        |> indexedMapValue Tuple.pair 0
        |> Tuple.first


getId : EnrichedValue -> Int
getId enrichedValue =
    let
        ( id, _ ) =
            Value.valueAttribute enrichedValue
    in
    id
