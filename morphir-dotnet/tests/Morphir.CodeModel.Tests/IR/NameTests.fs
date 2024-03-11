module Morphir.IR.NameTests

open Morphir.SDK.Testing
open Morphir.IR
//open Thoth.Json.Net

[<Tests>]
let tests =
    let fromString =
        describe
            "fromString"
            [ let assert' inString outList =
                  testCase ("From string" + inString)
                  <| fun _ -> Name.fromString inString |> Expect.equal (Name.fromList outList)

              assert' "fooBar_baz 123" [ "foo"; "bar"; "baz"; "123" ]

              assert' "valueInUSD" [ "value"; "in"; "u"; "s"; "d" ]

              assert' "ValueInUSD" [ "value"; "in"; "u"; "s"; "d" ]

              assert' "value_in_USD" [ "value"; "in"; "u"; "s"; "d" ]

              assert' "_-% " [] ]

    let toTitleCaseTests =
        describe
            "toTitleCase"
            [ let assert' inList outString =
                  testCase $"Title case %s{outString}"
                  <| fun _ -> Name.fromList inList |> Name.toTitleCase |> Expect.equal outString

              assert' [ "foo"; "bar"; "baz"; "123" ] "FooBarBaz123"

              assert' [ "value"; "in"; "u"; "s"; "d" ] "ValueInUSD" ]

    let toCamelCaseTests =
        describe
            "toCamelCase"
            [ let assert' inList outString =
                  testCase $"Camel case %s{outString}"
                  <| fun _ -> Name.fromList inList |> Name.toCamelCase |> Expect.equal outString

              assert' [ "foo"; "bar"; "baz"; "123" ] "fooBarBaz123"

              assert' [ "value"; "in"; "u"; "s"; "d" ] "valueInUSD" ]

    let toSnakeCaseTests =
        describe
            "toSnakeCase"
            [ let assert' inList outString =
                  testCase $"Snake case %s{outString}"
                  <| fun _ -> Name.fromList inList |> Name.toSnakeCase |> Expect.equal outString

              assert' [ "foo"; "bar"; "baz"; "123" ] "foo_bar_baz_123"

              assert' [ "value"; "in"; "u"; "s"; "d" ] "value_in_USD" ]

    let toHumanWordsTests =
        describe
            "toHumanWords"
            [ let assert' inList outList =
                  testCase $"Human words %A{outList}"
                  <| fun _ -> Name.fromList inList |> Name.toHumanWords |> Expect.equal outList

              assert' [ "foo"; "bar"; "baz"; "123" ] [ "foo"; "bar"; "baz"; "123" ]

              assert' [ "value"; "in"; "u"; "s"; "d" ] [ "value"; "in"; "USD" ] ]

    // let encodeNameTests =
    //     describe "encodeName" [
    //         let assert' inList expectedText =
    //             testCase $"where name is: %s{expectedText}"
    //             <| fun _ ->
    //                 Name.fromList inList
    //                 |> Name.Codec.encodeName
    //                 |> Encode.toString 0
    //                 |> Expect.equal expectedText

    //         assert' [ "delta"; "sigma"; "theta" ] """["delta","sigma","theta"]"""
    //         assert' [ "sigma"; "gamma"; "rho" ] """["sigma","gamma","rho"]"""
    //     ]

    describe
        "NameTests"
        [ fromString
          toTitleCaseTests
          toCamelCaseTests
          toSnakeCaseTests
          toHumanWordsTests
          // encodeNameTests
          ]
