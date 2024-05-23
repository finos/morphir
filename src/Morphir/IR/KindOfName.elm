module Morphir.IR.KindOfName exposing (KindOfName(..))

{-| A name can refer to various different kinds of things in Morphir: types, values or constructors. This module
contains utilities to be able to differentiate between them.

@docs KindOfName

-}


{-| Type that represents what kind of thing a local name refers to. Is it a type, constructor or value?
-}
type KindOfName
    = Type
    | Constructor
    | Value
