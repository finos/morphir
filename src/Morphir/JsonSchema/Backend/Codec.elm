module Morphir.JsonSchema.Backend.Codec exposing (..)

<<<<<<< HEAD
import Json.Decode as Decode exposing (Decoder)
import Morphir.JsonSchema.Backend exposing (Options)


decodeOptions : Decoder Options
decodeOptions =
    Decode.map Options (Decode.field "filename" Decode.string)
=======
import Json.Encode as Encode
import Morphir.JsonSchema.Backend exposing (Error)


encodeError : Error -> Encode.Value
encodeError error =
    Encode.list Encode.string error
>>>>>>> 031ee9f9 (Added feature to return all mapping errors)
