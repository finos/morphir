module Morphir.Visual.ViewPattern exposing (..)

import Decimal
import Element exposing (Element, text)
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Value exposing (Pattern(..))


patternAsText : Pattern va -> String
patternAsText pattern =
    case pattern of
        WildcardPattern _ ->
            "_"

        AsPattern _ (WildcardPattern _) name ->
            Name.toCamelCase name

        AsPattern _ subject name ->
            patternAsText subject ++ " as " ++ Name.toCamelCase name

        TuplePattern _ elems ->
            "( "
                ++ String.join ", "
                    (elems |> List.map patternAsText)
                ++ " )"

        ConstructorPattern _ (( _, _, localName ) as fQName) args ->
            case fQName of
                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) ->
                    String.join " " (args |> List.map patternAsText)

                _ ->
                    String.join " "
                        (List.concat
                            [ [ Name.toTitleCase localName ]
                            , args |> List.map patternAsText
                            ]
                        )

        EmptyListPattern _ ->
            "[]"

        HeadTailPattern _ head tail ->
            patternAsText head ++ " :: " ++ patternAsText tail

        LiteralPattern _ literal ->
            case literal of
                BoolLiteral bool ->
                    if bool then
                        "Yes"

                    else
                        "No"

                CharLiteral char ->
                    String.fromChar char

                StringLiteral string ->
                    string

                WholeNumberLiteral int ->
                    String.fromInt int

                FloatLiteral float ->
                    String.fromFloat float

                DecimalLiteral decimal ->
                    Decimal.toString decimal

        UnitPattern _ ->
            "()"
