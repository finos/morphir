module Morphir.IR.NodeId exposing (..)

import Morphir.IR.FQName exposing (FQName)

type NodeID 
    = TypeID FQName 
    | ValueID FQName