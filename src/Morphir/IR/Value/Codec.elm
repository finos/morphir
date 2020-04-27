module Morphir.IR.Value.Codec exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.FQName.Codec exposing (decodeFQName, encodeFQName)
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Type.Codec exposing (decodeType, encodeType)
import Morphir.IR.Value exposing (Definition, Literal(..), Pattern(..), Specification, Value(..))


encodeValue : (a -> Encode.Value) -> Value a -> Encode.Value
encodeValue encodeAttributes v =
    case v of
        Literal a value ->
            Encode.list identity
                [ Encode.string "Literal"
                , encodeAttributes a
                , encodeLiteral value
                ]

        Constructor a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "Constructor"
                , encodeAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Tuple a elements ->
            Encode.list identity
                [ Encode.string "Tuple"
                , encodeAttributes a
                , elements |> Encode.list (encodeValue encodeAttributes)
                ]

        List a items ->
            Encode.list identity
                [ Encode.string "List"
                , encodeAttributes a
                , items |> Encode.list (encodeValue encodeAttributes)
                ]

        Record a fields ->
            Encode.list identity
                [ Encode.string "Record"
                , encodeAttributes a
                , fields
                    |> Encode.list
                        (\( fieldName, fieldValue ) ->
                            Encode.list identity
                                [ encodeName fieldName
                                , encodeValue encodeAttributes fieldValue
                                ]
                        )
                ]

        Variable a name ->
            Encode.list identity
                [ Encode.string "Variable"
                , encodeAttributes a
                , encodeName name
                ]

        Reference a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "Reference"
                , encodeAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Field a subjectValue fieldName ->
            Encode.list identity
                [ Encode.string "Field"
                , encodeAttributes a
                , encodeValue encodeAttributes subjectValue
                , encodeName fieldName
                ]

        FieldFunction a fieldName ->
            Encode.list identity
                [ Encode.string "FieldFunction"
                , encodeAttributes a
                , encodeName fieldName
                ]

        Apply a function argument ->
            Encode.list identity
                [ Encode.string "Apply"
                , encodeAttributes a
                , encodeValue encodeAttributes function
                , encodeValue encodeAttributes argument
                ]

        Lambda a argumentPattern body ->
            Encode.list identity
                [ Encode.string "Lambda"
                , encodeAttributes a
                , encodePattern encodeAttributes argumentPattern
                , encodeValue encodeAttributes body
                ]

        LetDefinition a valueName valueDefinition inValue ->
            Encode.list identity
                [ Encode.string "LetDefinition"
                , encodeAttributes a
                , encodeName valueName
                , encodeDefinition encodeAttributes valueDefinition
                , encodeValue encodeAttributes inValue
                ]

        LetRecursion a valueDefinitions inValue ->
            Encode.list identity
                [ Encode.string "LetRecursion"
                , encodeAttributes a
                , valueDefinitions
                    |> Dict.toList
                    |> Encode.list
                        (\( name, def ) ->
                            Encode.list identity
                                [ encodeName name
                                , encodeDefinition encodeAttributes def
                                ]
                        )
                , encodeValue encodeAttributes inValue
                ]

        Destructure a pattern valueToDestruct inValue ->
            Encode.list identity
                [ Encode.string "Destructure"
                , encodeAttributes a
                , encodePattern encodeAttributes pattern
                , encodeValue encodeAttributes valueToDestruct
                , encodeValue encodeAttributes inValue
                ]

        IfThenElse a condition thenBranch elseBranch ->
            Encode.list identity
                [ Encode.string "IfThenElse"
                , encodeAttributes a
                , encodeValue encodeAttributes condition
                , encodeValue encodeAttributes thenBranch
                , encodeValue encodeAttributes elseBranch
                ]

        PatternMatch a branchOutOn cases ->
            Encode.list identity
                [ Encode.string "PatternMatch"
                , encodeAttributes a
                , encodeValue encodeAttributes branchOutOn
                , cases
                    |> Encode.list
                        (\( pattern, body ) ->
                            Encode.list identity
                                [ encodePattern encodeAttributes pattern
                                , encodeValue encodeAttributes body
                                ]
                        )
                ]

        UpdateRecord a valueToUpdate fieldsToUpdate ->
            Encode.list identity
                [ Encode.string "Update"
                , encodeAttributes a
                , encodeValue encodeAttributes valueToUpdate
                , fieldsToUpdate
                    |> Encode.list
                        (\( fieldName, fieldValue ) ->
                            Encode.list identity
                                [ encodeName fieldName
                                , encodeValue encodeAttributes fieldValue
                                ]
                        )
                ]

        Unit a ->
            Encode.list identity
                [ Encode.string "Unit"
                , encodeAttributes a
                ]


