module Morphir.TypeScript.BackendTests exposing (mapTypeDefinitionTests)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type
import Morphir.TypeScript.AST as TS
import Morphir.TypeScript.Backend.MapTypes exposing (mapTypeDefinition)
import Test exposing (Test, describe, test)


localFQName : String -> FQName.FQName
localFQName local =
    (Path.fromList [], Path.fromList [], Name.fromString local)

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
                                        [ ( Name.fromString "bar", [] )
                                        , ( Name.fromString "baz"
                                          , [ ( Name.fromString "myField", stringType () ) ]
                                          )
                                        ]
                                    )
                                )
                            )
                        )
                    )
                    |> Expect.equal
                        [ TS.TypeAlias
                            { name = (Name.fromString "MyFoo")
                            , doc = ""
                            , privacy = TS.Public
                            , variables = []
                            , typeExpression = (TS.Union
                                [ TS.TypeRef (localFQName "Bar") []
                                , TS.TypeRef (localFQName "Baz") []
                                ])
                            }
                        , TS.Interface
                            { name = (Name.fromString "Bar")
                            , privacy = TS.Public
                            , variables = []
                            , fields = [ ( "kind", TS.LiteralString "Bar" ) ]
                            }
                        , TS.Interface
                            { name = (Name.fromString "Baz")
                            , privacy = TS.Public
                            , variables = []
                            , fields =
                                [ ( "kind", TS.LiteralString "Baz" )
                                , ( "myField", TS.String )
                                ]
                            }
                        ]
            )
        , test "type alias expressed as custom type"
            (\_ ->
                mapTypeDefinition [ "same", "name" ]
                    (public
                        (Documented
                            ""
                            (Type.CustomTypeDefinition []
                                (public
                                    (Dict.fromList
                                        [ ( Name.fromString "sameName", [] ) ]
                                    )
                                )
                            )
                        )
                    )
                    |> Expect.equal
                        {- There should be no TS.Union here, as the name would conflict with the TS.Interface -}
                        [ TS.Interface
                            { name = Name.fromString "sameName"
                            , privacy = TS.Public
                            , variables = []
                            , fields = [ ( "kind", TS.LiteralString "SameName" ) ]
                            }
                        ]
             )
        ]
