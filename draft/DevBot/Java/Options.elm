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


module SlateX.DevBot.Java.Options exposing (..)


import Json.Decode as Decode

type alias Options =
    { indent : Int
    , maxWidth : Int
    }


decodeOptions : Decode.Decoder Options
decodeOptions =
    Decode.map2 Options
        (Decode.field "indent" Decode.int)
        (Decode.field "maxWidth" Decode.int)
