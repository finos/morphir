module Morphir.SDK.ListTests exposing (joinTests)

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

import Expect
import Morphir.SDK.List as List
import Test exposing (..)


joinTests : Test
joinTests =
    describe "joins"
        [ test "inner filters left" <|
            \_ ->
                [ 1, 2, 3 ]
                    |> List.innerJoin [ 1, 3 ] (==)
                    |> Expect.equal [ ( 1, 1 ), ( 3, 3 ) ]
        , test "inner filters right" <|
            \_ ->
                [ 1, 2 ]
                    |> List.innerJoin [ 1, 2, 3 ] (==)
                    |> Expect.equal [ ( 1, 1 ), ( 2, 2 ) ]
        , test "inner filters both" <|
            \_ ->
                [ 1, 2 ]
                    |> List.innerJoin [ 1, 3 ] (==)
                    |> Expect.equal [ ( 1, 1 ) ]
        , test "left outer keeps left" <|
            \_ ->
                [ 1, 2 ]
                    |> List.leftJoin [ 1, 3 ] (==)
                    |> Expect.equal [ ( 1, Just 1 ), ( 2, Nothing ) ]
        ]
