module Morphir.Visual.Components.VisualizationState exposing (VisualizationState)

import Dict exposing (Dict)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.QName exposing (QName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Interpreter exposing (FQN)


type alias VisualizationState =
    { distribution : Distribution
    , selectedFunction : QName
    , functionDefinition : Value.Definition () (Type ())
    , functionArguments : List (Value () ())
    , expandedFunctions : Dict FQN (Value.Definition () (Type ()))
    }
