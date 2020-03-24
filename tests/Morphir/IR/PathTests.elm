module Morphir.IR.PathTests exposing (..)

import Expect
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Test exposing (..)
import Json.Encode exposing (encode)

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
                        |> Path.encodePath
                        |> encode 0
                        |> Expect.equal expectedJsonText
    in
    describe "encodePath"
        [ assert (Path.fromList [Name.fromList ["alpha"], Name.fromList ["beta"], Name.fromList ["gamma"]])  """[["alpha"],["beta"],["gamma"]]"""
        , assert (Path.fromList [Name.fromList ["alpha","omega"], Name.fromList ["beta","delta"], Name.fromList ["gamma"]])  """[["alpha","omega"],["beta","delta"],["gamma"]]"""
        ]