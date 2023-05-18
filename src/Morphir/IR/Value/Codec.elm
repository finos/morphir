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


encodeValue : (ta -> Encode.Value) -> (va -> Encode.Value) -> Value ta va -> Encode.Value
encodeValue encodeTypeAttributes encodeValueAttributes v =
    case v of
        Literal a value ->
            Encode.list identity
                [ Encode.string "Literal"
                , encodeValueAttributes a
                , encodeLiteral value
                ]

        Constructor a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "Constructor"
                , encodeValueAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Tuple a elements ->
            Encode.list identity
                [ Encode.string "Tuple"
                , encodeValueAttributes a
                , elements |> Encode.list (encodeValue encodeTypeAttributes encodeValueAttributes)
                ]

        List a items ->
            Encode.list identity
                [ Encode.string "List"
                , encodeValueAttributes a
                , items |> Encode.list (encodeValue encodeTypeAttributes encodeValueAttributes)
                ]

        Record a fields ->
            Encode.list identity
                [ Encode.string "Record"
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
                [ Encode.string "Variable"
                , encodeValueAttributes a
                , encodeName name
                ]

        Reference a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "Reference"
                , encodeValueAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Field a subjectValue fieldName ->
            Encode.list identity
                [ Encode.string "Field"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes subjectValue
                , encodeName fieldName
                ]

        FieldFunction a fieldName ->
            Encode.list identity
                [ Encode.string "FieldFunction"
                , encodeValueAttributes a
                , encodeName fieldName
                ]

        Apply a function argument ->
            Encode.list identity
                [ Encode.string "Apply"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes function
                , encodeValue encodeTypeAttributes encodeValueAttributes argument
                ]

        Lambda a argumentPattern body ->
            Encode.list identity
                [ Encode.string "Lambda"
                , encodeValueAttributes a
                , encodePattern encodeValueAttributes argumentPattern
                , encodeValue encodeTypeAttributes encodeValueAttributes body
                ]

        LetDefinition a valueName valueDefinition inValue ->
            Encode.list identity
                [ Encode.string "LetDefinition"
                , encodeValueAttributes a
                , encodeName valueName
                , encodeDefinition encodeTypeAttributes encodeValueAttributes valueDefinition
                , encodeValue encodeTypeAttributes encodeValueAttributes inValue
                ]

        LetRecursion a valueDefinitions inValue ->
            Encode.list identity
                [ Encode.string "LetRecursion"
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
                [ Encode.string "Destructure"
                , encodeValueAttributes a
                , encodePattern encodeValueAttributes pattern
                , encodeValue encodeTypeAttributes encodeValueAttributes valueToDestruct
                , encodeValue encodeTypeAttributes encodeValueAttributes inValue
                ]

        IfThenElse a condition thenBranch elseBranch ->
            Encode.list identity
                [ Encode.string "IfThenElse"
                , encodeValueAttributes a
                , encodeValue encodeTypeAttributes encodeValueAttributes condition
                , encodeValue encodeTypeAttributes encodeValueAttributes thenBranch
                , encodeValue encodeTypeAttributes encodeValueAttributes elseBranch
                ]

        PatternMatch a branchOutOn cases ->
            Encode.list identity
                [ Encode.string "PatternMatch"
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
                [ Encode.string "UpdateRecord"
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
                [ Encode.string "Unit"
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
                    "Literal" ->
                        Decode.map2 Literal
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeLiteral)

                    "Constructor" ->
                        Decode.map2 Constructor
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeFQName)

                    "Tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "List" ->
                        Decode.map2 List
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "Record" ->
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

                    "Variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeName)

                    "Reference" ->
                        Decode.map2 Reference
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeFQName)

                    "Field" ->
                        Decode.map3 Field
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 3 decodeName)

                    "FieldFunction" ->
                        Decode.map2 FieldFunction
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeName)

                    "Apply" ->
                        Decode.map3 Apply
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "Lambda" ->
                        Decode.map3 Lambda
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodePattern decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "LetDefinition" ->
                        Decode.map4 LetDefinition
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 <| decodeDefinition decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 4 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "LetRecursion" ->
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

                    "Destructure" ->
                        Decode.map4 Destructure
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodePattern decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 4 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "IfThenElse" ->
                        Decode.map4 IfThenElse
                            (Decode.index 1 decodeValueAttributes)
                            (Decode.index 2 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 3 <| decodeValue decodeTypeAttributes decodeValueAttributes)
                            (Decode.index 4 <| decodeValue decodeTypeAttributes decodeValueAttributes)

                    "PatternMatch" ->
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

                    "UpdateRecord" ->
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

                    "Unit" ->
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

                    "LiteralPattern" ->
                        Decode.map2 LiteralPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeLiteral)

                    "UnitPattern" ->
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
