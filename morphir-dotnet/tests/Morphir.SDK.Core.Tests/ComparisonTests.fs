module Morphir.SDK.ComparisonTests

open Morphir.SDK.Testing
open Morphir.SDK

[<Tests>]
let tests =
    describe "Comparison" [
        describe "max tests" [
            testCase "max"
            <| fun _ -> Expect.equal 42 (Basics.max 32 42)
            testCase "min"
            <| fun _ -> Expect.equal 42 (Basics.min 91 42)
        ]
    ]
