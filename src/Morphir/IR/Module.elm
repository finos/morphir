module Morphir.IR.Module exposing (Definition)

{-| Modules are groups of types and values that belong together.

@docs Definition

-}

import Morphir.IR.Advanced.Module as Advanced


{-| Type that represents a module defintion. It includes types and values.
-}
type alias Definition =
    Advanced.Definition ()
