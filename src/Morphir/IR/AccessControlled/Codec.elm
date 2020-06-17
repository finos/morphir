module Morphir.IR.AccessControlled.Codec exposing (..)

{-| Encode AccessControlled to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)


encodeAccessControlled : (a -> Encode.Value) -> AccessControlled a -> Encode.Value
encodeAccessControlled encodeValue ac =
    case ac.access of
        Public ->
            Encode.list identity
                [ Encode.string "public"
                , encodeValue ac.value
                ]

        Private ->
            Encode.list identity
                [ Encode.string "private"
                , encodeValue ac.value
                ]


{-| Decode AccessControlled from JSON.
-}
decodeAccessControlled : Decode.Decoder a -> Decode.Decoder (AccessControlled a)
decodeAccessControlled decodeValue =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "public" ->
                        Decode.map (AccessControlled Public)
                            (Decode.index 1 decodeValue)

                    "private" ->
                        Decode.map (AccessControlled Private)
                            (Decode.index 1 decodeValue)

                    other ->
                        Decode.fail <| "Unknown access controlled type: " ++ other
            )
