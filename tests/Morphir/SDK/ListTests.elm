module Morphir.SDK.ListTests exposing (joinTests)

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
        , test "right outer keeps right" <|
            \_ ->
                [ 1, 2 ]
                    |> List.rightJoin [ 1, 3 ] (==)
                    |> Expect.equal [ ( Just 1, 1 ), ( Nothing, 3 ) ]
        ]
