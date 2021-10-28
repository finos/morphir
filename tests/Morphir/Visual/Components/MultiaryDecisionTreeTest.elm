module Morphir.Visual.Components.MultiaryDecisionTreeTest exposing (..)

import Expect
import Morphir.Visual.Components.MultiaryDecisionTree as MultiaryDecisionTree exposing (..)
import Test exposing (..)

----------------------------------- Example Test: -----------------------------------------
exampleTest1 : Test
exampleTest1 =
    test "two plus two equals four"
        (\_ -> Expect.equal 4 (2 + 2))

exampleTest2 : Test
exampleTest2  =
    test "testing mapping function" <|
        \_ ->
        Expect.equal [0,0,0]  (List.map (\_ -> 0) [ 1, 2, 3 ])

exampleTest3 : Test
exampleTest3 =
    test "this should pass"
        \_ ->
            Expect.equal "success" "success"

exampleTest4 : Test
exampleTest4 =
    test "only 2 guardians have names with less than 6 characters" <|
        \_ ->
            let
                guardians =
                    [ "Star-lord", "Groot", "Gamora", "Drax", "Rocket" ]
            in
            guardians
                |> List.map String.length
                |> List.filter (\x -> x < 6)
                |> List.length
                |> Expect.equal 2
------------------------------------------------------------------------------------------
-- "describe" is used for grouping
















