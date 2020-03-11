module Morphir.IR.PathTests exposing (..)

import Expect
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
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
