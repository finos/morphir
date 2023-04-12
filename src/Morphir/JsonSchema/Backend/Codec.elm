module Morphir.JsonSchema.Backend.Codec exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Morphir.IR.Path as Path
import Morphir.JsonSchema.Backend exposing (Errors, Options)
import Set


decodeOptions : Decoder Options
decodeOptions =
    Decode.map3 Options
        (Decode.field "filename" Decode.string)
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
        (Decode.field "include"
            (Decode.maybe
                (Decode.list
                    Decode.string
                    |> Decode.map Set.fromList
                )
            )
        )


encodeErrors : Errors -> Encode.Value
encodeErrors =
    Encode.list Encode.string
