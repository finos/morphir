module Morphir.SDK.ResultTests

open Morphir.SDK
open Morphir.SDK.Testing
open Morphir.SDK.Result

[<Tests>]
let tests =
    describe "Result Tests" [
        describe "Creation" [
            describe "Err" [
                testCase "creates an Error"
                <| fun _ -> Expect.equal (Error "Nope") (Err "Nope")
            ]
        ]

        describe "Pattern matching" [
            describe "Err" [
            //                testCase "Err should match error cases" <|
            //                    fun _ ->
            //                        let result =

            ]
        ]
    ]
