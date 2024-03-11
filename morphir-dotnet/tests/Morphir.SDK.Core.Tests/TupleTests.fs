module Morphir.SDK.TupleTests

open Morphir.SDK.Testing

[<Tests>]
let tests =
    describe "Tuple Tests" [
        describe "pair" [
            testCase "creates pair from 2 args"
            <| fun _ -> Expect.equal (3, 4) (Tuple.pair 3 4)

            testCase "creates pair from 2 args of different types"
            <| fun _ -> Expect.equal (1, "one") (Tuple.pair 1 "one")
        ]

        describe "first" [
            testCase "extracts first element"
            <| fun _ -> Expect.equal 1 (Tuple.first (1, 2))

            testCase "extracts first element from a pair of integers"
            <| fun _ -> Expect.equal 3 (Tuple.first (3, 4))

            testCase "extracts first element from a pair of strings"
            <| fun _ -> Expect.equal "john" (Tuple.first ("john", "doe"))

        ]

        describe "second" [
            testCase "extracts second element"
            <| fun _ -> Expect.equal 2 (Tuple.second (1, 2))

            testCase "extracts second element from a pair of integers"
            <| fun _ -> Expect.equal 2 (Tuple.second (1, 2))

            testCase "extracts second element from a pair of strings"
            <| fun _ -> Expect.equal "doe" (Tuple.second ("john", "doe"))
        ]

        describe "mapFirst" [
            testCase "applies function to first element"
            <| fun _ -> Expect.equal (5, 1) (Tuple.mapFirst ((*) 5) (1, 1))
        ]

        describe "mapSecond" [
            testCase "applies function to second element"
            <| fun _ -> Expect.equal (1, 5) (Tuple.mapSecond ((*) 5) (1, 1))
        ]

        describe "mapBoth" [
            testCase "applies function to both elements"
            <| fun _ -> Expect.equal (5, 10) (Tuple.mapBoth ((*) 5) ((*) 10) (1, 1))
        ]
    ]
