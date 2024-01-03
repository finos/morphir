module Morphir.Snowpark.AggregateTests exposing (..)

import Set
import Expect
import Dict
import Test exposing (Test, describe, test)
import Morphir.Scala.AST as Scala
import Morphir.IR.Path as Path
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.CommonTestUtils exposing (
                                                    testDistributionPackage
                                                    , testDistributionName
                                                    , stringTypeInstance
                                                    , mListTypeOf
                                                    , groupByFunction
                                                    , employeeInfo
                                                    , mFieldFunction
                                                    , mFuncTypeOf
                                                    , aggregateFunction
                                                    , aggregateTypeInstance
                                                    , mIdOf
                                                    , floatTypeInstance
                                                    , mLambdaOf)
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.IR.Value as Value
import Morphir.Snowpark.ReferenceUtils exposing (curryCall)
import Morphir.Snowpark.CommonTestUtils exposing (key0Type)
import Morphir.Snowpark.CommonTestUtils exposing (sCall)
import Morphir.Snowpark.CommonTestUtils exposing (sLit)
import Morphir.Snowpark.CommonTestUtils exposing (sVar)
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)


groupBySection : Value.TypedValue
groupBySection =
    curryCall (
        (groupByFunction stringTypeInstance  employeeInfo)
        , [mFieldFunction stringTypeInstance ["employee"], mIdOf ["employees"] (mListTypeOf employeeInfo) ] )

aggregateSection : Value.TypedValue
aggregateSection =
    curryCall (
        (aggregateFunction stringTypeInstance employeeInfo floatTypeInstance)
        , [aggregateLambda, groupBySection]
    )

aggregateLambda : Value.TypedValue
aggregateLambda =
    mLambdaOf (["key"], stringTypeInstance) secondParamLambda

secondParamLambda : Value.TypedValue
secondParamLambda =
    let
        balanceType = mFuncTypeOf 
                            (aggregateTypeInstance ["aggregation"] [employeeInfo, stringTypeInstance])
                            floatTypeInstance

        applyMinimum =
            Value.Apply
                (aggregateTypeInstance 
                    ["aggregation"] 
                    [ employeeInfo
                    , key0Type 
                    ])
                (Value.Reference
                    (mFuncTypeOf 
                        (mFuncTypeOf employeeInfo floatTypeInstance) 
                        (aggregateTypeInstance ["aggregation"] [ employeeInfo, key0Type ] ) )
                    ([["morphir"],["s","d","k"]],[["aggregate"]],["minimum","of"]))
                (mFieldFunction (mFuncTypeOf employeeInfo floatTypeInstance) ["min", "salary"])

        apply1LambdaBody =
            Value.Apply
                (mFuncTypeOf floatTypeInstance employeeInfo)
                (Value.Constructor 
                    (mFuncTypeOf stringTypeInstance (mFuncTypeOf floatTypeInstance employeeInfo))
                    ([["deparments"]],[["empleados"]],["employee","info"]))
                (mIdOf ["key"] stringTypeInstance)
        apply2LambdaBody =
            Value.Apply
                floatTypeInstance
                (mIdOf ["balances"] balanceType)
                applyMinimum

        lambdaBody =
            Value.Apply 
                employeeInfo 
                apply1LambdaBody
                apply2LambdaBody
    in
    mLambdaOf (["balances"], balanceType) lambdaBody

expectedResult : Scala.Value
expectedResult =
    let
        groupByObj =
            sCall (sVar "employees", "groupBy" ) [sLit "employee"]
        aggregateObj = 
            sCall 
                (groupByObj, "agg")
                [ sCall (applySnowparkFunc "min" [applySnowparkFunc "col" [sLit "minSalary"]], "alias")[sLit "minSalary"]]
    in
    sCall
        (aggregateObj, "select") 
        [ applySnowparkFunc "col" [sLit "employee"]
        , applySnowparkFunc "col" [sLit "minSalary"]
        ]

aggregateTests : Test
aggregateTests =
    let
        customizationOptions = {functionsToInline = Set.empty, functionsToCache = Set.empty}
        (calculatedContext, _ , _) = MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions
        columnsObjects = Dict.fromList  [ (FQName.fromString "UTest:MyMod:TypeA" ":", "typeAColumns")
                                        , (FQName.fromString "UTest:MyMod:TypeB" ":", "typeBColumns")
                                        , (FQName.fromString "UTest:MyMod:TypeC" ":", "typeCColumns")
                                        ]
        ctx = { emptyValueMappingContext | typesContextInfo = calculatedContext
                                         , packagePath = Path.fromString "UTest"
                                         , dataFrameColumnsObjects = columnsObjects}
        assertAggregateTest =
            test ("Simple aggregate") <|
                \_ ->
                    let
                        (mapped, _ ) = mapValue aggregateSection ctx
                    in
                    Expect.equal mapped expectedResult
    in
    describe "Aggregate test"
    [
        assertAggregateTest
    ]


