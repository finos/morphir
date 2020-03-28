module Morphir.IR.Package exposing
    ( Specification
    , Definition
    )

{-| Tools to work with packages.

@docs Specification

@docs Definition

-}

import Morphir.IR.Advanced.Package as Advanced


{-| Type that represents a package specification.
-}
type alias Specification =
    Advanced.Specification ()


{-| Type that represents a package definition.
-}
type alias Definition =
    Advanced.Definition ()
