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


module Morphir.IR.Value.CodecV1 exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.FQName.CodecV1 exposing (decodeFQName, encodeFQName)
import Morphir.IR.Literal.CodecV1 exposing (decodeLiteral, encodeLiteral)
import Morphir.IR.Name.CodecV1 exposing (decodeName, encodeName)
import Morphir.IR.Type.CodecV1 exposing (decodeType, encodeType)
import Morphir.IR.Value exposing (Definition, Pattern(..), Specification, Value(..))


encodeValue : (ta -> Encode.Value) -> (va -> Encode.Value) -> Value ta va -> Encode.Value
encodeValue encodeTypeAttributes encodeValueAttributes v =
    case v of
        Literal a value ->
            Encode.list identity
                [ Encode.string "literal"
                , encodeValueAttributes a
                , encodeLiteral value
                ]

        Constructor a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "constructor"
                , encodeValueAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Tuple a elements ->
            Encode.list identity
                [ Encode.string "tuple"
                , encodeValueAttributes a
                , elements |> Encode.list (encodeValue encodeTypeAttributes encodeValueAttributes)
                ]

        List a items ->
            Encode.list identity
                [ Encode.string "list"
                , encodeValueAttributes a
                , items |> Encode.list (encodeValue encodeTypeAttributes encodeValueAttributes)
                ]

        Record a fields ->
            Encode.list identity
                [ Encode.string "record"
                , encodeValueAttributes a
                , fields
                    |> Dict.toList
                    |> Encode.list
                        (\( fieldName, fieldValue ) ->
                            Encode.list identity
                                [ encodeName fieldName
                                , encodeValue encodeTypeAttributes encodeValueAttributes fieldValue
                                ]
                        )
                ]

        Variable a name ->
            Encode.list identity
                [ Encode.string "variable"
                , encodeValueAttributes a
                , encodeName name
                ]

        Reference a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "reference"
                , encodeValueAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Field a subjectValue fieldName ->
            Encode.list identity
                [ Encode.string "field"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes subjectValue
                , encodeName fieldName
                ]

        FieldFunction a fieldName ->
            Encode.list identity
                [ Encode.string "field_function"
                , encodeValueAttributes a
                , encodeName fieldName
                ]

        Apply a function argument ->
            Encode.list identity
                [ Encode.string "apply"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes function
                , encodeValue encodeTypeAttributes encodeValueAttributes argument
                ]

        Lambda a argumentPattern body ->
            Encode.list identity
                [ Encode.string "lambda"
                , encodeValueAttributes a
                , encodePattern encodeValueAttributes argumentPattern
                , encodeValue encodeTypeAttributes encodeValueAttributes body
                ]

        LetDefinition a valueName valueDefinition inValue ->
            Encode.list identity
                [ Encode.string "let_definition"
                , encodeValueAttributes a
                , encodeName valueName
                , encodeDefinition encodeTypeAttributes encodeValueAttributes valueDefinition
                , encodeValue encodeTypeAttributes encodeValueAttributes inValue
                ]

        LetRecursion a valueDefinitions inValue ->
            Encode.list identity
                [ Encode.string "let_recursion"
                , encodeValueAttributes a
                , valueDefinitions
                    |> Dict.toList
                    |> Encode.list
                        (\( name, def ) ->
                            Encode.list identity
                                [ encodeName name
                                , encodeDefinition encodeTypeAttributes encodeValueAttributes def
                                ]
                        )
                , encodeValue encodeTypeAttributes encodeValueAttributes inValue
                ]

        Destructure a pattern valueToDestruct inValue ->
            Encode.list identity
                [ Encode.string "destructure"
                , encodeValueAttributes a
                , encodePattern encodeValueAttributes pattern
                , encodeValue encodeTypeAttributes encodeValueAttributes valueToDestruct
                , encodeValue encodeTypeAttributes encodeValueAttributes inValue
                ]

        IfThenElse a condition thenBranch elseBranch ->
            Encode.list identity
                [ Encode.string "if_then_else"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes condition
                , encodeValue encodeTypeAttributes encodeValueAttributes thenBranch
                , encodeValue encodeTypeAttributes encodeValueAttributes elseBranch
                ]

        PatternMatch a branchOutOn cases ->
            Encode.list identity
                [ Encode.string "pattern_match"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes branchOutOn
                , cases
                    |> Encode.list
                        (\( pattern, body ) ->
                            Encode.list identity
                                [ encodePattern encodeValueAttributes pattern
                                , encodeValue encodeTypeAttributes encodeValueAttributes body
                                ]
                        )
                ]

        UpdateRecord a valueToUpdate fieldsToUpdate ->
            Encode.list identity
                [ Encode.string "update_record"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes valueToUpdate
                , fieldsToUpdate
                    |> Dict.toList
                    |> Encode.list
                        (\( fieldName, fieldValue ) ->
                            Encode.list identity
                                [ encodeName fieldName
                                , encodeValue encodeTypeAttributes encodeValueAttributes fieldValue
                                ]
                        )
                ]

        Unit a ->
            Encode.list identity
                [ Encode.string "unit"
                , encodeValueAttributes a
                ]


