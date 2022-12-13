module Morphir.JsonSchema.RecordTypesTests exposing (..)

import Dict
import Expect
import Morphir.IR.Type as Type
import Morphir.JsonSchema.AST exposing (SchemaType(..), StringConstraints)
import Morphir.JsonSchema.Backend exposing (mapType)
import Test exposing (describe, test)


mapTypeTests =
    describe "Tests Record Types"
        [ test "Test record with single field" <|
            \_ ->
                mapType ( [], [] ) (Type.Record () [ Type.Field [ "firstname" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "String" ] ], [ "string" ] ) []) ])
                    |> Expect.equal (Ok (Object ([ ( "firstname", String (StringConstraints Nothing) ) ] |> Dict.fromList) [ "firstname" ]))
        , test "Test for record with two fields" <|
            \_ ->
                mapType ( [], [] )
                    (Type.Record ()
                        [ Type.Field [ "firstname" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "String" ] ], [ "string" ] ) [])
                        , Type.Field [ "age" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "Basics" ] ], [ "int" ] ) [])
                        ]
                    )
                    |> Expect.equal (Ok (Object ([ ( "firstname", String (StringConstraints Nothing) ), ( "age", Integer ) ] |> Dict.fromList) [ "firstname", "age" ]))
        , test "Test for record with a custom field" <|
            \_ ->
                mapType ( [], [] )
                    (Type.Record ()
                        [ Type.Field [ "firstname" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "String" ] ], [ "string" ] ) [])
                        , Type.Field [ "lastname" ] (Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "String" ] ], [ "string" ] ) [])
                        , Type.Field [ "address" ] (Type.Reference () ( [ [ "TestModel" ] ], [ [ "RecordTypes" ] ], [ "address" ] ) [])
                        ]
                    )
                    |> Expect.equal
                        (Ok
                            (Object
                                ([ ( "firstname", String (StringConstraints Nothing) )
                                 , ( "lastname", String (StringConstraints Nothing) )
                                 , ( "address", Ref "#/$defs/RecordTypes.Address" )
                                 ]
                                    |> Dict.fromList
                                )
                                [ "firstname", "lastname", "address" ]
                            )
                        )
        ]
