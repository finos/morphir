module Morphir.IR.Tests.QNameTests

open System
open Bogus
open FsCheck
open Morphir.SDK.Testing
open Morphir.SDK
open Morphir.IR
open Morphir.IR.QName
//open Thoth.Json.Net

module TestData =
    do Randomizer.Seed <- new Random(8675309)
    let faker = Faker "en"


    let names =
        [ for i = 0 to 10 do
              faker.Company.CompanyName() |> Name.fromString ]

    let paths =
        [ for i = 0 to 10 do
              [ faker.Internet.DomainSuffix() |> Name.fromString ]
              |> List.append names
              |> Path.fromList ]

    let pickAName () = faker.PickRandom(names)
    let pickAPath () = faker.PickRandom(paths)

    let pickAQName () = QName(pickAPath (), pickAName ())

[<Tests>]
let tests =
    describe
        "QName Tests"
        [ test "When toTuple is called then be converted to a tuple" {
              let path = Path.fromString "Morphir.IR.QName"
              let localName = Name.fromString "toTuple"

              let actual = qName path localName |> toTuple

              Expect.equal actual (mkPath [ [ "morphir" ]; [ "i"; "r" ]; [ "q"; "name" ] ], mkName [ "to"; "tuple" ])
          }
          describe
              "When getting a property using: "
              (testParam
                  (TestData.pickAQName ())
                  [ "getModulePath",
                    fun (QName(moduleName, _) as qname) () -> Expect.equal (QName.getModulePath qname) moduleName
                    "getLocalName",
                    fun (QName(_, localName) as qname) () -> Expect.equal (QName.getLocalName qname) localName ]
               |> List.ofSeq)
          describe
              "fromName"
              [ test "should construct QName from moduleName and localName" {
                    let moduleName = TestData.pickAPath ()
                    let localName = TestData.pickAName ()
                    let qname = qName moduleName localName
                    Expect.equal (fromName moduleName localName) qname
                } ]
          describe "fromTuple" []
          describe "fromString" []
          describe
              "toString"
              [ test "toString should return FooBar.Baz:aName" {
                    let qname =
                        QName.fromTuple (
                            Path.fromList [ Name.fromList [ "foo"; "bar" ]; Name.fromList [ "baz" ] ],
                            Name.fromList [ "a"; "name" ]
                        )

                    Expect.equal (QName.toString qname) "FooBar.Baz:aName"
                } ]
          // describe "Codec" [
          //     test "Can be encoded and decoded (via roundtrip)" {
          //         let path = Path.fromString "Morphir.IR.QName"
          //         let localName = Name.fromString "toTuple"
          //         let qname = qName path localName

          //         let encoded =
          //             qname
          //             |> Codec.encodeQName
          //             |> Encode.toString 0

          //         let decoded =
          //             encoded
          //             |> Decode.fromString Codec.decodeQName

          //         Expect.equal decoded (Ok qname)
          //     }
          // ]
          ]
