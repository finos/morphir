module Morphir.Dependency.DAG.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Dependency.DAG exposing (CycleDetected(..))


encodeCycleDetected : (comparableNode -> Encode.Value) -> CycleDetected comparableNode -> Encode.Value
encodeCycleDetected encodeNode (CycleDetected fromNode toNode) =
    Encode.list identity
        [ Encode.string "CycleDetected"
        , encodeNode fromNode
        , encodeNode toNode
        ]
