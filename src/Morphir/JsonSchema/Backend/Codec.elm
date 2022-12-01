module Morphir.JsonSchema.Backend.Codec exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Morphir.IR.Path as Path
import Morphir.JsonSchema.Backend exposing (Error, Errors, Options)
import Set


decodeOptions : Decoder Options
decodeOptions =
    Decode.map2 Options
        (Decode.field "limitToModules"
            (Decode.maybe
                (Decode.list
                    (Decode.string
                        |> Decode.map Path.fromString
                    )
                    |> Decode.map Set.fromList
                )
            )
        )
        (Decode.field "filename" Decode.string)


encodeErrors : Errors -> Encode.Value
encodeErrors errors =
    Encode.list Encode.string errors
