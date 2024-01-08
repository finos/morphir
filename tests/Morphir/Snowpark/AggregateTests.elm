module Morphir.Snowpark.AggregateTests exposing (..)

import Dict
import Expect
import Morphir.IR.FQName as FQName
import Morphir.IR.Path as Path
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( aggregateFunction
        , aggregateTypeInstance
        , employeeInfo
        , floatTypeInstance
        , groupByFunction
        , key0Type
        , mFieldFunction
        , mFuncTypeOf
        , mIdOf
        , mLambdaOf
        , mListTypeOf
        , sCall
        , sLit
        , sVar
        , stringTypeInstance
        , testDistributionName
        , testDistributionPackage
        )
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Morphir.Snowpark.ReferenceUtils exposing (curryCall)
import Set
import Test exposing (Test, describe, test)


groupBySection : Value.TypedValue
groupBySection =
    curryCall
        ( groupByFunction stringTypeInstance employeeInfo
        , [ mFieldFunction stringTypeInstance [ "employee" ], mIdOf [ "employees" ] (mListTypeOf employeeInfo) ]
        )


aggregateSection : Value.TypedValue
aggregateSection =
    curryCall
        ( aggregateFunction stringTypeInstance employeeInfo floatTypeInstance
        , [ aggregateLambda, groupBySection ]
        )


aggregateLambda : Value.TypedValue
aggregateLambda =
    mLambdaOf ( [ "key" ], stringTypeInstance ) secondParamLambda


secondParamLambda : Value.TypedValue
secondParamLambda =
    let
        balanceType =
            mFuncTypeOf
                (aggregateTypeInstance [ "aggregation" ] [ employeeInfo, stringTypeInstance ])
                floatTypeInstance

        applyMinimum =
            Value.Apply
                (aggregateTypeInstance
                    [ "aggregation" ]
                    [ employeeInfo
                    , key0Type
                    ]
                )
                (Value.Reference
                    (mFuncTypeOf
                        (mFuncTypeOf employeeInfo floatTypeInstance)
                        (aggregateTypeInstance [ "aggregation" ] [ employeeInfo, key0Type ])
                    )
                    ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], [ "minimum", "of" ] )
                )
                (mFieldFunction (mFuncTypeOf employeeInfo floatTypeInstance) [ "min", "salary" ])

        apply1LambdaBody =
            Value.Apply
                (mFuncTypeOf floatTypeInstance employeeInfo)
                (Value.Constructor
                    (mFuncTypeOf stringTypeInstance (mFuncTypeOf floatTypeInstance employeeInfo))
                    ( [ [ "deparments" ] ], [ [ "empleados" ] ], [ "employee", "info" ] )
                )
                (mIdOf [ "key" ] stringTypeInstance)

        apply2LambdaBody =
            Value.Apply
                floatTypeInstance
                (mIdOf [ "balances" ] balanceType)
                applyMinimum

        lambdaBody =
            Value.Apply
                employeeInfo
                apply1LambdaBody
                apply2LambdaBody
    in
    mLambdaOf ( [ "balances" ], balanceType ) lambdaBody


expectedResult : Scala.Value
expectedResult =
    let
        groupByObj =
            sCall ( sVar "employees", "groupBy" ) [ sLit "employee" ]

        aggregateObj =
            sCall
                ( groupByObj, "agg" )
                [ sCall ( applySnowparkFunc "min" [ applySnowparkFunc "col" [ sLit "minSalary" ] ], "alias" ) [ sLit "minSalary" ] ]
    in
    sCall
        ( aggregateObj, "select" )
        [ applySnowparkFunc "col" [ sLit "employee" ]
        , applySnowparkFunc "col" [ sLit "minSalary" ]
        ]


aggregateTests : Test
aggregateTests =
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

        assertAggregateTest =
            test "Simple aggregate" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue aggregateSection ctx
                    in
                    Expect.equal mapped expectedResult
    in
    describe "Aggregate test"
        [ assertAggregateTest
        ]
