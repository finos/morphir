module Morphir.IR.Module.Codec exposing (..)

{-| -}

import Dict
import Json.Encode as Encode
import Morphir.IR.AccessControlled.Codec exposing (encodeAccessControlled)
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
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "spec", TypeCodec.encodeSpecification encodeAttributes typeSpec )
                            ]
                    )
          )
        , ( "values"
          , spec.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueSpec ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "spec", ValueCodec.encodeSpecification encodeAttributes valueSpec )
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
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "def", encodeAccessControlled (TypeCodec.encodeDefinition encodeAttributes) typeDef )
                            ]
                    )
          )
        , ( "values"
          , def.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueDef ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "def", encodeAccessControlled (ValueCodec.encodeDefinition encodeAttributes) valueDef )
                            ]
                    )
          )
        ]
