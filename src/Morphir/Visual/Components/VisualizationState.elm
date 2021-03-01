module Morphir.Visual.Components.VisualizationState exposing (VisualizationState)

import Dict exposing (Dict)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.QName exposing (QName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Visual.Config exposing (PopupScreenRecord)


type alias VisualizationState =
    { distribution : Distribution
    , selectedFunction : QName
    , functionDefinition : Value.Definition () (Type ())
    , functionArguments : List (Value () ())
    , expandedFunctions : Dict FQName (Value.Definition () (Type ()))
    , popupVariables : PopupScreenRecord
    }
