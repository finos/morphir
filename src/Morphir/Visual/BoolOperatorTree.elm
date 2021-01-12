module Morphir.Visual.BoolOperatorTree exposing (..)

import Morphir.IR.Value exposing (TypedValue)


type BoolOperatorTree
    = BoolOperatorBranch BoolOperator (List BoolOperatorTree)
    | BoolValueLeaf TypedValue


type BoolOperator
    = And
    | Or


fromTypedValue : TypedValue -> BoolOperatorTree
fromTypedValue typedValue =
    -- TODO: implement the transformation by matching on AND and OR operators recursively
    BoolValueLeaf typedValue
