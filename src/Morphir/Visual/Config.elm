module Morphir.Visual.Config exposing (..)

import Dict exposing (Dict)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK as SDK
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Value.Error as Error exposing (Error(..))
import Morphir.Value.Interpreter as Interpreter
import Morphir.Value.Native as Native
import Morphir.Visual.Theme exposing (Theme)


type alias Config msg =
    { ir : Distribution
    , nativeFunctions : Dict FQName Native.Function
    , state : VisualState
    , handlers : EventHandlers msg
    , nodePath : List Int
    }


type alias VisualState =
    { drillDownFunctions : DrillDownFunctions
    , variables : Dict Name RawValue
    , nonEvaluatedVariables : Dict Name RawValue
    , popupVariables : PopupScreenRecord
    , theme : Theme
    , highlightState : Maybe HighlightState
    , zIndex : Int
    }


type DrillDownFunctions
    = DrillDownFunctions (Dict Int DrillDownFunctions)



-- used to identify where in the expression tree visualisation an msg is coming from


type alias ExpressionTreePath =
    List Int


type alias EventHandlers msg =
    { onReferenceClicked : FQName -> Int -> ExpressionTreePath -> msg
    , onReferenceClose : FQName -> Int -> ExpressionTreePath -> msg
    , onHoverOver : Int -> List Int -> Maybe RawValue -> msg
    , onHoverLeave : Int -> List Int -> msg
    }


type alias PopupScreenRecord =
    { variableIndex : Int
    , variableValue : Maybe RawValue
    , nodePath : List Int
    }


type HighlightState
    = Matched Interpreter.Variables
    | Unmatched
    | Default


fromIR : Distribution -> VisualState -> EventHandlers msg -> Config msg
fromIR ir visualState eventHandlers =
    { ir = ir
    , nativeFunctions = SDK.nativeFunctions
    , state = visualState
    , handlers = eventHandlers
    , nodePath = []
    }


evaluate : RawValue -> Config msg -> Result String RawValue
evaluate value config =
    Interpreter.evaluateValue config.nativeFunctions config.ir config.state.variables [] value
        |> Result.mapError
            (\error ->
                error
                    |> Debug.log (Error.toString error)
                    |> Error.toString
            )


pathTaken : Config msg -> Bool
pathTaken config =
    not (config.state.highlightState == Just Unmatched || config.state.highlightState == Just Default)


evalIfPathTaken : Config msg -> Value ta va -> Maybe RawValue
evalIfPathTaken config expr =
    if pathTaken config then
        case config |> evaluate (Value.toRawValue expr) of
            Ok v ->
                Just v

            _ ->
                Nothing

    else
        Nothing


addToDrillDown : DrillDownFunctions -> Int -> ExpressionTreePath -> Dict Int DrillDownFunctions
addToDrillDown (DrillDownFunctions dict) nodeID nodePath =
    case nodePath of
        [] ->
            Dict.insert nodeID (DrillDownFunctions Dict.empty) dict

        [ p ] ->
            case Dict.get p dict of
                Just (DrillDownFunctions currentp) ->
                    Dict.insert p (DrillDownFunctions <| Dict.insert nodeID (DrillDownFunctions Dict.empty) currentp) dict

                Nothing ->
                    dict

        head :: rest ->
            case Dict.get head dict of
                Just d ->
                    Dict.insert head (DrillDownFunctions <| addToDrillDown d nodeID rest) dict

                Nothing ->
                    dict


removeFromDrillDown : DrillDownFunctions -> Int -> ExpressionTreePath -> Dict Int DrillDownFunctions
removeFromDrillDown (DrillDownFunctions dict) nodeID nodePath =
    case nodePath of
        [] ->
            Dict.remove nodeID dict

        [ p ] ->
            case Dict.get p dict of
                Just (DrillDownFunctions currentp) ->
                    Dict.insert p (DrillDownFunctions (Dict.remove nodeID currentp)) dict

                Nothing ->
                    dict

        head :: rest ->
            case Dict.get head dict of
                Just d ->
                    Dict.insert head (DrillDownFunctions <| removeFromDrillDown d nodeID rest) dict

                Nothing ->
                    dict


drillDownContains : DrillDownFunctions -> Int -> ExpressionTreePath -> Bool
drillDownContains (DrillDownFunctions dict) nodeID nodePath =
    case nodePath of
        [] ->
            Dict.member nodeID dict

        x :: xs ->
            case Dict.get x dict of
                Just d ->
                    drillDownContains d nodeID xs

                Nothing ->
                    False
