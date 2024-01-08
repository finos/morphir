module Morphir.Snowpark.MapValueJoinTests exposing (..)

import Dict exposing (Dict(..))
import Expect
import Morphir.IR.FQName as FQName
import Morphir.IR.Path as Path
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( boolTypeInstance
        , equalFunction
        , innerJoinFunction
        , intTypeInstance
        , leftJoinFunction
        , listMapFunction
        , mField
        , mFuncTypeOf
        , mIdOf
        , mLambdaOf
        , mListTypeOf
        , mMaybeTypeOf
        , mRecordOf
        , mRecordTypeOf
        , mTuple2TypeOf
        , maybeMapFunction
        , sCall
        , sLit
        , sVar
        , testDistributionName
        , testDistributionPackage
        , typeA
        , typeB
        , typeC
        )
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Morphir.Snowpark.ReferenceUtils exposing (curryCall)
import Set
import Test exposing (Test, describe, test)


expectedInnerJoin : Scala.Value
expectedInnerJoin =
    sCall ( expectedJoinCall "inner", "select" ) expectedProjection


expectedLeftJoin : Scala.Value
expectedLeftJoin =
    sCall ( expectedJoinCall "left", "select" ) expectedProjection


expectedMultipleJoin : Scala.Value
expectedMultipleJoin =
    sCall ( expectedInnerMultipleJoin, "select" ) expectedMultipleProjection


expectedInnerMultipleJoin : Scala.Value
expectedInnerMultipleJoin =
    sCall ( expectedInnerInnerMultipleJoin, "join" ) expectedInnerJoinValue


expectedInnerInnerMultipleJoin : Scala.Value
expectedInnerInnerMultipleJoin =
    sCall ( sVar "dataSetA", "join" ) expectedInnerInnerJoinValue


expectedInnerJoinValue : List Scala.Value
expectedInnerJoinValue =
    [ sVar "dataSetC"
    , Scala.BinOp (Scala.Ref [ "typeAColumns" ] "id") "===" (Scala.Ref [ "typeCColumns" ] "id")
    , sLit "inner"
    ]


expectedInnerInnerJoinValue : List Scala.Value
expectedInnerInnerJoinValue =
    [ sVar "dataSetB"
    , Scala.BinOp (Scala.Ref [ "typeAColumns" ] "id") "===" (Scala.Ref [ "typeBColumns" ] "id")
    , sLit "inner"
    ]


expectedProjection : List Scala.Value
expectedProjection =
    [ sCall ( Scala.Ref [ "typeAColumns" ] "id", "alias" ) [ sLit "idA" ]
    , sCall ( Scala.Ref [ "typeBColumns" ] "id", "alias" ) [ sLit "idB" ]
    ]


expectedMultipleProjection : List Scala.Value
expectedMultipleProjection =
    [ sCall ( Scala.Ref [ "typeAColumns" ] "id", "alias" ) [ sLit "idA" ]
    , sCall ( Scala.Ref [ "typeBColumns" ] "id", "alias" ) [ sLit "idB" ]
    , sCall ( Scala.Ref [ "typeCColumns" ] "id", "alias" ) [ sLit "idC" ]
    ]


expectedJoinCall : String -> Scala.Value
expectedJoinCall joinType =
    sCall
        ( sVar "dataSetA", "join" )
        [ sVar "dataSetB"
        , Scala.BinOp (Scala.Ref [ "typeAColumns" ] "id") "===" (Scala.Ref [ "typeBColumns" ] "id")
        , sLit joinType
        ]


originMultipleInnerJoin : ValueIR.TypedValue
originMultipleInnerJoin =
    let
        tupleType =
            mTuple2TypeOf typeA typeB
    in
    curryCall
        ( innerJoinFunction typeC tupleType
        , [ mIdOf [ "dataSetC" ] (mListTypeOf typeC)
          , ValueIR.Lambda
                (mFuncTypeOf tupleType (mFuncTypeOf typeC boolTypeInstance))
                (ValueIR.TuplePattern
                    tupleType
                    [ ValueIR.AsPattern typeA (ValueIR.WildcardPattern typeA) [ "x" ]
                    , ValueIR.AsPattern typeB (ValueIR.WildcardPattern typeB) [ "y" ]
                    ]
                )
                (mLambdaOf
                    ( [ "z" ], typeC )
                    (curryCall
                        ( equalFunction intTypeInstance
                        , [ mField intTypeInstance (mIdOf [ "x" ] typeA) "id"
                          , mField intTypeInstance (mIdOf [ "z" ] typeC) "id"
                          ]
                        )
                    )
                )
          , originInnerJoin
          ]
        )


originInnerJoin : ValueIR.TypedValue
originInnerJoin =
    curryCall
        ( innerJoinFunction typeA typeB
        , [ mIdOf [ "dataSetB" ] (mListTypeOf typeB)
          , mLambdaOf
                ( [ "a" ], typeA )
                (mLambdaOf
                    ( [ "b" ], typeB )
                    (curryCall
                        ( equalFunction intTypeInstance
                        , [ mField intTypeInstance (mIdOf [ "a" ] typeA) "id"
                          , mField intTypeInstance (mIdOf [ "b" ] typeB) "id"
                          ]
                        )
                    )
                )
          , mIdOf [ "dataSetA" ] (mListTypeOf typeA)
          ]
        )


originLeftJoin : ValueIR.TypedValue
originLeftJoin =
    curryCall
        ( leftJoinFunction typeA typeB
        , [ mIdOf [ "dataSetB" ] (mListTypeOf typeB)
          , mLambdaOf
                ( [ "a" ], typeA )
                (mLambdaOf
                    ( [ "b" ], typeB )
                    (curryCall
                        ( equalFunction intTypeInstance
                        , [ mField intTypeInstance (mIdOf [ "a" ] typeA) "id"
                          , mField intTypeInstance (mIdOf [ "b" ] typeB) "id"
                          ]
                        )
                    )
                )
          , mIdOf [ "dataSetA" ] (mListTypeOf typeA)
          ]
        )


