module Morphir.Visual.Edit exposing (editFloat, editInt, editValue)

import Element exposing (Element, height, paddingXY, px, shrink, text, width)
import Element.Input as Input
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)


editValue : Type () -> Maybe RawValue -> (Value () () -> msg) -> (String -> msg) -> Element msg
editValue valueType currentValue valueUpdated invalidValue =
    if valueType == Basics.intType () then
        editInt currentValue valueUpdated invalidValue

    else if valueType == Basics.floatType () then
        editFloat (currentValue |> Debug.log "current vaalue") valueUpdated invalidValue

    else
        textBox
            { onChange =
                \updatedText ->
                    invalidValue "unknown value type"
            , text = ""
            }


editInt : Maybe RawValue -> (Value () () -> msg) -> (String -> msg) -> Element msg
editInt currentValue valueUpdated invalidValue =
    textBox
        { onChange =
            \updatedText ->
                String.toInt updatedText
                    |> Maybe.map (\int -> valueUpdated (Value.Literal () (IntLiteral int)))
                    |> Maybe.withDefault (invalidValue "needs to be an integer value")
        , text =
            case currentValue of
                Just (Value.Literal _ (IntLiteral v)) ->
                    String.fromInt v

                _ ->
                    ""
        }


editFloat : Maybe RawValue -> (Value () () -> msg) -> (String -> msg) -> Element msg
editFloat currentValue valueUpdated invalidValue =
    textBox
        { onChange =
            \updatedText ->
                String.toFloat updatedText
                    |> Maybe.map (\float -> valueUpdated (Value.Literal () (FloatLiteral float)))
                    |> Maybe.withDefault (invalidValue "needs to be a a floating-point value")
        , text =
            case currentValue of
                Just (Value.Literal _ (FloatLiteral v)) ->
                    String.fromFloat v

                _ ->
                    ""
        }


textBox config =
    Input.text
        [ width (px 70)
        , height shrink
        , paddingXY 10 3
        ]
        { onChange =
            config.onChange
        , text =
            config.text
        , placeholder = Nothing
        , label = Input.labelHidden ""
        }
