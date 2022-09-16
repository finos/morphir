module Morphir.Type.MetaTypeMappingTests exposing (..)

import Dict
import Expect
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), metaAlias, metaClosedRecord, metaRecord, variableByIndex)
import Morphir.Type.MetaTypeMapping exposing (concreteTypeToMetaType)
import Set
import Test exposing (Test, describe, test)


concreteTypeToMetaTypeTests : Test
concreteTypeToMetaTypeTests =
    describe "concreteTypeToMetaType"
        [ test "alias lookup"
            (\_ ->
                concreteTypeToMetaType (variableByIndex 0) testIR Dict.empty (Type.Reference () (fqn "Test" "Test" "FooBarBazRecord") [])
                    |> Expect.equal
                        (metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                            []
                            (metaClosedRecord ( [], 0, 1 )
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


testIR : IR
testIR =
    Dict.fromList
        [ ( [ [ "morphir" ], [ "s", "d", "k" ] ]
          , SDK.packageSpec
          )
        , ( [ [ "test" ] ]
          , { modules =
                Dict.fromList
                    [ ( [ [ "test" ] ]
                      , { types =
                            Dict.fromList
                                [ ( [ "custom" ]
                                  , Documented ""
                                        (Type.CustomTypeSpecification []
                                            (Dict.fromList
                                                [ ( [ "custom", "zero" ], [] )
                                                ]
                                            )
                                        )
                                  )
                                , ( [ "foo", "bar", "baz", "record" ]
                                  , Documented ""
                                        (Type.TypeAliasSpecification []
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
                        }
                      )
                    ]
            }
          )
        ]
        |> IR.fromPackageSpecifications