projectionInnerJoin : ValueIR.Value () (TypeIR.Type ())
projectionInnerJoin =
    let
        tupleType =
            mTuple2TypeOf typeA typeB
    in
    curryCall
        ( listMapFunction tupleType recordProjection
        , [ ValueIR.Lambda
                (mFuncTypeOf tupleType recordProjection)
                (ValueIR.TuplePattern
                    tupleType
                    [ ValueIR.AsPattern typeA (ValueIR.WildcardPattern typeA) [ "x" ]
                    , ValueIR.AsPattern typeB (ValueIR.WildcardPattern typeB) [ "y" ]
                    ]
                )
                (mRecordOf
                    [ ( "idA", mField intTypeInstance (mIdOf [ "x" ] typeA) "id" )
                    , ( "idB", mField intTypeInstance (mIdOf [ "y" ] typeB) "id" )
                    ]
                )
          , originInnerJoin
          ]
        )


projectionLeftJoin : ValueIR.Value () (TypeIR.Type ())
projectionLeftJoin =
    let
        tupleType =
            mTuple2TypeOf typeA (mMaybeTypeOf typeB)
    in
    curryCall
        ( listMapFunction tupleType recordMaybeProjection
        , [ ValueIR.Lambda
                (mFuncTypeOf tupleType recordMaybeProjection)
                (ValueIR.TuplePattern
                    tupleType
                    [ ValueIR.AsPattern typeA (ValueIR.WildcardPattern typeA) [ "x" ]
                    , ValueIR.AsPattern typeB (ValueIR.WildcardPattern (mMaybeTypeOf intTypeInstance)) [ "y" ]
                    ]
                )
                (mRecordOf
                    [ ( "idA", mField intTypeInstance (mIdOf [ "x" ] typeA) "id" )
                    , ( "idB"
                      , curryCall
                            ( maybeMapFunction typeB intTypeInstance
                            , [ mLambdaOf ( [ "z" ], typeB ) (mField typeB (mIdOf [ "z" ] typeB) "id")
                              , mIdOf [ "y" ] (mMaybeTypeOf typeB)
                              ]
                            )
                      )
                    ]
                )
          , originLeftJoin
          ]
        )


projectionMultipleJoin : ValueIR.Value () (TypeIR.Type ())
projectionMultipleJoin =
    let
        tupleType =
            mTuple2TypeOf typeA typeB

        tupleTupleType =
            mTuple2TypeOf tupleType typeC
    in
    curryCall
        ( listMapFunction tupleTupleType recordMultipleProjection
        , [ ValueIR.Lambda
                (mFuncTypeOf tupleTupleType recordMultipleProjection)
                (ValueIR.TuplePattern
                    tupleTupleType
                    [ ValueIR.TuplePattern
                        tupleType
                        [ ValueIR.AsPattern typeA (ValueIR.WildcardPattern typeA) [ "a" ]
                        , ValueIR.AsPattern typeB (ValueIR.WildcardPattern typeB) [ "b" ]
                        ]
                    , ValueIR.AsPattern typeC (ValueIR.WildcardPattern typeC) [ "c" ]
                    ]
                )
                (mRecordOf
                    [ ( "idA", mField intTypeInstance (mIdOf [ "a" ] typeA) "id" )
                    , ( "idB", mField intTypeInstance (mIdOf [ "b" ] typeB) "id" )
                    , ( "idC", mField intTypeInstance (mIdOf [ "c" ] typeC) "id" )
                    ]
                )
          , originMultipleInnerJoin
          ]
        )


recordProjection : TypeIR.Type ()
recordProjection =
    mRecordTypeOf
        [ ( "idA", intTypeInstance )
        , ( "idB", intTypeInstance )
        ]


recordMaybeProjection : TypeIR.Type ()
recordMaybeProjection =
    mRecordTypeOf
        [ ( "idA", intTypeInstance )
        , ( "idB", mMaybeTypeOf intTypeInstance )
        ]


recordMultipleProjection : TypeIR.Type ()
recordMultipleProjection =
    mRecordTypeOf
        [ ( "idA", intTypeInstance )
        , ( "idB", intTypeInstance )
        , ( "idC", intTypeInstance )
        ]


mapValueJoinTest : Test
mapValueJoinTest =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        ( calculatedContext, _, _ ) =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        columnsObjects =
            Dict.fromList
                [ ( FQName.fromString "UTest:MyMod:TypeA" ":", "typeAColumns" )
                , ( FQName.fromString "UTest:MyMod:TypeB" ":", "typeBColumns" )
                , ( FQName.fromString "UTest:MyMod:TypeC" ":", "typeCColumns" )
                ]

        ctx =
            { emptyValueMappingContext
                | typesContextInfo = calculatedContext
                , packagePath = Path.fromString "UTest"
                , dataFrameColumnsObjects = columnsObjects
            }

        assertInnerJoin =
            test "simple inner Join" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue projectionInnerJoin ctx
                    in
                    Expect.equal mapped expectedInnerJoin

        assertLeftJoin =
            test "simple left Join" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue projectionLeftJoin ctx
                    in
                    Expect.equal mapped expectedLeftJoin

        assertMultipleJoin =
            test "Multiple inner Join" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue projectionMultipleJoin ctx
                    in
                    Expect.equal mapped expectedMultipleJoin
    in
    describe "inner Join"
        [ assertInnerJoin
        , assertLeftJoin
        , assertMultipleJoin
        ]
