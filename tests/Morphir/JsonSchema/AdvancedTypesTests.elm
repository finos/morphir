module Morphir.JsonSchema.AdvancedTypesTests exposing (..)

import Decimal as D
import Expect
import Morphir.IR.Type as Type exposing (Type)
import Morphir.JsonSchema.AST exposing (SchemaType(..), StringConstraints)
import Morphir.JsonSchema.Backend exposing (mapType)
import Test exposing (describe, test)


mapTypeTest =
    describe "Tests for Decimal Types"
        [ test "Unsigned decimal should produce a string type" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Decimal" ] ], [ "decimal" ] ) [])
                    |> Expect.equal (Ok (String (StringConstraints Nothing)))
        , test "LocalDate should produce a string type" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "LocalDate" ] ], [ "localDate" ] ) [])
                    |> Expect.equal (Ok (String (StringConstraints (Just "date"))))
        , test "LocalTime should produce a string type" <|
            \_ ->
                mapType ( [], [] ) (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "LocalTime" ] ], [ "localTime" ] ) [])
                    |> Expect.equal (Ok (String (StringConstraints (Just "time"))))
        ]
