module Morphir.Visual.Context exposing (Context, evaluate, fromDistributionAndVariables)

import Dict exposing (Dict)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (RawValue)
import Morphir.Value.Interpreter as Interpreter exposing (FQN)


type alias Context msg =
    { distribution : Distribution
    , references : Dict Interpreter.FQN Interpreter.Reference
    , variables : Dict Name RawValue
    , onReferenceClicked : FQN -> Bool -> msg
    }


fromDistributionAndVariables : Distribution -> Dict Name RawValue -> (FQN -> Bool -> msg) -> Context msg
fromDistributionAndVariables distribution variables onReferenceClick =
    let
        references =
            Interpreter.referencesForDistribution distribution
    in
    Context distribution references variables onReferenceClick


evaluate : RawValue -> Context msg -> Result String RawValue
evaluate value ctx =
    Interpreter.evaluateValue ctx.references ctx.variables [] value
        |> Result.mapError
            (\error ->
                error
                    |> Debug.log (String.concat [ "Error while evaluating '", Debug.toString value, "'" ])
                    |> Debug.toString
            )
