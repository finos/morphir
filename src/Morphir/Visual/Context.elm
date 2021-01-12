module Morphir.Visual.Context exposing (..)

import Dict exposing (Dict)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (RawValue)
import Morphir.Value.Interpreter as Interpreter


type alias Context =
    { distribution : Distribution
    , references : Dict Interpreter.FQN Interpreter.Reference
    , variables : Dict Name RawValue
    }


fromDistributionAndVariables : Distribution -> Dict Name RawValue -> Context
fromDistributionAndVariables distribution variables =
    let
        references =
            Interpreter.referencesForDistribution distribution
    in
    Context distribution references variables


evaluate : RawValue -> Context -> Result String RawValue
evaluate value ctx =
    Interpreter.evaluateValue ctx.references ctx.variables [] value
        |> Result.mapError Debug.toString
