module Morphir.TypeScript.BackendTests exposing (mapTypeDefinitionTests)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type
import Morphir.TypeScript.AST as TS
import Morphir.TypeScript.Backend exposing (mapTypeDefinition)
import Test exposing (Test, describe, test)


mapTypeDefinitionTests : Test
mapTypeDefinitionTests =
    describe "mapTypeDefinition"
        [ test "custom type mapping"
            (\_ ->
                mapTypeDefinition [ "my", "foo" ]
                    (Type.CustomTypeDefinition []
                        (public
                            (Dict.fromList
                                [ ( [ "bar" ], [] )
                                , ( [ "baz" ]
                                  , [ ( [ "my", "field" ], stringType () ) ]
                                  )
                                ]
                            )
                        )
                    )
                    |> Expect.equal
                        [ TS.Interface "Bar"
                            []
                        , TS.Interface "Baz"
                            [ ( "myField", TS.String )
                            ]
                        , TS.TypeAlias "MyFoo"
                            (TS.Union
                                [ TS.TypeRef "Bar"
                                , TS.TypeRef "Baz"
                                ]
                            )
                        ]
            )
        ]
