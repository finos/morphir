module Morphir.IR.PathBuilderTests

open Morphir.SDK.Testing

[<Tests>]
let tests =
    describe
        "PathBuilder"
        [ test "should support building a path from a single string" {
              let actual = path { "name.Address.City" }
              let expected = Path.fromString "name.Address.City"
              actual |> Expect.equal expected
          }
          test "should allow creation from a single name" {
              let actual = path { name "Path" }
              let expected = Path.fromList [ Name.fromString "Path" ]
              actual |> Expect.equal expected
          }

          test "should allow creation from a sequence of names" {
              let actual =
                  path {
                      name "name"
                      name "Address"
                      name "City"
                  }

              let expected = Path.fromString "name.address.city"

              actual |> Expect.equal expected
          }

          test "should allow creation from names created from lists" {
              let actual =
                  path {
                      names [ "Target"; "User"; "Address" ]
                      names [ "PhoneNumber"; "AreaCode" ]
                  }

              let expected = Path.fromString "Target.User.Address/PhoneNumber.AreaCode"

              actual |> Expect.equal expected
          } ]
