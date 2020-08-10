{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module Morphir.IR.Value.Codec exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.FQName.Codec exposing (decodeFQName, encodeFQName)
import Morphir.IR.Literal.Codec exposing (decodeLiteral, encodeLiteral)
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Type.Codec exposing (decodeType, encodeType)
import Morphir.IR.Value exposing (Definition, Pattern(..), Specification, Value(..))


encodeValue : (a -> Encode.Value) -> Value a -> Encode.Value
encodeValue encodeAttributes v =
    case v of
        Literal a value ->
            Encode.list identity
                [ Encode.string "literal"
                , encodeAttributes a
                , encodeLiteral value
                ]

        Constructor a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "constructor"
                , encodeAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Tuple a elements ->
            Encode.list identity
                [ Encode.string "tuple"
                , encodeAttributes a
                , elements |> Encode.list (encodeValue encodeAttributes)
                ]

        List a items ->
            Encode.list identity
                [ Encode.string "list"
                , encodeAttributes a
                , items |> Encode.list (encodeValue encodeAttributes)
                ]

        Record a fields ->
            Encode.list identity
                [ Encode.string "record"
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
                [ Encode.string "variable"
                , encodeAttributes a
                , encodeName name
                ]

        Reference a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "reference"
                , encodeAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Field a subjectValue fieldName ->
            Encode.list identity
                [ Encode.string "field"
                , encodeAttributes a
                , encodeValue encodeAttributes subjectValue
                , encodeName fieldName
                ]

        FieldFunction a fieldName ->
            Encode.list identity
                [ Encode.string "field_function"
                , encodeAttributes a
                , encodeName fieldName
                ]

        Apply a function argument ->
            Encode.list identity
                [ Encode.string "apply"
                , encodeAttributes a
                , encodeValue encodeAttributes function
                , encodeValue encodeAttributes argument
                ]

        Lambda a argumentPattern body ->
            Encode.list identity
                [ Encode.string "lambda"
                , encodeAttributes a
                , encodePattern encodeAttributes argumentPattern
                , encodeValue encodeAttributes body
                ]

        LetDefinition a valueName valueDefinition inValue ->
            Encode.list identity
                [ Encode.string "let_definition"
                , encodeAttributes a
                , encodeName valueName
                , encodeDefinition encodeAttributes valueDefinition
                , encodeValue encodeAttributes inValue
                ]

        LetRecursion a valueDefinitions inValue ->
            Encode.list identity
                [ Encode.string "let_recursion"
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
                [ Encode.string "destructure"
                , encodeAttributes a
                , encodePattern encodeAttributes pattern
                , encodeValue encodeAttributes valueToDestruct
                , encodeValue encodeAttributes inValue
                ]

        IfThenElse a condition thenBranch elseBranch ->
            Encode.list identity
                [ Encode.string "if_then_else"
                , encodeAttributes a
                , encodeValue encodeAttributes condition
                , encodeValue encodeAttributes thenBranch
                , encodeValue encodeAttributes elseBranch
                ]

        PatternMatch a branchOutOn cases ->
            Encode.list identity
                [ Encode.string "pattern_match"
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
                [ Encode.string "update"
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
                [ Encode.string "unit"
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
                    "literal" ->
                        Decode.map2 Literal
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeLiteral)

                    "constructor" ->
                        Decode.map2 Constructor
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)

                    "tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "list" ->
                        Decode.map2 List
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "record" ->
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

                    "variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "reference" ->
                        Decode.map2 Reference
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)

                    "field" ->
                        Decode.map3 Field
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 decodeName)

                    "field_function" ->
                        Decode.map2 FieldFunction
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "apply" ->
                        Decode.map3 Apply
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "lambda" ->
                        Decode.map3 Lambda
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodePattern decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "let_definition" ->
                        Decode.map4 LetDefinition
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 <| decodeDefinition decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "let_recursion" ->
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

                    "destructure" ->
                        Decode.map4 Destructure
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodePattern decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "if_then_else" ->
                        Decode.map4 IfThenElse
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "pattern_match" ->
                        Decode.map3 PatternMatch
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <|
                                Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 (decodePattern decodeAttributes))
                                        (Decode.index 1 (decodeValue decodeAttributes))
                                    )
                            )

                    "update_record" ->
                        Decode.map3 UpdateRecord
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <|
                                Decode.list <|
                                    Decode.map2 Tuple.pair
                                        decodeName
                                        (decodeValue decodeAttributes)
                            )

                    "unit" ->
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
                [ Encode.string "wildcard_pattern"
                , encodeAttributes a
                ]

        AsPattern a p name ->
            Encode.list identity
                [ Encode.string "as_pattern"
                , encodeAttributes a
                , encodePattern encodeAttributes p
                , encodeName name
                ]

        TuplePattern a elementPatterns ->
            Encode.list identity
                [ Encode.string "tuple_pattern"
                , encodeAttributes a
                , elementPatterns |> Encode.list (encodePattern encodeAttributes)
                ]

        RecordPattern a fieldNames ->
            Encode.list identity
                [ Encode.string "record_pattern"
                , encodeAttributes a
                , fieldNames |> Encode.list encodeName
                ]

        ConstructorPattern a constructorName argumentPatterns ->
            Encode.list identity
                [ Encode.string "constructor_pattern"
                , encodeAttributes a
                , encodeFQName constructorName
                , argumentPatterns |> Encode.list (encodePattern encodeAttributes)
                ]

        EmptyListPattern a ->
            Encode.list identity
                [ Encode.string "empty_list_pattern"
                , encodeAttributes a
                ]

        HeadTailPattern a headPattern tailPattern ->
            Encode.list identity
                [ Encode.string "head_tail_pattern"
                , encodeAttributes a
                , encodePattern encodeAttributes headPattern
                , encodePattern encodeAttributes tailPattern
                ]

        LiteralPattern a value ->
            Encode.list identity
                [ Encode.string "literal_pattern"
                , encodeAttributes a
                , encodeLiteral value
                ]

        UnitPattern a ->
            Encode.list identity
                [ Encode.string "unit_pattern"
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
                    "wildcard_pattern" ->
                        Decode.map WildcardPattern
                            (Decode.index 1 decodeAttributes)

                    "as_pattern" ->
                        Decode.map3 AsPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodePattern)
                            (Decode.index 3 decodeName)

                    "tuple_pattern" ->
                        Decode.map2 TuplePattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodePattern)

                    "record_pattern" ->
                        Decode.map2 RecordPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list decodeName)

                    "constructor_pattern" ->
                        Decode.map3 ConstructorPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)
                            (Decode.index 3 <| Decode.list lazyDecodePattern)

                    "empty_list_pattern" ->
                        Decode.map EmptyListPattern
                            (Decode.index 1 decodeAttributes)

                    "head_tail_pattern" ->
                        Decode.map3 HeadTailPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodePattern)
                            (Decode.index 3 lazyDecodePattern)

                    "unit_pattern" ->
                        Decode.map UnitPattern
                            (Decode.index 1 decodeAttributes)

                    other ->
                        Decode.fail <| "Unknown pattern type: " ++ other
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
    Encode.object
        [ ( "inputTypes"
          , def.inputTypes
                |> Encode.list
                    (\( argName, a, argType ) ->
                        Encode.list identity
                            [ encodeName argName
                            , encodeAttributes a
                            , encodeType encodeAttributes argType
                            ]
                    )
          )
        , ( "outputType", encodeType encodeAttributes def.outputType )
        , ( "body", encodeValue encodeAttributes def.body )
        ]


decodeDefinition : Decode.Decoder a -> Decode.Decoder (Definition a)
decodeDefinition decodeAttributes =
    Decode.map3 Definition
        (Decode.field "inputTypes"
            (Decode.list
                (Decode.map3 (\n a t -> ( n, a, t ))
                    (Decode.index 0 decodeName)
                    (Decode.index 1 decodeAttributes)
                    (Decode.index 2 (decodeType decodeAttributes))
                )
            )
        )
        (Decode.field "outputType" (decodeType decodeAttributes))
        (Decode.field "body" (Decode.lazy (\_ -> decodeValue decodeAttributes)))
