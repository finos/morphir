module Morphir.JsonSchema.RecordTypesTests exposing (..)

import Dict
import Expect
import Morphir.IR.Type as Type
import Morphir.JsonSchema.AST exposing (Derivative(..), SchemaType(..))
import Morphir.JsonSchema.Backend exposing (mapType)
import Test exposing (describe, test)


recordTests =
    describe "Tests Record Types"
        [ test "Test record with single field" <|
            \_ ->
                mapType (Type.Record () [ Type.Field [ "firstname" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "String" ] ], [ "string" ] ) []) ])
                    |> Expect.equal (Ok (Object ([ ( "firstname", String BasicString ) ] |> Dict.fromList)))
        , test "Test for record with two fields" <|
            \_ ->
                mapType
                    (Type.Record ()
                        [ Type.Field [ "firstname" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "String" ] ], [ "string" ] ) [])
                        , Type.Field [ "age" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "int" ] ) [])
                        ]
                    )
                    |> Expect.equal (Ok (Object ([ ( "firstname", String BasicString ), ( "age", Integer ) ] |> Dict.fromList)))
        ]
