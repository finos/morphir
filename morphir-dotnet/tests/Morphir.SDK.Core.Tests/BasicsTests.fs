module Morphir.SDK.BasicsTests

open Morphir.SDK.Testing
open Morphir.SDK

[<Tests>]
let tests =

    let basicMathTests =
        describe
            "Basic Math Tests"
            [

              describe
                  "add tests"
                  [ testCase "add float" <| fun _ -> Expect.equal 159.0 (Basics.add 155.6 3.4)
                    testCase "add int" <| fun _ -> Expect.equal 17 (Basics.add 10 7) ]

              describe
                  "abs tests"
                  [ testCase "abs -25" <| fun _ -> Expect.equal 25 (Basics.abs (-25))
                    testCase "abs 76" <| fun _ -> Expect.equal 76 (Basics.abs (76))

                    testCase "abs -3.14" <| fun _ -> Expect.equal 3.14 (Basics.abs (-3.14))
                    testCase "abs 98.6" <| fun _ -> Expect.equal 98.6 (Basics.abs (98.6)) ]

              describe
                  "pow tests"
                  [ testCase "pow 3^2" <| fun _ -> Expect.equal 9 (Basics.pow 3 2)
                    testCase "pow 3^3" <| fun _ -> Expect.equal 27 (Basics.pow 3 3) ] ]

    describe "Basics Tests" [ basicMathTests ]
