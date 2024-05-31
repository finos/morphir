module Morphir.IR.Type.DataCodecTests exposing (decodeDataTest)

import Dict
import Expect exposing (Expectation)
import Json.Decode as Decode
import Morphir.IR.AccessControlled as Access
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Char exposing (charType)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.LocalDate exposing (localDateType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec exposing (decodeData, encodeData)
import Morphir.IR.ValueFuzzer as ValueFuzzer
import Test exposing (Test, describe, fuzz)


packageDefinition : Package.Definition () (Type ())
packageDefinition =
    { modules =
        Dict.fromList
            [ ( [ [ "mod" ] ]
              , { access = Access.Private
                , value =
                    { types =
                        Dict.fromList
                            [ ( [ "alias", "1" ]
                              , { access = Access.Public
                                , value =
                                    { doc = ""
                                    , value =
                                        Type.TypeAliasDefinition [ [ "a" ] ]
                                            (Type.Variable () [ "a" ])
                                    }
                                }
                              )
                            , ( [ "custom" ]
                              , { access = Access.Public
                                , value =
                                    { doc = ""
                                    , value =
                                        Type.CustomTypeDefinition [ [ "a" ] ]
                                            { access = Access.Public
                                            , value =
                                                Dict.fromList
                                                    [ ( [ "custom", "zero" ], [] )
                                                    , ( [ "custom", "one" ], [ ( [ "one" ], intType () ) ] )
                                                    , ( [ "custom", "two" ], [ ( [ "one" ], Type.Variable () [ "a" ] ), ( [ "two" ], boolType () ) ] )
                                                    ]
                                            }
                                    }
                                }
                              )
                            ]
                    , values = Dict.empty
                    , doc = Nothing
                    }
                }
              )
            ]
    }


distribution : Distribution
distribution =
    Library (Path.fromString "My") Dict.empty packageDefinition
        |> Distribution.insertDependency SDK.packageName SDK.packageSpec


decodeDataTest : Test
decodeDataTest =
    describe "JsonDecoderTest"
        [ encodeDecodeTest (boolType ())
        , encodeDecodeTest (intType ())
        , encodeDecodeTest (floatType ())
        , encodeDecodeTest (charType ())
        , encodeDecodeTest (stringType ())
        , encodeDecodeTest (listType () (stringType ()))
        , encodeDecodeTest (listType () (intType ()))
        , encodeDecodeTest (listType () (floatType ()))
        , encodeDecodeTest (maybeType () (floatType ()))
        , encodeDecodeTest (Type.Record () [])
        , encodeDecodeTest (Type.Record () [ Type.Field [ "foo" ] (intType ()) ])
        , encodeDecodeTest (Type.Record () [ Type.Field [ "foo" ] (intType ()), Type.Field [ "bar" ] (boolType ()) ])
        , encodeDecodeTest (Type.Tuple () [])
        , encodeDecodeTest (Type.Tuple () [ intType () ])
        , encodeDecodeTest (Type.Tuple () [ intType (), boolType () ])
        , encodeDecodeTest (Type.Reference () ( [ [ "my" ] ], [ [ "mod" ] ], [ "alias", "1" ] ) [ intType () ])
        , encodeDecodeTest (Type.Reference () ( [ [ "my" ] ], [ [ "mod" ] ], [ "custom" ] ) [ charType () ])
        , encodeDecodeTest (Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "local", "date" ] ) [ localDateType () ])
        ]


encodeDecodeTest : Type () -> Test
encodeDecodeTest tpe =
    fuzz (ValueFuzzer.fromType distribution tpe)
        (Debug.toString tpe)
        (\value ->
            Result.map2
                (\encode decoder ->
                    encode value
                        |> Result.andThen (Decode.decodeValue decoder >> Result.mapError Decode.errorToString)
                        |> Expect.equal (Ok value)
                )
                (encodeData distribution tpe)
                (decodeData distribution tpe)
                |> Result.withDefault (Expect.fail ("Could not create codec for " ++ Debug.toString tpe))
        )
