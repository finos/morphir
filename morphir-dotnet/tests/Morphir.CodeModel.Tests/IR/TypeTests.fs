module Morphir.IR.Tests.TypeTests

open Morphir.SDK.Testing
open Morphir.IR

open Morphir.IR.SDK
open Morphir.IR.Type

[<Tests>]
let tests =
    let toStringTests =
        describe
            "ToString"
            [
              //   describe
              //       "When Type is a Reference:"
              //       [ for (index, input, expected) in
              //             [ Basics.intType (), "Morphir.SDK.Basics.Int"
              //               Basics.floatType (), "Morphir.SDK.Basics.Float"
              //               Dict.dictType () (Char.charType ()) (String.stringType ()),
              //               "Morphir.SDK.Dict.Dict Morphir.SDK.Char.Char Morphir.SDK.String.String" ]
              //             |> List.mapi (fun index (input, expected) -> (index, input, expected)) do
              //             test $"Testcase %i{index} should pass [expected = {expected}]" {
              //                 Type.toString input |> Expect.equal expected
              //             } ]
              describe
                  "When Type is a Variable"
                  [ for (input, expected) in [ "a", "a"; "Result", "result"; "FizzBuzz", "fizzBuzz" ] do
                        test $"Given a variable of {input} then it should return {expected}" {
                            let type_ = Name.fromString input |> Type.variable ()

                            Type.toString type_ |> Expect.equal expected
                        }

                    ]
              describe
                  "When Type is a Record"
                  [ for (givenClause, input, expected) in
                        [ "an empty Record", Type.record () [], "{  }"
                          "a Record with one field",
                          Type.record () [ field (Name.fromString "foo") (Basics.intType ()) ],
                          "{ foo : Morphir.SDK.Basics.Int }"
                          "a Record with two fields",
                          Type.record
                              ()
                              [ field (Name.fromString "foo") (Basics.intType ())
                                field (Name.fromString "bar") (Basics.floatType ()) ],
                          "{ foo : Morphir.SDK.Basics.Int, bar : Morphir.SDK.Basics.Float }" ] do
                        test $"Given {givenClause} When calling ToString Then it should return {expected}" {
                            Type.toString input |> Expect.equal expected
                        } ]
              describe
                  "When Type is an ExtensibleRecord"
                  [ for (givenClause, input, expected) in
                        [ "an empty ExtensibleRecord", Type.extensibleRecord () (Name.fromString "a") [], "{ a |  }"
                          "an ExtensibleRecord with one field",
                          Type.extensibleRecord
                              ()
                              (Name.fromString "record")
                              [ field (Name.fromString "foo") (Basics.intType ()) ],
                          "{ record | foo : Morphir.SDK.Basics.Int }"
                          "an ExtensibleRecord with two fields",
                          Type.extensibleRecord
                              ()
                              (Name.fromString "b")
                              [ field (Name.fromString "foo") (Basics.intType ())
                                field (Name.fromString "bar") (Basics.floatType ()) ],
                          "{ b | foo : Morphir.SDK.Basics.Int, bar : Morphir.SDK.Basics.Float }" ] do
                        test $"Given {givenClause} When calling ToString Then it should return {expected}" {
                            Type.toString input |> Expect.equal expected
                        } ]
              describe
                  "When Type is a Function"
                  [ for (givenClause, input, expected) in
                        [ "a Function with no arguments",
                          Type.``function`` () (Type.unit ()) (Basics.intType ()),
                          "() -> Morphir.SDK.Basics.Int"
                          "a Function with one argument",
                          Type.``function`` () (Basics.intType ()) (Basics.floatType ()),
                          "Morphir.SDK.Basics.Int -> Morphir.SDK.Basics.Float"
                          "a Function with two arguments",
                          Type.``function`` () (func () (Basics.intType ()) (Basics.intType ())) (Basics.intType ()),
                          "(Morphir.SDK.Basics.Int -> Morphir.SDK.Basics.Int) -> Morphir.SDK.Basics.Int" ] do
                        test $"Given {givenClause} When calling ToString Then it should return {expected}" {
                            Type.toString input |> Expect.equal expected
                        } ]
              describe
                  "When Type is a Unit:"
                  [ test "it should return the proper string" {
                        let type_ = Type.unit ()

                        Type.toString type_ |> Expect.equal "()"
                    } ] ]

    describe "TypeTests" [ toStringTests ]
