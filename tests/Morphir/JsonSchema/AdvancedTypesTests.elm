module Morphir.JsonSchema.AdvancedTypesTests exposing (..)

import Decimal as D
import Expect
import Morphir.IR.Type as Type exposing (Type)
import Morphir.JsonSchema.AST exposing (Derivative(..), SchemaType(..))
import Morphir.JsonSchema.Backend exposing (mapType)
import Test exposing (describe, test)


decimalTest =
    describe "Tests for Decimal Data types"
        [ test "Unsigned decimal should produce a string type" <|
            \_ ->
                mapType (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Decimal" ] ], [ "decimal" ] ) [])
                    |> Expect.equal (Ok (String DecimalString))
        ]
