module Morphir.SDK.MaybeTests

open Morphir.SDK.Testing
open Morphir.SDK.Maybe

[<Tests>]
let tests =
    describe "Maybe Tests" [
        describe "Common Helpers Tests" [
            describe "withDefault Tests" [

                testCase "no default used"
                <| fun _ -> Expect.equal 0 (Maybe.withDefault 5 (Just 0))

                testCase "default used"
                <| fun _ -> Expect.equal 5 (Maybe.withDefault 5 Nothing)
            ]

            describe "map Tests" [
                let f n = n + 1

                testCase "on Just"
                <| fun _ -> Expect.equal (Just 1) (Maybe.map f (Just 0))

                testCase "on Nothing"
                <| fun _ -> Expect.equal (Just 1) (Maybe.map f (Just 0))

            ]

            describe "map2 Tests" [
                let f = (+)

                testCase "on (Just, Just)"
                <| fun _ -> Expect.equal (Just 1) (Maybe.map2 f (Just 0) (Just 1))

                testCase "on (Just, Nothing)"
                <| fun _ -> Expect.equal Nothing (Maybe.map2 f (Just 0) Nothing)

                testCase "on (Nothing, Just)"
                <| fun _ -> Expect.equal Nothing (Maybe.map2 f Nothing (Just 0))

            ]

            describe "map3 Tests" [
                let f a b c = a + b + c

                testCase "on (Just, Just, Just)"
                <| fun _ -> Expect.equal (Just 3) (Maybe.map3 f (Just 1) (Just 1) (Just 1))

                testCase "on (Just, Just, Nothing)"
                <| fun _ -> Expect.equal Nothing (Maybe.map3 f (Just 1) (Just 1) Nothing)

                testCase "on (Just, Nothing, Just)"
                <| fun _ -> Expect.equal Nothing (Maybe.map3 f (Just 1) Nothing (Just 0))

                testCase "on (Nothing, Just, Just)"
                <| fun _ -> Expect.equal Nothing (Maybe.map3 f Nothing (Just 1) (Just 1))

            ]
        ]

        describe "Chaining Maybes Tests" [
            describe "andThen Tests" [
                testCase "succeeding chain"
                <| fun _ -> Expect.equal (Just 1) (Maybe.andThen (fun a -> Just a) (Just 1))

                testCase "failing chain (original Maybe failed)"
                <| fun _ -> Expect.equal Nothing (Maybe.andThen (fun a -> Just a) Nothing)

                testCase "failing chain (chained function failed)"
                <| fun _ -> Expect.equal Nothing (Maybe.andThen (fun _ -> Nothing) Nothing)
            ]
        ]
    ]
