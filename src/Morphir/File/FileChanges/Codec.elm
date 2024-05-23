module Morphir.File.FileChanges.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.File.FileChanges exposing (Change(..), FileChanges)


encodeFileChanges : FileChanges -> Encode.Value
encodeFileChanges fileChanges =
    Encode.dict
        identity
        encodeChange
        fileChanges


decodeFileChanges : Decode.Decoder FileChanges
decodeFileChanges =
    Decode.dict
        decodeChange


encodeChange : Change -> Encode.Value
encodeChange change =
    case change of
        Insert content ->
            Encode.list Encode.string [ "Insert", content ]

        Update content ->
            Encode.list Encode.string [ "Update", content ]

        Delete ->
            Encode.list Encode.string [ "Delete" ]


decodeChange : Decode.Decoder Change
decodeChange =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "Insert" ->
                        Decode.map Insert
                            (Decode.index 1 Decode.string)

                    "Update" ->
                        Decode.map Update
                            (Decode.index 1 Decode.string)

                    "Delete" ->
                        Decode.succeed Delete

                    other ->
                        Decode.fail ("Unknown tag: " ++ other)
            )
