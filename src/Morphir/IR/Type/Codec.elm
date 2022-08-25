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


module Morphir.IR.Type.Codec exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled.Codec exposing (decodeAccessControlled, encodeAccessControlled)
import Morphir.IR.FQName.Codec exposing (decodeFQName, encodeFQName)
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Type exposing (Constructors, Definition(..), Field, Specification(..), Type(..))


{-| Encode a type into JSON.
-}
encodeType : (a -> Encode.Value) -> Type a -> Encode.Value
encodeType encodeAttributes tpe =
    case tpe of
        Variable a name ->
            Encode.list identity
                [ Encode.string "Variable"
                , encodeAttributes a
                , encodeName name
                ]

        Reference a typeName typeParameters ->
            Encode.list identity
                [ Encode.string "Reference"
                , encodeAttributes a
                , encodeFQName typeName
                , Encode.list (encodeType encodeAttributes) typeParameters
                ]

        Tuple a elementTypes ->
            Encode.list identity
                [ Encode.string "Tuple"
                , encodeAttributes a
                , Encode.list (encodeType encodeAttributes) elementTypes
                ]

        Record a fieldTypes ->
            Encode.list identity
                [ Encode.string "Record"
                , encodeAttributes a
                , Encode.list (encodeField encodeAttributes) fieldTypes
                ]

        ExtensibleRecord a variableName fieldTypes ->
            Encode.list identity
                [ Encode.string "ExtensibleRecord"
                , encodeAttributes a
                , encodeName variableName
                , Encode.list (encodeField encodeAttributes) fieldTypes
                ]

        Function a argumentType returnType ->
            Encode.list identity
                [ Encode.string "Function"
                , encodeAttributes a
                , encodeType encodeAttributes argumentType
                , encodeType encodeAttributes returnType
                ]

        Unit a ->
            Encode.list identity
                [ Encode.string "Unit"
                , encodeAttributes a
                ]


{-| Decode a type from JSON.
-}
decodeType : Decode.Decoder a -> Decode.Decoder (Type a)
decodeType decodeAttributes =
    let
        lazyDecodeType =
            Decode.lazy
                (\_ ->
                    decodeType decodeAttributes
                )

        lazyDecodeField =
            Decode.lazy
                (\_ ->
                    decodeField decodeAttributes
                )
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "Variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "Reference" ->
                        Decode.map3 Reference
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)
                            (Decode.index 3 (Decode.list (Decode.lazy (\_ -> decodeType decodeAttributes))))

                    "Tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 (Decode.list lazyDecodeType))

                    "Record" ->
                        Decode.map2 Record
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 (Decode.list lazyDecodeField))

                    "ExtensibleRecord" ->
                        Decode.map3 ExtensibleRecord
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 (Decode.list lazyDecodeField))

                    "Function" ->
                        Decode.map3 Function
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodeType)
                            (Decode.index 3 lazyDecodeType)

                    "Unit" ->
                        Decode.map Unit
                            (Decode.index 1 decodeAttributes)

                    _ ->
                        Decode.fail ("Unknown kind: " ++ kind)
            )


encodeField : (a -> Encode.Value) -> Field a -> Encode.Value
encodeField encodeAttributes field =
    Encode.object
        [ ( "name", encodeName field.name )
        , ( "tpe", encodeType encodeAttributes field.tpe )
        ]


decodeField : Decode.Decoder a -> Decode.Decoder (Field a)
decodeField decodeAttributes =
    Decode.map2 Field
        (Decode.field "name" decodeName)
        (Decode.field "tpe" (decodeType decodeAttributes))


