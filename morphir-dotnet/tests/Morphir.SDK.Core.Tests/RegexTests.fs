module Morphir.SDK.RegexTests

open Morphir.SDK.Testing
open Morphir.SDK

[<Tests>]
let tests =
    describe "Regex Tests" [
        describe "contains Tests" [
            let digit =
                Maybe.withDefault Regex.never
                <| Regex.fromString "[0-9]"

            testCase "abc123 contains digit == true"
            <| fun _ -> Expect.equal true (Regex.contains digit "abc123")

            testCase "abcxyz contains digit == false"
            <| fun _ -> Expect.equal false (Regex.contains digit "abcxyz")
        ]

        describe "Splitting Tests" [
            let comma =
                Maybe.withDefault Regex.never
                <| Regex.fromString " *, *"

            describe "split Tests" [
                testCase @"split comma ""tom,99,90,85"""
                <| fun _ ->
                    Expect.equal ([ "tom"; "99"; "90"; "85" ]) (Regex.split comma "tom,99,90,85")
                testCase @"split comma ""tom, 99, 90, 85"""
                <| fun _ ->
                    Expect.equal ([ "tom"; "99"; "90"; "85" ]) (Regex.split comma "tom, 99, 90, 85")
                testCase @"split comma ""tom , 99, 90, 85"""
                <| fun _ ->
                    Expect.equal
                        ([ "tom"; "99"; "90"; "85" ])
                        (Regex.split comma "tom , 99, 90, 85")
            ]

            describe "splitAtMost Tests" [
                testCase @"splitAtMost comma ""tom,99,90,85"""
                <| fun _ ->
                    Expect.equal
                        ([ "tom"; "99"; "90,85" ])
                        (Regex.splitAtMost 2 comma "tom,99,90,85")
            ]
        ]
    ]
