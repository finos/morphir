module Morphir.Snowpark.FunctionMappingsTests exposing (functionMappingsTests)

import Dict exposing (Dict(..))
import Expect
import Morphir.IR.FQName as FQName
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( addFunction
        , boolTypeInstance
        , empType
        , equalFunction
        , floatTypeInstance
        , intTypeInstance
        , listConcatFunction
        , listConcatMapFunction
        , listFilterFunction
        , listFilterMapFunction
        , listMapFunction
        , listSumFunction
        , mFuncTypeOf
        , mIdOf
        , mIntLiteralOf
        , mLambdaOf
        , mLetOf
        , mListOf
        , mListTypeOf
        , mMaybeTypeOf
        , mRecordOf
        , mRecordTypeOf
        , mStringLiteralOf
        , maybeMapFunction
        , maybeWithDefaultFunction
        , sCall
        , sDot
        , sExpCall
        , sIntLit
        , sLit
        , sSpEqual
        , sVar
        , stringTypeInstance
        , testDistributionName
        , testDistributionPackage
        )
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MapFunctionsMapping exposing (basicsFunctionName, checkForArgsToInline, stringsFunctionName)
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Morphir.Snowpark.ReferenceUtils exposing (curryCall)
import Set
import Test exposing (Test, describe, test)


