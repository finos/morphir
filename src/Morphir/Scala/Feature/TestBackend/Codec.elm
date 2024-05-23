module Morphir.Scala.Feature.TestBackend.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Scala.Feature.TestBackend as TestBackend
import Morphir.Type.Infer.Codec as InferCodec


encodeErrors : TestBackend.Errors -> Encode.Value
encodeErrors =
    Encode.list encodeError


encodeError : TestBackend.Error -> Encode.Value
encodeError error =
    case error of
        TestBackend.TestError errorMessage ->
            Encode.list Encode.string
                [ "TestError"
                , errorMessage
                ]

        TestBackend.InferenceError typeError ->
            Encode.list identity
                [ Encode.string "InferenceError"
                , InferCodec.encodeTypeError typeError
                ]
