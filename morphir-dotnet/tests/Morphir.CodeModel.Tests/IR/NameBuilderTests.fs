module Morphir.IR.NameBuilderTests

open Expecto
open Morphir.IR
open Morphir.SDK.Testing

[<Tests>]
let tests =
    describe
        "NameBuilder"
        [ test "should support building a name from a single string" {
              let actual = name { "foo" }
              let expected = Name.fromString "foo"
              Expect.equal actual expected
          }
          test "should support building a name by providing a sequence of strings" {
              let actual =
                  name {
                      "foo"
                      "bar"
                      "baz"
                  }

              let expected = Name.fromString "fooBarBaz"
              Expect.equal actual expected
          }
          test "should support building a name by yielding a sequence of strings" {
              let actual =
                  name {
                      yield "foo"
                      yield "bar"
                      yield "baz"
                  }

              let expected = Name.fromString "fooBarBaz"
              Expect.equal actual expected
          } ]
