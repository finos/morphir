module Morphir.Visual.ViewLiteral exposing (..)

import Element exposing (Element, el, paragraph, text)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.Visual.Common as Common


view : Literal -> Element msg
view literal =
    case literal of
        BoolLiteral bool ->
            viewLiteralText "bool-literal"
                (case bool of
                    True ->
                        "True"

                    False ->
                        "False"
                )

        CharLiteral char ->
            viewLiteralText "char-literal"
                (String.concat [ "'", String.fromChar char, "'" ])

        StringLiteral string ->
            viewLiteralText "string-literal"
                (String.concat [ "\"", string, "\"" ])

        IntLiteral int ->
            viewLiteralText "int-literal"
                (String.fromInt int)

        FloatLiteral float ->
            viewLiteralText "float-literal"
                (String.fromFloat float)


viewLiteralText : String -> String -> Element msg
viewLiteralText className literalText =
    el []
        (paragraph
            [ Common.cssClass className ]
            [ text literalText ]
        )
