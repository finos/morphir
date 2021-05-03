module Morphir.Visual.ViewLiteral exposing (..)

import Element exposing (Element, el, row, text)
import FormatNumber exposing (format)
import FormatNumber.Locales exposing (Decimals(..), usLocale)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.Visual.Common as Common
import Morphir.Visual.Config exposing (Config)


view : Config msg -> Literal -> Element msg
view config literal =
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
                (format { usLocale | decimals = Exact 0, negativePrefix = "- ( ", negativeSuffix = " )" }
                    (toFloat int)
                )

        FloatLiteral float ->
            viewLiteralText "float-literal"
                (format
                    { usLocale | decimals = Exact config.state.theme.decimalDigit, negativePrefix = "- ( ", negativeSuffix = " )" }
                    float
                )


viewLiteralText : String -> String -> Element msg
viewLiteralText className literalText =
    el []
        (row
            [ Common.cssClass className ]
            [ text literalText ]
        )
