{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.Scala.Backend.Codec exposing
    ( decodeOptions
    , encodeError
    )

{-| Codecs for types in the `Morphir.Scala.Backend` module.


# Options

@docs decodeOptions
@docs encodeError

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Path as Path
import Morphir.Scala.Backend exposing (Error(..), Options)
import Morphir.Scala.Feature.TestBackend as TestBE
import Morphir.Scala.Feature.TestBackend.Codec as TestBECodec
import Set


{-| Decode Options.
-}
decodeOptions : Decode.Decoder Options
decodeOptions =
    Decode.map3 Options
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
        (Decode.field "includeCodecs"
            Decode.bool
        )
        decodeTestOptions


decodeTestOptions : Decode.Decoder TestBE.Options
decodeTestOptions =
    Decode.map2
        (\maybeGenericTest maybeScalaTest ->
            TestBE.Options
                (Maybe.withDefault False maybeGenericTest)
                (Maybe.withDefault False maybeScalaTest)
        )
        (Decode.maybe (Decode.field "generateTestGeneric" Decode.bool))
        (Decode.maybe (Decode.field "generateTestScalatest" Decode.bool))


{-| Encode Error
-}
encodeError : Error -> Encode.Value
encodeError error =
    case error of
        TestError errs ->
            TestBECodec.encodeErrors errs

        CodecError err ->
            Encode.string err
