module Morphir.IR.Type.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled.Codec exposing (encodeAccessControlled)
import Morphir.IR.FQName.Codec exposing (decodeFQName, encodeFQName)
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Type exposing (Constructor(..), Constructors, Definition(..), Field, Specification(..), Type(..))


{-| Encode a type into JSON.
-}
encodeType : (a -> Encode.Value) -> Type a -> Encode.Value
encodeType encodeAttributes tpe =
    case tpe of
        Variable a name ->
            Encode.list identity
                [ Encode.string "variable"
                , encodeAttributes a
                , encodeName name
                ]

        Reference a typeName typeParameters ->
            Encode.list identity
                [ Encode.string "reference"
                , encodeAttributes a
                , encodeFQName typeName
                , Encode.list (encodeType encodeAttributes) typeParameters
                ]

        Tuple a elementTypes ->
            Encode.list identity
                [ Encode.string "tuple"
                , encodeAttributes a
                , Encode.list (encodeType encodeAttributes) elementTypes
                ]

        Record a fieldTypes ->
            Encode.list identity
                [ Encode.string "record"
                , encodeAttributes a
                , Encode.list (encodeField encodeAttributes) fieldTypes
                ]

        ExtensibleRecord a variableName fieldTypes ->
            Encode.list identity
                [ Encode.string "extensible_record"
                , encodeAttributes a
                , encodeName variableName
                , Encode.list (encodeField encodeAttributes) fieldTypes
                ]

        Function a argumentType returnType ->
            Encode.list identity
                [ Encode.string "function"
                , encodeAttributes a
                , encodeType encodeAttributes argumentType
                , encodeType encodeAttributes returnType
                ]

        Unit a ->
            Encode.list identity
                [ Encode.string "unit"
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
                    "variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "reference" ->
                        Decode.map3 Reference
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)
                            (Decode.index 3 (Decode.list (Decode.lazy (\_ -> decodeType decodeAttributes))))

                    "tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 (Decode.list lazyDecodeType))

                    "record" ->
                        Decode.map2 Record
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 (Decode.list lazyDecodeField))

                    "extensible_record" ->
                        Decode.map3 ExtensibleRecord
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 (Decode.list lazyDecodeField))

                    "function" ->
                        Decode.map3 Function
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodeType)
                            (Decode.index 3 lazyDecodeType)

                    "unit" ->
                        Decode.map Unit
                            (Decode.index 1 decodeAttributes)

                    _ ->
                        Decode.fail ("Unknown kind: " ++ kind)
            )


encodeField : (a -> Encode.Value) -> Field a -> Encode.Value
encodeField encodeAttributes field =
    Encode.list identity
        [ encodeName field.name
        , encodeType encodeAttributes field.tpe
        ]


decodeField : Decode.Decoder a -> Decode.Decoder (Field a)
decodeField decodeAttributes =
    Decode.map2 Field
        (Decode.index 0 decodeName)
        (Decode.index 1 (decodeType decodeAttributes))


{-| -}
encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    case spec of
        TypeAliasSpecification params exp ->
            Encode.list identity
                [ Encode.string "type_alias_specification"
                , Encode.list encodeName params
                , encodeType encodeAttributes exp
                ]

        OpaqueTypeSpecification params ->
            Encode.list identity
                [ Encode.string "opaque_type_specification"
                , Encode.list encodeName params
                ]

        CustomTypeSpecification params ctors ->
            Encode.list identity
                [ Encode.string "custom_type_specification"
                , Encode.list encodeName params
                , encodeConstructors encodeAttributes ctors
                ]


{-| -}
encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    case def of
        TypeAliasDefinition params exp ->
            Encode.list identity
                [ Encode.string "type_alias_definition"
                , Encode.list encodeName params
                , encodeType encodeAttributes exp
                ]

        CustomTypeDefinition params ctors ->
            Encode.list identity
                [ Encode.string "custom_type_definition"
                , Encode.list encodeName params
                , encodeAccessControlled (encodeConstructors encodeAttributes) ctors
                ]


encodeConstructors : (a -> Encode.Value) -> Constructors a -> Encode.Value
encodeConstructors encodeAttributes ctors =
    ctors
        |> Encode.list
            (\(Constructor ctorName ctorArgs) ->
                Encode.list identity
                    [ Encode.string "constructor"
                    , encodeName ctorName
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
