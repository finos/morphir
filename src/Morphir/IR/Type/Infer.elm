module Morphir.IR.Type.Infer exposing (..)

import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)


type Info
    = Index Int
    | Exact (Type ())


type Error
    = Error


type alias Inferred =
    Result Error Info


applyRules : Value Inferred -> Value Inferred
applyRules value =
    value
