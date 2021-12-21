module Morphir.Visual.Config exposing (..)

import Dict exposing (Dict)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK as SDK
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue)
import Morphir.Value.Interpreter as Interpreter
import Morphir.Value.Native as Native
import Morphir.Visual.Theme as Theme exposing (Theme)


type alias Config msg =
    { ir : IR
    , nativeFunctions : Dict FQName Native.Function
    , state : VisualState
    , handlers : EventHandlers msg
    }


type alias VisualState =
    { expandedFunctions : Dict FQName (Value.Definition () (Type ()))
    , variables : Dict Name RawValue
    , popupVariables : PopupScreenRecord
    , theme : Theme
    , highlightState : Maybe HighlightState
    }


type alias EventHandlers msg =
    { onReferenceClicked : FQName -> Bool -> msg
    , onHoverOver : Int -> Maybe RawValue -> msg
    , onHoverLeave : Int -> msg
    }


type alias PopupScreenRecord =
    { variableIndex : Int
    , variableValue : Maybe RawValue
    }


type HighlightState
    = Matched
    | Unmatched
    | Default


fromIR : IR -> VisualState -> EventHandlers msg -> Config msg
fromIR ir visualState eventHandlers =
    { ir = ir
    , nativeFunctions = SDK.nativeFunctions
    , state = visualState
    , handlers = eventHandlers
    }


evaluate : RawValue -> Config msg -> Result String RawValue
evaluate value config =
    Interpreter.evaluateValue config.nativeFunctions config.ir config.state.variables [] value
        |> Result.mapError
            (\error ->
                error
                    |> Debug.log (String.concat [ "Error while evaluating '", Debug.toString value, "'" ])
                    |> Debug.toString
            )
