module Morphir.Value.Native.Eq exposing (equal, notEqual)

{-| This is a module that implements equality checks directly on the Morphir IR. As most functional languages Morphir
also uses structural equality. This means that all types of values can be checked for equality except functions. For
tuples, lists and records equality is defined by comparing elements, items and fields.

@docs equal, notEqual

-}

import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Value.Error exposing (Error(..))


{-| Checks if two values are equal.
-}
equal : RawValue -> RawValue -> Result Error Bool
equal a b =
    if Value.isData a && Value.isData b then
        Ok (a == b)

    else
        Err (UnexpectedArguments [ a, b ])


{-| Checks if two values are not equal.
-}
notEqual : RawValue -> RawValue -> Result Error Bool
notEqual a b =
    Result.map not (equal a b)
