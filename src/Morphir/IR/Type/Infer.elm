module Morphir.IR.Type.Infer exposing (..)

import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)


type alias UntypedValue =
    Value () ()


type alias TypedValue =
    Value () (Type ())


inferValueTypes : UntypedValue -> TypedValue
inferValueTypes untypedValue =
    Debug.todo "implement"