decodeValue : Decode.Decoder a -> Decode.Decoder (Value a)
decodeValue decodeAttributes =
    let
        lazyDecodeValue =
            Decode.lazy <|
                \_ ->
                    decodeValue decodeAttributes
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "Literal" ->
                        Decode.map2 Literal
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeLiteral)

                    "Constructor" ->
                        Decode.map2 Constructor
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)

                    "Tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "List" ->
                        Decode.map2 List
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "Record" ->
                        Decode.map2 Record
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeValue decodeAttributes)
                                    )
                                )
                            )

                    "Variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "Reference" ->
                        Decode.map2 Reference
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)

                    "Field" ->
                        Decode.map3 Field
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 decodeName)

                    "FieldFunction" ->
                        Decode.map2 FieldFunction
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "Apply" ->
                        Decode.map3 Apply
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "Lambda" ->
                        Decode.map3 Lambda
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodePattern decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "LetDefinition" ->
                        Decode.map4 LetDefinition
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 <| decodeDefinition decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "LetRecursion" ->
                        Decode.map3 LetRecursion
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeDefinition decodeAttributes)
                                    )
                                    |> Decode.map Dict.fromList
                                )
                            )
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "Destructure" ->
                        Decode.map4 Destructure
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodePattern decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "IfThenElse" ->
                        Decode.map4 IfThenElse
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "PatternMatch" ->
                        Decode.map3 PatternMatch
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <|
                                Decode.list
                                    (Decode.map2 Tuple.pair
                                        (decodePattern decodeAttributes)
                                        (decodeValue decodeAttributes)
                                    )
                            )

                    "UpdateRecord" ->
                        Decode.map3 UpdateRecord
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <|
                                Decode.list <|
                                    Decode.map2 Tuple.pair
                                        decodeName
                                        (decodeValue decodeAttributes)
                            )

                    "Unit" ->
                        Decode.map Unit
                            (Decode.index 1 decodeAttributes)

                    other ->
                        Decode.fail <| "Unknown value type: " ++ other
            )


encodePattern : (a -> Encode.Value) -> Pattern a -> Encode.Value
encodePattern encodeAttributes pattern =
    case pattern of
        WildcardPattern a ->
            Encode.list identity
                [ Encode.string "WildcardPattern"
                , encodeAttributes a
                ]

        AsPattern a p name ->
            Encode.list identity
                [ Encode.string "AsPattern"
                , encodeAttributes a
                , encodePattern encodeAttributes p
                , encodeName name
                ]

        TuplePattern a elementPatterns ->
            Encode.list identity
                [ Encode.string "TuplePattern"
                , encodeAttributes a
                , elementPatterns |> Encode.list (encodePattern encodeAttributes)
                ]

        RecordPattern a fieldNames ->
            Encode.list identity
                [ Encode.string "RecordPattern"
                , encodeAttributes a
                , fieldNames |> Encode.list encodeName
                ]

        ConstructorPattern a constructorName argumentPatterns ->
            Encode.list identity
                [ Encode.string "ConstructorPattern"
                , encodeAttributes a
                , encodeFQName constructorName
                , argumentPatterns |> Encode.list (encodePattern encodeAttributes)
                ]

        EmptyListPattern a ->
            Encode.list identity
                [ Encode.string "EmptyListPattern"
                , encodeAttributes a
                ]

        HeadTailPattern a headPattern tailPattern ->
            Encode.list identity
                [ Encode.string "HeadTailPattern"
                , encodeAttributes a
                , encodePattern encodeAttributes headPattern
                , encodePattern encodeAttributes tailPattern
                ]

        LiteralPattern a value ->
            Encode.list identity
                [ Encode.string "LiteralPattern"
                , encodeAttributes a
                , encodeLiteral value
                ]

        UnitPattern a ->
            Encode.list identity
                [ Encode.string "UnitPattern"
                , encodeAttributes a
                ]


