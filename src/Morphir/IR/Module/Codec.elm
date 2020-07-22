module Morphir.IR.Module.Codec exposing (..)

{-| -}

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled.Codec exposing (encodeAccessControlled)
import Morphir.IR.Documented.Codec exposing (encodeDocumented)
import Morphir.IR.Module exposing (Definition, Specification)
import Morphir.IR.Name.Codec exposing (encodeName)
import Morphir.IR.Type.Codec as TypeCodec
import Morphir.IR.Value.Codec as ValueCodec


{-| -}
encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    Encode.object
        [ ( "types"
          , spec.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeSpec ) ->
                        Encode.list identity
                            [ encodeName name
                            , typeSpec |> encodeDocumented (TypeCodec.encodeSpecification encodeAttributes)
                            ]
                    )
          )
        , ( "values"
          , spec.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueSpec ) ->
                        Encode.list identity
                            [ encodeName name
                            , valueSpec |> ValueCodec.encodeSpecification encodeAttributes
                            ]
                    )
          )
        ]


encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    Encode.object
        [ ( "types"
          , def.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeDef ) ->
                        Encode.list identity
                            [ encodeName name
                            , typeDef |> encodeAccessControlled (encodeDocumented (TypeCodec.encodeDefinition encodeAttributes))
                            ]
                    )
          )
        , ( "values"
          , def.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueDef ) ->
                        Encode.list identity
                            [ encodeName name
                            , valueDef |> encodeAccessControlled (ValueCodec.encodeDefinition encodeAttributes)
                            ]
                    )
          )
        ]


decodeDefinition : Decode.Decoder a -> Decode.Decoder (Definition a)
decodeDefinition decodeAttributes =
    Decode.succeed { types = Dict.empty, values = Dict.empty }
