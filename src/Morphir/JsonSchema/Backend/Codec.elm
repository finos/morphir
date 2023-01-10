module Morphir.JsonSchema.Backend.Codec exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Morphir.IR.Path as Path
import Morphir.JsonSchema.Backend exposing (Options)
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
