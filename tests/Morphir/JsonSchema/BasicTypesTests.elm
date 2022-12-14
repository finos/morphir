module Morphir.JsonSchema.BasicTypesTests exposing (..)

import Expect
import Morphir.IR.Type as Type
import Morphir.JsonSchema.AST exposing (SchemaType(..))
import Morphir.JsonSchema.Backend exposing (mapType)
import Test exposing (describe, test)


floatTests =
    describe "Tests for float types"
        [ test "Positive float test" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "float" ] ) [])
                    |> Expect.equal (Ok Number)
        , test "Negative float test" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "bool" ] ) [])
                    |> Expect.notEqual (Ok Number)
        ]


booleanTests =
    describe "Tests for boolean types"
        [ test "Positive boolean test" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "bool" ] ) [])
                    |> Expect.equal (Ok Boolean)
        , test "Negative boolean test" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "bool" ] ) [])
                    |> Expect.notEqual (Ok Integer)
        ]


integerTests =
    describe "Tests for integer types"
        [ test "Positive integer test" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "int" ] ) [])
                    |> Expect.equal (Ok Integer)
        , test "Negative integer test" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "int" ] ) [])
                    |> Expect.notEqual (Ok Boolean)
        ]