decodeValue : Decode.Decoder ta -> Decode.Decoder va -> Decode.Decoder (Value ta va)
decodeValue decodeTypeAttributes decodeValueAttributes =
    let
        lazyDecodeValue =
            Decode.lazy <|
                \_ ->
                    decodeValue decodeTypeAttributes decodeValueAttributes
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "literal" ->
                        Decode.map2 Literal
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeLiteral)

                    "constructor" ->
                        Decode.map2 Constructor
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeFQName)

                    "tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "list" ->
                        Decode.map2 List
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "record" ->
                        Decode.map2 Record
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                                    )
                                    |> Decode.map Dict.fromList
                                )
                            )

                    "variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeName)

                    "reference" ->
                        Decode.map2 Reference
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeFQName)

                    "field" ->
                        Decode.map3 Field
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 3 decodeName)

                    "field_function" ->
                        Decode.map2 FieldFunction
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeName)

                    "apply" ->
                        Decode.map3 Apply
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "lambda" ->
                        Decode.map3 Lambda
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodePattern decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "let_definition" ->
                        Decode.map4 LetDefinition
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 <| decodeDefinition decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 4 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "let_recursion" ->
                        Decode.map3 LetRecursion
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeDefinition decodeTypeAttributes decodeValueAttributes)
                                    )
                                    |> Decode.map Dict.fromList
                                )
                            )
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "destructure" ->
                        Decode.map4 Destructure
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodePattern decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 4 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "if_then_else" ->
                        Decode.map4 IfThenElse
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 4 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "pattern_match" ->
                        Decode.map3 PatternMatch
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 3 <|
                                Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 (decodePattern decodeValueAttributes))
                                        (Decode.index 1 (decodeValue decodeTypeAttributes decodeValueAttributes))
                                    )
                            )

                    "update_record" ->
                        Decode.map3 UpdateRecord
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 (decodeValue decodeTypeAttributes decodeValueAttributes))
                            (Decode.index 3
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 (decodeValue decodeTypeAttributes decodeValueAttributes))
                                    )
                                    |> Decode.map Dict.fromList
                                )
                            )

                    "unit" ->
                        Decode.map Unit
                            (Decode.index 1 decodeValueAttributes)

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

                    "literal_pattern" ->
                        Decode.map2 LiteralPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeLiteral)

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
                        Encode.list identity
                            [ encodeName argName
                            , encodeType encodeAttributes argType
                            ]
                    )
          )
        , ( "output", encodeType encodeAttributes spec.output )
        ]


decodeSpecification : Decode.Decoder ta -> Decode.Decoder (Specification ta)
decodeSpecification decodeTypeAttributes =
    Decode.map2 Specification
        (Decode.field "inputs"
            (Decode.list
                (Decode.map2 Tuple.pair
                    (Decode.index 0 decodeName)
                    (Decode.index 1 (decodeType decodeTypeAttributes))
                )
            )
        )
        (Decode.field "output" (decodeType decodeTypeAttributes))


encodeDefinition : (ta -> Encode.Value) -> (va -> Encode.Value) -> Definition ta va -> Encode.Value
encodeDefinition encodeTypeAttributes encodeValueAttributes def =
    Encode.object
        [ ( "inputTypes"
          , def.inputTypes
                |> Encode.list
                    (\( argName, a, argType ) ->
                        Encode.list identity
                            [ encodeName argName
                            , encodeValueAttributes a
                            , encodeType encodeTypeAttributes argType
                            ]
                    )
          )
        , ( "outputType", encodeType encodeTypeAttributes def.outputType )
        , ( "body", encodeValue encodeTypeAttributes encodeValueAttributes def.body )
        ]


decodeDefinition : Decode.Decoder ta -> Decode.Decoder va -> Decode.Decoder (Definition ta va)
decodeDefinition decodeTypeAttributes decodeValueAttributes =
    Decode.map3 Definition
        (Decode.field "inputTypes"
            (Decode.list
                (Decode.map3 (\n a t -> ( n, a, t ))
                    (Decode.index 0 decodeName)
                    (Decode.index 1 decodeValueAttributes)
                    (Decode.index 2 (decodeType decodeTypeAttributes))
                )
            )
        )
        (Decode.field "outputType" (decodeType decodeTypeAttributes))
        (Decode.field "body" (Decode.lazy (\_ -> decodeValue decodeTypeAttributes decodeValueAttributes)))
