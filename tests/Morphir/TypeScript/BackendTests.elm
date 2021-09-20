module Morphir.TypeScript.BackendTests exposing (mapTypeDefinitionTests)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Documented exposing (Documented)
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
                    (public
                        (Documented
                             ""
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
                        )
                    )
                    |> Expect.equal
                        [ TS.TypeAlias
                            { name = "MyFoo"
                            , doc = ""
                            , privacy = TS.Public
                            , variables = []
                            , typeExpression = (TS.Union
                                [ TS.TypeRef "Bar" []
                                , TS.TypeRef "Baz" []
                                ])
                            }
                        , TS.Interface
                            { name = "Bar"
                            , privacy = TS.Public
                            , variables = []
                            , fields = [ ( "kind", TS.LiteralString "Bar" ) ]
                            }
                        , TS.Interface
                            { name = "Baz"
                            , privacy = TS.Public
                            , variables = []
                            , fields =
                                [ ( "kind", TS.LiteralString "Baz" )
                                , ( "myField", TS.String )
                                ]
                            }
                        ]
            )
        ]
