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
equal arg1 arg2 =
    if Value.isData arg1 && Value.isData arg2 then
        Ok (arg1 == arg2)

    else
        Err (UnexpectedArguments [ arg1, arg2 ])


{-| Checks if two values are not equal.
-}
notEqual : RawValue -> RawValue -> Result Error Bool
notEqual arg1 arg2 =
    Result.map not (equal arg1 arg2)