decodePattern : Decode.Decoder a -> Decode.Decoder (Pattern a)
decodePattern decodeAttributes =
    let
        lazyDecodePattern =
            Decode.lazy <|
                \_ ->
                    decodePattern decodeAttributes
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "WildcardPattern" ->
                        Decode.map WildcardPattern
                            (Decode.index 1 decodeAttributes)

                    "AsPattern" ->
                        Decode.map3 AsPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodePattern)
                            (Decode.index 3 decodeName)

                    "TuplePattern" ->
                        Decode.map2 TuplePattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodePattern)

                    "RecordPattern" ->
                        Decode.map2 RecordPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list decodeName)

                    "ConstructorPattern" ->
                        Decode.map3 ConstructorPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)
                            (Decode.index 3 <| Decode.list lazyDecodePattern)

                    "EmptyListPattern" ->
                        Decode.map EmptyListPattern
                            (Decode.index 1 decodeAttributes)

                    "HeadTailPattern" ->
                        Decode.map3 HeadTailPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodePattern)
                            (Decode.index 3 lazyDecodePattern)

                    other ->
                        Decode.fail <| "Unknown pattern type: " ++ other
            )


encodeLiteral : Literal -> Encode.Value
encodeLiteral l =
    let
        typeTag tag =
            ( "@type", Encode.string tag )
    in
    case l of
        BoolLiteral v ->
            Encode.object
                [ typeTag "boolLiteral"
                , ( "value", Encode.bool v )
                ]

        CharLiteral v ->
            Encode.object
                [ typeTag "charLiteral"
                , ( "value", Encode.string (String.fromChar v) )
                ]

        StringLiteral v ->
            Encode.object
                [ typeTag "stringLiteral"
                , ( "value", Encode.string v )
                ]

        IntLiteral v ->
            Encode.object
                [ typeTag "intLiteral"
                , ( "value", Encode.int v )
                ]

        FloatLiteral v ->
            Encode.object
                [ typeTag "floatLiteral"
                , ( "value", Encode.float v )
                ]


decodeLiteral : Decode.Decoder Literal
decodeLiteral =
    Decode.field "@type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "boolLiteral" ->
                        Decode.map BoolLiteral
                            (Decode.field "value" Decode.bool)

                    "charLiteral" ->
                        Decode.map CharLiteral
                            (Decode.field "value" Decode.string
                                |> Decode.andThen
                                    (\str ->
                                        case String.uncons str of
                                            Just ( ch, _ ) ->
                                                Decode.succeed ch

                                            Nothing ->
                                                Decode.fail "Single char expected"
                                    )
                            )

                    "stringLiteral" ->
                        Decode.map StringLiteral
                            (Decode.field "value" Decode.string)

                    "intLiteral" ->
                        Decode.map IntLiteral
                            (Decode.field "value" Decode.int)

                    "floatLiteral" ->
                        Decode.map FloatLiteral
                            (Decode.field "value" Decode.float)

                    other ->
                        Decode.fail <| "Unknown literal type: " ++ other
            )


encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    Encode.object
        [ ( "inputs"
          , spec.inputs
                |> Encode.list
                    (\( argName, argType ) ->
                        Encode.object
                            [ ( "argName", encodeName argName )
                            , ( "argType", encodeType encodeAttributes argType )
                            ]
                    )
          )
        , ( "output", encodeType encodeAttributes spec.output )
        ]


encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    Encode.list identity
        [ Encode.string "Definition"
        , case def.valueType of
            Just valueType ->
                encodeType encodeAttributes valueType

            Nothing ->
                Encode.null
        , def.arguments
            |> Encode.list
                (\( name, a ) ->
                    Encode.list identity
                        [ encodeName name
                        , encodeAttributes a
                        ]
                )
        , encodeValue encodeAttributes def.body
        ]


decodeDefinition : Decode.Decoder a -> Decode.Decoder (Definition a)
decodeDefinition decodeAttributes =
    Decode.map3 Definition
        (Decode.index 1 (Decode.maybe (decodeType decodeAttributes)))
        (Decode.index 2 (Decode.list (Decode.map2 Tuple.pair decodeName decodeAttributes)))
        (Decode.index 3 (Decode.lazy (\_ -> decodeValue decodeAttributes)))
