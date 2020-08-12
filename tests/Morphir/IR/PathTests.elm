module Morphir.IR.PathTests exposing (..)

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
import Json.Encode exposing (encode)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Path.Codec exposing (encodePath)
import Test exposing (..)


isPrefixOfTests : Test
isPrefixOfTests =
    let
        toModuleName =
            Path.toString Name.toTitleCase "."

        boolToString bool =
            if bool then
                "True"

            else
                "False"

        isPrefixOf prefix path expectedResult =
            test ("isPrefixOf " ++ toModuleName prefix ++ " " ++ toModuleName path ++ " == " ++ boolToString expectedResult) <|
                \_ ->
                    Path.isPrefixOf prefix path
                        |> Expect.equal expectedResult
    in
    describe "fromString"
        [ isPrefixOf [ [ "foo" ], [ "bar" ] ] [ [ "foo" ] ] True
        , isPrefixOf [ [ "foo" ] ] [ [ "foo" ], [ "bar" ] ] False
        , isPrefixOf [ [ "foo" ], [ "bar" ] ] [ [ "foo" ], [ "bar" ] ] True
        ]


encodePathTests : Test
encodePathTests =
    let
        assert input expectedJsonText =
            test ("encodePath " ++ (expectedJsonText ++ " ")) <|
                \_ ->
                    Path.fromList input
                        |> encodePath
                        |> encode 0
                        |> Expect.equal expectedJsonText
    in
    describe "encodePath"
        [ assert (Path.fromList [ Name.fromList [ "alpha" ], Name.fromList [ "beta" ], Name.fromList [ "gamma" ] ]) """[["alpha"],["beta"],["gamma"]]"""
        , assert (Path.fromList [ Name.fromList [ "alpha", "omega" ], Name.fromList [ "beta", "delta" ], Name.fromList [ "gamma" ] ]) """[["alpha","omega"],["beta","delta"],["gamma"]]"""
        ]