functionMappingsTests : Test
functionMappingsTests =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        ( calculatedContext, _, _ ) =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        columnsObjects =
            Dict.fromList [ ( FQName.fromString "UTest:MyMod:Emp" ":", "empColumns" ) ]

        ctx =
            { emptyValueMappingContext
                | typesContextInfo = calculatedContext
                , packagePath = Path.fromString "UTest"
                , dataFrameColumnsObjects = columnsObjects
            }

        listConcatMapWithLambda =
            test "Convert List.concatMap with lambda" <|
                \_ ->
                    let
                        concatMapCall =
                            curryCall
                                ( listConcatMapFunction empType empType
                                , [ mLambdaOf ( [ "x" ], empType ) (mListOf [ mIdOf [ "x" ] empType ])
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue concatMapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( applySnowparkFunc "array_construct"
                                        [ applySnowparkFunc "array_construct"
                                            [ sDot (sVar "empColumns") "firstname"
                                            , sDot (sVar "empColumns") "lastname"
                                            ]
                                        ]
                                    , "as"
                                    )
                                    [ sLit "result" ]
                                ]

                        expectedCall =
                            sCall
                                ( sCall ( expectedSelectResult, "flatten" ) [ applySnowparkFunc "col" [ sLit "result" ] ]
                                , "select"
                                )
                                [ sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "value" ]) [ sIntLit 0 ] ], "as" )
                                    [ sLit "firstname" ]
                                , sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "value" ]) [ sIntLit 1 ] ], "as" )
                                    [ sLit "lastname" ]
                                ]
                    in
                    Expect.equal mapped expectedCall

        listConcatMapWithFunctionExpr =
            test "Convert List.concatMap with function expr" <|
                \_ ->
                    let
                        concatMapCall =
                            curryCall
                                ( listConcatMapFunction empType empType
                                , [ mIdOf [ "foo" ] (mFuncTypeOf empType (mListTypeOf empType))
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue concatMapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( sExpCall (sVar "foo") [ sVar "empColumns" ]
                                    , "as"
                                    )
                                    [ sLit "result" ]
                                ]

                        expectedCall =
                            sCall
                                ( sCall ( expectedSelectResult, "flatten" ) [ applySnowparkFunc "col" [ sLit "result" ] ]
                                , "select"
                                )
                                [ sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "value" ]) [ sIntLit 0 ] ], "as" )
                                    [ sLit "firstname" ]
                                , sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "value" ]) [ sIntLit 1 ] ], "as" )
                                    [ sLit "lastname" ]
                                ]
                    in
                    Expect.equal mapped expectedCall

        listFilterMapWithLambda =
            test "Convert List.filterMap with lambda" <|
                \_ ->
                    let
                        fooType =
                            mFuncTypeOf empType (mMaybeTypeOf empType)

                        fooRef =
                            Value.Reference fooType (FQName.fqn "UTest" "MyMod" "foo")

                        filterMapCall =
                            curryCall
                                ( listFilterMapFunction empType empType
                                , [ mLambdaOf ( [ "x" ], empType ) (curryCall ( fooRef, [ mIdOf [ "x" ] empType ] ))
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterMapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( sExpCall (Scala.Ref [ "utest", "MyMod" ] "foo") [ sVar "empColumns" ]
                                    , "as"
                                    )
                                    [ sLit "result" ]
                                ]

                        expectedFilterCall =
                            sCall ( expectedSelectResult, "filter" ) [ sDot (applySnowparkFunc "col" [ sLit "result" ]) "is_not_null" ]

                        expectedCall =
                            sCall
                                ( expectedFilterCall, "select" )
                                [ sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "result" ]) [ sIntLit 0 ] ], "as" )
                                    [ sLit "firstname" ]
                                , sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "result" ]) [ sIntLit 1 ] ], "as" )
                                    [ sLit "lastname" ]
                                ]
                    in
                    Expect.equal mapped expectedCall

        listFilterMapWithFunctionExpr =
            test "Convert List.filterMap with function expression" <|
                \_ ->
                    let
                        fooType =
                            mFuncTypeOf empType (mMaybeTypeOf empType)

                        fooRef =
                            Value.Reference fooType (FQName.fqn "UTest" "MyMod" "foo")

                        filterMapCall =
                            curryCall
                                ( listFilterMapFunction empType empType
                                , [ fooRef
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterMapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( sExpCall (Scala.Ref [ "utest", "MyMod" ] "foo") [ sVar "empColumns" ]
                                    , "as"
                                    )
                                    [ sLit "result" ]
                                ]

                        expectedFilterCall =
                            sCall ( expectedSelectResult, "filter" ) [ sDot (applySnowparkFunc "col" [ sLit "result" ]) "is_not_null" ]

                        expectedCall =
                            sCall
                                ( expectedFilterCall, "select" )
                                [ sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "result" ]) [ sIntLit 0 ] ], "as" )
                                    [ sLit "firstname" ]
                                , sCall ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "result" ]) [ sIntLit 1 ] ], "as" )
                                    [ sLit "lastname" ]
                                ]
                    in
                    Expect.equal mapped expectedCall

        listMapWithLambdaAndRecord =
            test "Convert List.map with lambda and record" <|
                \_ ->
                    let
                        resultRecord =
                            mRecordOf [ ( "a", Value.Field stringTypeInstance (Value.Variable empType [ "x" ]) [ "firstname" ] ) ]

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ mLambdaOf ( [ "x" ], empType ) resultRecord
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( Scala.Ref [ "empColumns" ] "firstname"
                                    , "as"
                                    )
                                    [ sLit "a" ]
                                ]
                    in
                    Expect.equal mapped expectedSelectResult

        listMapWithLambdaAndRecordAndBinOpInProjection =
            test "Convert List.map with lambda and record and binary operation in projection" <|
                \_ ->
                    let
                        resultRecord =
                            mRecordOf
                                [ ( "a", Value.Field stringTypeInstance (Value.Variable empType [ "x" ]) [ "firstname" ] )
                                , ( "b", curryCall ( addFunction intTypeInstance, [ mIntLiteralOf 1, mIntLiteralOf 2 ] ) )
                                ]

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ mLambdaOf ( [ "x" ], empType ) resultRecord
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( Scala.Ref [ "empColumns" ] "firstname"
                                    , "as"
                                    )
                                    [ sLit "a" ]
                                , sCall
                                    ( Scala.Tuple [ Scala.BinOp (applySnowparkFunc "lit" [ sIntLit 1 ]) "+" (applySnowparkFunc "lit" [ sIntLit 2 ]) ]
                                    , "as"
                                    )
                                    [ sLit "b" ]
                                ]
                    in
                    Expect.equal mapped expectedSelectResult

        listMapWithLambdaAndLetRecord =
            test "Convert List.map with lambda and let with record" <|
                \_ ->
                    let
                        resultLetRecord =
                            mLetOf [ "y" ]
                                (Value.Field stringTypeInstance (Value.Variable empType [ "k" ]) [ "lastname" ])
                                (mRecordOf [ ( "a", mIdOf [ "y" ] stringTypeInstance ) ])

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ mLambdaOf ( [ "k" ], empType ) resultLetRecord
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( Scala.Ref [ "empColumns" ] "lastname"
                                    , "as"
                                    )
                                    [ sLit "a" ]
                                ]
                    in
                    Expect.equal mapped expectedSelectResult

        listMapWithLambdaAndBasicType =
            test "Convert List.map with lambda and basic type" <|
                \_ ->
                    let
                        lambdaBody =
                            Value.Field stringTypeInstance (Value.Variable empType [ "k" ]) [ "lastname" ]

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ mLambdaOf ( [ "k" ], empType ) lambdaBody
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ Scala.Ref [ "empColumns" ] "lastname" ]
                    in
                    Expect.equal mapped expectedSelectResult

        listMapWithLambdaAndFieldFunction =
            test "Convert List.map with lambda and field function" <|
                \_ ->
                    let
                        lambdaBody =
                            Value.FieldFunction stringTypeInstance [ "lastname" ]

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ mLambdaOf ( [ "k" ], empType ) lambdaBody
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ applySnowparkFunc "col" [ sLit "lastname" ] ]
                    in
                    Expect.equal mapped expectedSelectResult

        listMapWithFunction =
            test "Convert List.map with function expression" <|
                \_ ->
                    let
                        recordType =
                            Type.Record ()
                                [ { name = [ "f2" ], tpe = floatTypeInstance }
                                , { name = [ "f1" ], tpe = stringTypeInstance }
                                ]

                        functionExpr =
                            Value.Reference (mFuncTypeOf empType recordType) (FQName.fqn "UTest" "MyMod" "myProjection")

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ functionExpr
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall ctx

                        externalSelect =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( sExpCall (Scala.Ref [ "utest", "MyMod" ] "myProjection") [ sVar "empColumns" ]
                                    , "as"
                                    )
                                    [ sLit "result" ]
                                ]

                        unpackSelect =
                            sCall ( externalSelect, "select" )
                                [ sCall
                                    ( applySnowparkFunc "as_double" [ sExpCall (applySnowparkFunc "col" [ sLit "result" ]) [ sIntLit 0 ] ]
                                    , "as"
                                    )
                                    [ sLit "f2" ]
                                , sCall
                                    ( applySnowparkFunc "as_char" [ sExpCall (applySnowparkFunc "col" [ sLit "result" ]) [ sIntLit 1 ] ]
                                    , "as"
                                    )
                                    [ sLit "f1" ]
                                ]
                    in
                    Expect.equal mapped unpackSelect

        listMapWithLambdaAndRecordUpdate =
            test "Convert List.map with record update expression" <|
                \_ ->
                    let
                        resultUpdateRecord =
                            Value.UpdateRecord
                                empType
                                (mIdOf [ "k" ] empType)
                                (Dict.fromList [ ( [ "lastname" ], mIdOf [ "tmpStr" ] stringTypeInstance ) ])

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ mLambdaOf ( [ "k" ], empType ) resultUpdateRecord
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall ctx

                        expectedSelectResult =
                            sCall ( sVar "alist", "withColumns" )
                                [ sExpCall
                                    (Scala.Variable "Seq")
                                    [ sLit "lastname" ]
                                , sExpCall
                                    (Scala.Variable "Seq")
                                    [ sVar "tmpStr" ]
                                ]
                    in
                    Expect.equal mapped expectedSelectResult

        listFilterWithLambdaAndBasicCondition =
            test "Convert List.filter with lambda and basic condition" <|
                \_ ->
                    let
                        lambdaBody =
                            curryCall
                                ( equalFunction stringTypeInstance
                                , [ mStringLiteralOf "Smith"
                                  , Value.Field stringTypeInstance (Value.Variable empType [ "k" ]) [ "lastname" ]
                                  ]
                                )

                        filterCall =
                            curryCall
                                ( listFilterFunction empType empType
                                , [ mLambdaOf ( [ "k" ], empType ) lambdaBody
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterCall ctx

                        expectedResult =
                            sCall
                                ( sVar "alist", "filter" )
                                [ sSpEqual (applySnowparkFunc "lit" [ sLit "Smith" ]) (Scala.Ref [ "empColumns" ] "lastname") ]
                    in
                    Expect.equal mapped expectedResult

        listFilterWithPredicateFunction =
            test "Convert List.filter with predicate function" <|
                \_ ->
                    let
                        referenceToFunc =
                            Value.Reference (mFuncTypeOf empType boolTypeInstance) (FQName.fqn "UTest" "MyMod" "myPredicate")

                        filterCall =
                            curryCall
                                ( listFilterFunction empType empType
                                , [ referenceToFunc
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterCall ctx

                        expectedResult =
                            sCall
                                ( sVar "alist", "filter" )
                                [ sExpCall (Scala.Ref [ "utest", "MyMod" ] "myPredicate") [ Scala.Variable "empColumns" ] ]
                    in
                    Expect.equal mapped expectedResult

        listFilterWithArgPredicateFunction =
            test "Convert List.filter with predicate function as argument" <|
                \_ ->
                    let
                        referenceToFunc =
                            Value.Variable (mFuncTypeOf empType boolTypeInstance) [ "my", "predicate" ]

                        filterCall =
                            curryCall
                                ( listFilterFunction empType empType
                                , [ referenceToFunc
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterCall ctx

                        expectedResult =
                            sCall
                                ( sVar "alist", "filter" )
                                [ sExpCall (Scala.Variable "myPredicate") [ Scala.Variable "empColumns" ] ]
                    in
                    Expect.equal mapped expectedResult

        listFilterWithPartiallyAppliedFunction =
            test "Convert List.filter with partially applied function" <|
                \_ ->
                    let
                        predicateType =
                            mFuncTypeOf stringTypeInstance (mFuncTypeOf empType boolTypeInstance)

                        referenceToFunc =
                            curryCall
                                ( Value.Reference predicateType (FQName.fqn "UTest" "MyMod" "checkLastName")
                                , [ mStringLiteralOf "Smith" ]
                                )

                        filterCall =
                            curryCall
                                ( listFilterFunction empType empType
                                , [ referenceToFunc
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterCall ctx

                        expectedResult =
                            sCall
                                ( sVar "alist", "filter" )
                                [ sExpCall
                                    (sExpCall (Scala.Ref [ "utest", "MyMod" ] "checkLastName") [ applySnowparkFunc "lit" [ sLit "Smith" ] ])
                                    [ Scala.Variable "empColumns" ]
                                ]
                    in
                    Expect.equal mapped expectedResult

        listConcatToArray =
            test "Convert List.concat to array" <|
                \_ ->
                    let
                        utilFunctionName =
                            FQName.fqn "UTest" "MyMod" "apply"

                        funcType =
                            mFuncTypeOf stringTypeInstance (mListTypeOf empType)

                        referenceToFunc =
                            curryCall
                                ( Value.Reference funcType utilFunctionName
                                , [ mStringLiteralOf "X11" ]
                                )

                        concatCall =
                            curryCall
                                ( listConcatFunction empType
                                , [ mListOf [ referenceToFunc ] ]
                                )

                        newCtx =
                            { ctx | functionClassificationInfo = Dict.fromList [ ( utilFunctionName, MappingContext.FromDfValuesToDfValues ) ] }

                        ( mapped, _ ) =
                            mapValue concatCall newCtx

                        argsArrayConstruct =
                            applySnowparkFunc
                                "array_construct"
                                [ sExpCall (Scala.Ref [ "utest", "MyMod" ] "apply") [ applySnowparkFunc "lit" [ sLit "X11" ] ] ]

                        expectedResult =
                            applySnowparkFunc "callBuiltin" [ sLit "array_flatten", argsArrayConstruct ]
                    in
                    Expect.equal mapped expectedResult

        listConcatToDataFrameUnion =
            test "Convert List.concat to DataFrame union" <|
                \_ ->
                    let
                        utilFunctionName =
                            FQName.fqn "UTest" "MyMod" "apply"

                        funcType =
                            mFuncTypeOf stringTypeInstance (mListTypeOf empType)

                        referenceToFunc txt =
                            curryCall
                                ( Value.Reference funcType utilFunctionName
                                , [ mStringLiteralOf txt ]
                                )

                        concatCall =
                            curryCall
                                ( listConcatFunction empType
                                , [ mListOf [ referenceToFunc "A", referenceToFunc "B" ] ]
                                )

                        ( mapped, _ ) =
                            mapValue concatCall ctx

                        unionCall =
                            sCall
                                ( sExpCall (Scala.Ref [ "utest", "MyMod" ] "apply") [ applySnowparkFunc "lit" [ sLit "A" ] ], "unionAll" )
                                [ sExpCall (Scala.Ref [ "utest", "MyMod" ] "apply") [ applySnowparkFunc "lit" [ sLit "B" ] ] ]
                    in
                    Expect.equal mapped unionCall

        listSumWithMap =
            test "Generate List.sum" <|
                \_ ->
                    let
                        mapLambdaBody =
                            curryCall
                                ( Value.Reference (mFuncTypeOf stringTypeInstance intTypeInstance) (stringsFunctionName [ "length" ])
                                , [ Value.FieldFunction stringTypeInstance [ "lastname" ] ]
                                )

                        mapCall =
                            curryCall
                                ( listMapFunction empType intTypeInstance
                                , [ mLambdaOf ( [ "k" ], empType ) mapLambdaBody
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        sumCall =
                            curryCall
                                ( listSumFunction intTypeInstance
                                , [ mapCall ]
                                )

                        ( mapped, _ ) =
                            mapValue sumCall ctx

                        selectCall =
                            sCall
                                ( sVar "alist", "select" )
                                [ sCall
                                    ( applySnowparkFunc "length" [ applySnowparkFunc "col" [ sLit "lastname" ] ], "as" )
                                    [ sLit "result" ]
                                ]

                        targetSumCall =
                            sCall ( selectCall, "select" ) [ applySnowparkFunc "coalesce" [ applySnowparkFunc "sum" [ applySnowparkFunc "col" [ sLit "result" ] ], applySnowparkFunc "lit" [ sIntLit 0 ] ] ]

                        expected =
                            sCall ( sDot (sDot targetSumCall "first") "get", "getInt" ) [ sIntLit 0 ]
                    in
                    Expect.equal mapped expected

        maybeMapWithFunction =
            test "Generate Maybe.map with function expression" <|
                \_ ->
                    let
                        referenceToFunc =
                            Value.Reference (mFuncTypeOf empType boolTypeInstance) (FQName.fqn "UTest" "MyMod" "myOperation")

                        filterCall =
                            curryCall
                                ( maybeMapFunction stringTypeInstance intTypeInstance
                                , [ referenceToFunc
                                  , mIdOf [ "mval" ] (mMaybeTypeOf stringTypeInstance)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterCall ctx

                        expectedResult =
                            sCall
                                ( applySnowparkFunc "when"
                                    [ sDot (sVar "mval") "is_not_null"
                                    , sExpCall (Scala.Ref [ "utest", "MyMod" ] "myOperation") [ sVar "mval" ]
                                    ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ Scala.Literal Scala.NullLit ] ]
                    in
                    Expect.equal mapped expectedResult

        maybeMapWithLambda =
            test "Generate Maybe.map with lambda expression" <|
                \_ ->
                    let
                        plusType =
                            mFuncTypeOf intTypeInstance (mFuncTypeOf intTypeInstance intTypeInstance)

                        lambdaBody =
                            curryCall
                                ( Value.Reference plusType (basicsFunctionName [ "add" ])
                                , [ mIdOf [ "k" ] intTypeInstance
                                  , mIntLiteralOf 10
                                  ]
                                )

                        filterCall =
                            curryCall
                                ( maybeMapFunction stringTypeInstance intTypeInstance
                                , [ mLambdaOf ( [ "k" ], empType ) lambdaBody
                                  , mIdOf [ "mval" ] (mMaybeTypeOf stringTypeInstance)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue filterCall ctx

                        expectedResult =
                            sCall
                                ( applySnowparkFunc "when"
                                    [ sDot (sVar "mval") "is_not_null"
                                    , Scala.BinOp (sVar "mval") "+" (applySnowparkFunc "lit" [ sIntLit 10 ])
                                    ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ Scala.Literal Scala.NullLit ] ]
                    in
                    Expect.equal mapped expectedResult

        maybeWithDefault =
            test "Generate Maybe.withDefault" <|
                \_ ->
                    let
                        withDefaultCall =
                            curryCall
                                ( maybeWithDefaultFunction stringTypeInstance
                                , [ mStringLiteralOf "A"
                                  , mIdOf [ "mval" ] (mMaybeTypeOf stringTypeInstance)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue withDefaultCall ctx

                        expectedResult =
                            applySnowparkFunc "coalesce" [ sVar "mval", applySnowparkFunc "lit" [ sLit "A" ] ]
                    in
                    Expect.equal mapped expectedResult

        argInliningFunctionByName =
            test "argument inlining from named referece" <|
                \_ ->
                    let
                        functionToInlineName =
                            FQName.fqn "UTest" "MyMod" "Foo"

                        definitionToInline =
                            { inputTypes =
                                [ ( [ "x" ], intTypeInstance, intTypeInstance )
                                , ( [ "y" ], floatTypeInstance, floatTypeInstance )
                                , ( [ "z" ], stringTypeInstance, stringTypeInstance )
                                ]
                            , outputType = stringTypeInstance
                            , body = mIdOf [ "x" ] intTypeInstance
                            }

                        newCtx =
                            { ctx | globalValuesToInline = Dict.insert functionToInlineName definitionToInline ctx.globalValuesToInline }

                        inlined =
                            checkForArgsToInline
                                newCtx
                                [ Value.Reference
                                    (mFuncTypeOf intTypeInstance
                                        (mFuncTypeOf floatTypeInstance
                                            (mFuncTypeOf stringTypeInstance stringTypeInstance)
                                        )
                                    )
                                    functionToInlineName
                                ]

                        expectedResult =
                            [ mLambdaOf ( [ "x" ], intTypeInstance )
                                (mLambdaOf ( [ "y" ], floatTypeInstance )
                                    (mLambdaOf ( [ "z" ], stringTypeInstance )
                                        (mIdOf [ "x" ] intTypeInstance)
                                    )
                                )
                            ]
                    in
                    Expect.equal inlined expectedResult

        argInliningFunctionByCall =
            test "argument inlining from call" <|
                \_ ->
                    let
                        functionToInlineName =
                            FQName.fqn "UTest" "MyMod" "Foo"

                        definitionToInline =
                            { inputTypes = [ ( [ "x" ], intTypeInstance, intTypeInstance ) ]
                            , outputType = intTypeInstance
                            , body = curryCall ( addFunction intTypeInstance, [ mIdOf [ "x" ] intTypeInstance, mIdOf [ "x" ] intTypeInstance ] )
                            }

                        newCtx =
                            { ctx | globalValuesToInline = Dict.insert functionToInlineName definitionToInline ctx.globalValuesToInline }

                        inlined =
                            checkForArgsToInline
                                newCtx
                                [ curryCall
                                    ( Value.Reference
                                        (mFuncTypeOf intTypeInstance intTypeInstance)
                                        functionToInlineName
                                    , [ mIntLiteralOf 100 ]
                                    )
                                ]

                        expectedResult =
                            [ curryCall ( addFunction intTypeInstance, [ mIntLiteralOf 100, mIntLiteralOf 100 ] ) ]
                    in
                    Expect.equal inlined expectedResult

        listMapWithInlining =
            test "Convert List.map with lambda function inlining" <|
                \_ ->
                    let
                        functionToInlineName =
                            FQName.fqn "UTest" "MyMod" "Foo"

                        resultRecordType =
                            mRecordTypeOf [ ( "t", stringTypeInstance ) ]

                        definitionToInline =
                            { inputTypes = [ ( [ "k" ], empType, empType ) ]
                            , outputType = resultRecordType
                            , body = mRecordOf [ ( "t", Value.Field stringTypeInstance (Value.Variable empType [ "k" ]) [ "lastname" ] ) ]
                            }

                        newCtx =
                            { ctx | globalValuesToInline = Dict.insert functionToInlineName definitionToInline ctx.globalValuesToInline }

                        mapCall =
                            curryCall
                                ( listMapFunction empType empType
                                , [ mLambdaOf ( [ "k" ], empType ) (curryCall ( Value.Reference (mFuncTypeOf empType resultRecordType) functionToInlineName, [ mIdOf [ "k" ] empType ] ))
                                  , mIdOf [ "alist" ] (mListTypeOf empType)
                                  ]
                                )

                        ( mapped, _ ) =
                            mapValue mapCall newCtx

                        expectedSelectResult =
                            sCall ( sVar "alist", "select" )
                                [ sCall
                                    ( Scala.Ref [ "empColumns" ] "lastname"
                                    , "as"
                                    )
                                    [ sLit "t" ]
                                ]
                    in
                    Expect.equal mapped expectedSelectResult
    in
    describe "Function mappings tests"
        [ listConcatMapWithLambda
        , listConcatMapWithFunctionExpr
        , listFilterMapWithLambda
        , listFilterMapWithFunctionExpr
        , listMapWithLambdaAndRecord
        , listMapWithLambdaAndRecordAndBinOpInProjection
        , listMapWithLambdaAndLetRecord
        , listMapWithLambdaAndBasicType
        , listMapWithLambdaAndFieldFunction
        , listMapWithFunction
        , listMapWithLambdaAndRecordUpdate
        , listFilterWithLambdaAndBasicCondition
        , listFilterWithPredicateFunction
        , listFilterWithArgPredicateFunction
        , listFilterWithPartiallyAppliedFunction
        , listConcatToArray
        , listConcatToDataFrameUnion
        , listSumWithMap
        , maybeMapWithFunction
        , maybeMapWithLambda
        , maybeWithDefault
        , argInliningFunctionByName
        , argInliningFunctionByCall
        , listMapWithInlining
        ]
