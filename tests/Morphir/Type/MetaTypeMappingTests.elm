module Morphir.Type.MetaTypeMappingTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type
import Morphir.Type.Count as Count
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), metaAlias, metaClosedRecord)
import Morphir.Type.MetaTypeMapping exposing (concreteTypeToMetaType)
import Test exposing (Test, describe, test)


concreteTypeToMetaTypeTests : Test
concreteTypeToMetaTypeTests =
    describe "concreteTypeToMetaType"
        [ test "alias lookup"
            (\_ ->
                concreteTypeToMetaType testIR Dict.empty (Type.Reference () (fqn "Test" "Test" "FooBarBazRecord") [])
                    |> Count.apply 0
                    |> Tuple.second
                    |> Expect.equal
                        (metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                            []
                            (metaClosedRecord 0
                                (Dict.fromList
                                    [ ( [ "foo" ], MetaType.stringType )
                                    , ( [ "bar" ], MetaType.boolType )
                                    , ( [ "baz" ], MetaType.intType )
                                    ]
                                )
                            )
                        )
            )
        ]


testIR : Distribution
testIR =
    Library [ [ "test" ] ]
        (Dict.fromList
            [ ( [ [ "morphir" ], [ "s", "d", "k" ] ]
              , SDK.packageSpec
              )
            ]
        )
        { modules =
            Dict.fromList
                [ ( [ [ "test" ] ]
                  , public <|
                        { types =
                            Dict.fromList
                                [ ( [ "custom" ]
                                  , public <|
                                        Documented ""
                                            (Type.CustomTypeDefinition []
                                                (public <|
                                                    Dict.fromList
                                                        [ ( [ "custom", "zero" ], [] )
                                                        ]
                                                )
                                            )
                                  )
                                , ( [ "foo", "bar", "baz", "record" ]
                                  , public <|
                                        Documented ""
                                            (Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ Type.Field [ "foo" ] (stringType ())
                                                    , Type.Field [ "bar" ] (boolType ())
                                                    , Type.Field [ "baz" ] (intType ())
                                                    ]
                                                )
                                            )
                                  )
                                ]
                        , values =
                            Dict.empty
                        , doc = Nothing
                        }
                  )
                ]
        }
