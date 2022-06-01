module Morphir.IR.Attribute exposing (..)

import Morphir.IR.NodePath exposing (NodePath)


{-| Compact representation of a set of optional attributes on some nodes of an expression tree.
-}
type AttributeTree a
    = AttributeTree a (List ( NodePath, AttributeTree a ))
