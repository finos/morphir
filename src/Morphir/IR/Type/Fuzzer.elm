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


module Morphir.IR.Type.Fuzzer exposing (..)

{-| Generate random types.
-}

import Fuzz exposing (Fuzzer)
import Morphir.IR.FQName.Fuzzer exposing (fuzzFQName)
import Morphir.IR.Name.Fuzzer exposing (fuzzName)
import Morphir.IR.Type exposing (Field, Type(..))


fuzzType : Int -> Fuzzer a -> Fuzzer (Type a)
fuzzType maxDepth fuzzAttributes =
    let
        fuzzField depth =
            Fuzz.map2 Field
                fuzzName
                (fuzzType depth fuzzAttributes)

        fuzzVariable =
            Fuzz.map2 Variable
                fuzzAttributes
                fuzzName

        fuzzReference depth =
            Fuzz.map3 Reference
                fuzzAttributes
                fuzzFQName
                (Fuzz.list (fuzzType depth fuzzAttributes) |> Fuzz.map (List.take depth))

        fuzzTuple depth =
            Fuzz.map2 Tuple
                fuzzAttributes
                (Fuzz.list (fuzzType depth fuzzAttributes) |> Fuzz.map (List.take depth))

        fuzzRecord depth =
            Fuzz.map2 Record
                fuzzAttributes
                (Fuzz.list (fuzzField (depth - 1)) |> Fuzz.map (List.take depth))

        fuzzExtensibleRecord depth =
            Fuzz.map3 ExtensibleRecord
                fuzzAttributes
                fuzzName
                (Fuzz.list (fuzzField (depth - 1)) |> Fuzz.map (List.take depth))

        fuzzFunction depth =
            Fuzz.map3 Function
                fuzzAttributes
                (fuzzType depth fuzzAttributes)
                (fuzzType depth fuzzAttributes)

        fuzzUnit =
            Fuzz.map Unit
                fuzzAttributes

        fuzzLeaf =
            Fuzz.oneOf
                [ fuzzVariable
                , fuzzUnit
                ]

        fuzzBranch depth =
            Fuzz.oneOf
                [ fuzzFunction depth
                , fuzzReference depth
                , fuzzTuple depth
                , fuzzRecord depth
                , fuzzExtensibleRecord depth
                ]
    in
    if maxDepth <= 0 then
        fuzzLeaf

    else
        Fuzz.oneOf
            [ fuzzLeaf
            , fuzzBranch (maxDepth - 1)
            ]