{-| -}
encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    case spec of
        TypeAliasSpecification params exp ->
            Encode.list identity
                [ Encode.string "TypeAliasSpecification"
                , Encode.list encodeName params
                , encodeType encodeAttributes exp
                ]

        OpaqueTypeSpecification params ->
            Encode.list identity
                [ Encode.string "OpaqueTypeSpecification"
                , Encode.list encodeName params
                ]

        CustomTypeSpecification params ctors ->
            Encode.list identity
                [ Encode.string "CustomTypeSpecification"
                , Encode.list encodeName params
                , encodeConstructors encodeAttributes ctors
                ]

        DerivedTypeSpecification params config ->
            Encode.list identity
                [ Encode.string "DerivedTypeSpecification"
                , Encode.list encodeName params
                , Encode.object
                    [ ( "baseType", encodeType encodeAttributes config.baseType )
                    , ( "fromBaseType", encodeFQName config.fromBaseType )
                    , ( "toBaseType", encodeFQName config.toBaseType )
                    ]
                ]


decodeSpecification : Decode.Decoder a -> Decode.Decoder (Specification a)
decodeSpecification decodeAttributes =
    let
        decodeDerivedTypeConfig =
            Decode.map3
                (\baseType fromBaseType toBaseType ->
                    { baseType = baseType
                    , fromBaseType = fromBaseType
                    , toBaseType = toBaseType
                    }
                )
                (Decode.field "baseType" (decodeType decodeAttributes))
                (Decode.field "fromBaseType" decodeFQName)
                (Decode.field "toBaseType" decodeFQName)
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "TypeAliasSpecification" ->
                        Decode.map2 TypeAliasSpecification
                            (Decode.index 1 (Decode.list decodeName))
                            (Decode.index 2 (decodeType decodeAttributes))

                    "OpaqueTypeSpecification" ->
                        Decode.map OpaqueTypeSpecification
                            (Decode.index 1 (Decode.list decodeName))

                    "CustomTypeSpecification" ->
                        Decode.map2 CustomTypeSpecification
                            (Decode.index 1 (Decode.list decodeName))
                            (Decode.index 2 (decodeConstructors decodeAttributes))

                    "DerivedTypeSpecification" ->
                        Decode.map2 DerivedTypeSpecification
                            (Decode.index 1 (Decode.list decodeName))
                            (Decode.index 2 decodeDerivedTypeConfig)

                    _ ->
                        Decode.fail ("Unknown kind: " ++ kind)
            )


{-| -}
encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    case def of
        TypeAliasDefinition params exp ->
            Encode.list identity
                [ Encode.string "TypeAliasDefinition"
                , Encode.list encodeName params
                , encodeType encodeAttributes exp
                ]

        CustomTypeDefinition params ctors ->
            Encode.list identity
                [ Encode.string "CustomTypeDefinition"
                , Encode.list encodeName params
                , encodeAccessControlled (encodeConstructors encodeAttributes) ctors
                ]


decodeDefinition : Decode.Decoder a -> Decode.Decoder (Definition a)
decodeDefinition decodeAttributes =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "TypeAliasDefinition" ->
                        Decode.map2 TypeAliasDefinition
                            (Decode.index 1 (Decode.list decodeName))
                            (Decode.index 2 (decodeType decodeAttributes))

                    "CustomTypeDefinition" ->
                        Decode.map2 CustomTypeDefinition
                            (Decode.index 1 (Decode.list decodeName))
                            (Decode.index 2 (decodeAccessControlled (decodeConstructors decodeAttributes)))

                    _ ->
                        Decode.fail ("Unknown kind: " ++ kind)
            )


encodeConstructors : (a -> Encode.Value) -> Constructors a -> Encode.Value
encodeConstructors encodeAttributes ctors =
    ctors
        |> Dict.toList
        |> Encode.list
            (\( ctorName, ctorArgs ) ->
                Encode.list identity
                    [ encodeName ctorName
                    , ctorArgs
                        |> Encode.list
                            (\( argName, argType ) ->
                                Encode.list identity
                                    [ encodeName argName
                                    , encodeType encodeAttributes argType
                                    ]
                            )
                    ]
            )


decodeConstructors : Decode.Decoder a -> Decode.Decoder (Constructors a)
decodeConstructors decodeAttributes =
    Decode.list
        (Decode.map2 Tuple.pair
            (Decode.index 0 decodeName)
            (Decode.index 1
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodeName)
                        (Decode.index 1 (decodeType decodeAttributes))
                    )
                )
            )
        )
        |> Decode.map Dict.fromList
