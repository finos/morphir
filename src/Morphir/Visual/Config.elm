module Morphir.Visual.Config exposing (..)

import Dict exposing (Dict)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Value.Interpreter as Interpreter


type alias Config msg =
    { irContext : IRContext
    , state : VisualState
    , handlers : EventHandlers msg
    }


type alias IRContext =
    { distribution : Distribution
    , references : Dict FQName Interpreter.Reference
    }


type alias VisualState =
    { expandedFunctions : Dict FQName (Value.Definition () (Type ()))
    , variables : Dict Name RawValue
    }


type alias EventHandlers msg =
    { onReferenceClicked : FQName -> Bool -> msg
    }


evaluate : RawValue -> Config msg -> Result String RawValue
evaluate value config =
    Interpreter.evaluateValue config.irContext.references config.state.variables [] value
        |> Result.mapError
            (\error ->
                error
                    |> Debug.log (String.concat [ "Error while evaluating '", Debug.toString value, "'" ])
                    |> Debug.toString
            )
