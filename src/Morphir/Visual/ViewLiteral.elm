module Morphir.Visual.ViewLiteral exposing (..)

import Html exposing (Html)
import Html.Attributes exposing (class)
import Morphir.IR.Literal exposing (Literal(..))


view : Literal -> Html msg
view literal =
    case literal of
        BoolLiteral bool ->
            let
                text : String
                text =
                    case bool of
                        True ->
                            "True"

                        False ->
                            "False"
            in
            Html.span [ class "bool-literal" ] [ Html.text text ]

        CharLiteral char ->
            let
                text : String
                text =
                    String.concat [ "'", String.fromChar char, "'" ]
            in
            Html.span [ class "char-literal" ] [ Html.text text ]

        StringLiteral string ->
            let
                text : String
                text =
                    String.concat [ "\"", string, "\"" ]
            in
            Html.span [ class "string-literal" ] [ Html.text text ]

        IntLiteral int ->
            let
                text : String
                text =
                    String.fromInt int
            in
            Html.span [ class "int-literal" ] [ Html.text text ]

        FloatLiteral float ->
            let
                text : String
                text =
                    String.fromFloat float
            in
            Html.span [ class "float-literal" ] [ Html.text text ]
