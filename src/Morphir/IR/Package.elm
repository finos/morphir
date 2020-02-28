module Morphir.IR.Package exposing
    ( Declaration
    , Definition
    )

{-| Tools to work with packages.

@docs Declaration

@docs Definition

-}

import Morphir.IR.Advanced.Package as Advanced


{-| Type that represents a package declaration.
-}
type alias Declaration =
    Advanced.Declaration ()


{-| Type that represents a package definition.
-}
type alias Definition =
    Advanced.Definition ()
