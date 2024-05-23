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


module Morphir.JsonExtra exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode


encodeConstructor : String -> List Encode.Value -> Encode.Value
encodeConstructor typeTag args =
    Encode.string typeTag
        :: args
        |> Encode.list identity


decodeCustomType : (String -> Decode.Decoder a) -> Decode.Decoder a
decodeCustomType f =
    Decode.index 0 Decode.string
        |> Decode.andThen f


decodeConstructor : (a -> r) -> Decode.Decoder a -> Decode.Decoder r
decodeConstructor f a =
    Decode.map f
        (Decode.index 1 a)


decodeConstructor2 : (a -> b -> r) -> Decode.Decoder a -> Decode.Decoder b -> Decode.Decoder r
decodeConstructor2 f a b =
    Decode.map2 f
        (Decode.index 1 a)
        (Decode.index 2 b)


decodeConstructor3 : (a -> b -> c -> r) -> Decode.Decoder a -> Decode.Decoder b -> Decode.Decoder c -> Decode.Decoder r
decodeConstructor3 f a b c =
    Decode.map3 f
        (Decode.index 1 a)
        (Decode.index 2 b)
        (Decode.index 3 c)


decodeConstructor4 : (a -> b -> c -> d -> r) -> Decode.Decoder a -> Decode.Decoder b -> Decode.Decoder c -> Decode.Decoder d -> Decode.Decoder r
decodeConstructor4 f a b c d =
    Decode.map4 f
        (Decode.index 1 a)
        (Decode.index 2 b)
        (Decode.index 3 c)
        (Decode.index 4 d)
