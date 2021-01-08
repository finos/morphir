module Morphir.Visual.Edit exposing (..)

import Html exposing (Html)
import Html.Attributes
import Html.Events
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


editValue : Type () -> (Value () () -> msg) -> (String -> msg) -> Html msg
editValue valueType valueUpdated invalidValue =
    if valueType == Basics.intType () then
        editInt valueUpdated invalidValue

    else if valueType == Basics.floatType () then
        editFloat valueUpdated invalidValue

    else
        Html.text "Unknown value type"


editInt : (Value () () -> msg) -> (String -> msg) -> Html msg
editInt valueUpdated invalidValue =
    Html.input
        [ Html.Attributes.placeholder "Start typing an integer value ..."
        , Html.Events.onInput
            (\updatedText ->
                String.toInt updatedText
                    |> Maybe.map (\int -> valueUpdated (Value.Literal () (IntLiteral int)))
                    |> Maybe.withDefault (invalidValue "needs to be an integer value")
            )
        ]
        []


editFloat : (Value () () -> msg) -> (String -> msg) -> Html msg
editFloat valueUpdated invalidValue =
    Html.input
        [ Html.Attributes.placeholder "Start typing a floating-point value ..."
        , Html.Events.onInput
            (\updatedText ->
                String.toFloat updatedText
                    |> Maybe.map (\float -> valueUpdated (Value.Literal () (FloatLiteral float)))
                    |> Maybe.withDefault (invalidValue "needs to be a a floating-point value")
            )
        ]
        []
