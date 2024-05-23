module Morphir.Snowpark.PatternMatchTests exposing (caseOfGenTests)

import Dict exposing (Dict(..))
import Expect
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal as Literal
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( floatTypeInstance
        , intTypeInstance
        , mIdOf
        , mIntLiteralOf
        , mMaybeTypeOf
        , mStringLiteralOf
        , sCall
        , sDot
        , sExpCall
        , sIntLit
        , sLit
        , sVar
        , stringTypeInstance
        , testDistributionName
        , testDistributionPackage
        )
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MapFunctionsMapping exposing (maybeFunctionName)
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Set
import Test exposing (Test, describe, test)


str : Type.Type ()
str =
    stringTypeInstance


aLit : Literal.Literal
aLit =
    Literal.stringLiteral "A"


a2Lit : Literal.Literal
a2Lit =
    Literal.stringLiteral "a"


mCaseOf : Value.TypedValue -> List ( Value.Pattern (Type.Type ()), Value.TypedValue ) -> Value.TypedValue
mCaseOf expr cases =
    let
        returnType =
            cases
                |> List.head
                |> Maybe.map (\( _, firstValue ) -> Value.valueAttribute firstValue)
                |> Maybe.withDefault (Type.Unit ())
    in
    Value.PatternMatch returnType expr cases


mTuple2Of : Value.TypedValue -> Value.TypedValue -> Value.TypedValue
mTuple2Of value1 value2 =
    let
        tupleType =
            Type.Tuple () [ Value.valueAttribute value1, Value.valueAttribute value2 ]
    in
    Value.Tuple tupleType [ value1, value2 ]


caseOfGenTests : Test
caseOfGenTests =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        ( calculatedContext, _, _ ) =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        cases =
            [ ( Value.LiteralPattern str aLit, Value.Literal str a2Lit )
            , ( Value.WildcardPattern str, Value.Literal str (Literal.stringLiteral "D") )
            ]

        inputCase =
            Value.PatternMatch stringTypeInstance (Value.Literal str (Literal.stringLiteral "X")) cases

        ctx =
            { emptyValueMappingContext | typesContextInfo = calculatedContext }

        ( mappedCase, _ ) =
            mapValue inputCase ctx

        mappedCaseParts =
            case mappedCase of
                Scala.Apply (Scala.Select (Scala.Apply (Scala.Ref _ "when") [ Scala.ArgValue _ (Scala.BinOp left1 "===" right1), Scala.ArgValue _ result1 ]) "otherwise") [ Scala.ArgValue _ result2 ] ->
                    [ left1, right1, result1, result2 ]

                _ ->
                    []

        assertCaseWithLiterals =
            test "Convert case of with literals" <|
                \_ ->
                    Expect.equal
                        [ applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit "X") ]
                        , applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit "A") ]
                        , applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit "a") ]
                        , applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit "D") ]
                        ]
                        mappedCaseParts

        assertCaseWithMaybeFullCases =
            test "Generate case of with Maybe type with both constructors" <|
                \_ ->
                    let
                        inputCaseExpr =
                            mCaseOf (mIdOf [ "x" ] (mMaybeTypeOf stringTypeInstance))
                                [ ( Value.ConstructorPattern
                                        (mMaybeTypeOf stringTypeInstance)
                                        (maybeFunctionName [ "just" ])
                                        [ Value.AsPattern stringTypeInstance (Value.WildcardPattern stringTypeInstance) [ "t" ] ]
                                  , mIdOf [ "t" ] stringTypeInstance
                                  )
                                , ( Value.ConstructorPattern (mMaybeTypeOf stringTypeInstance) (maybeFunctionName [ "nothing" ]) []
                                  , mStringLiteralOf "DEFAULT"
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( applySnowparkFunc "when" [ sDot (sVar "x") "is_not_null", sVar "x" ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sLit "DEFAULT" ] ]
                    in
                    Expect.equal mapped expected

        assertCaseWithMaybeWithDefault =
            test "Generate case of with Maybe type with default case" <|
                \_ ->
                    let
                        inputCaseExpr =
                            mCaseOf (mIdOf [ "x" ] (mMaybeTypeOf stringTypeInstance))
                                [ ( Value.ConstructorPattern
                                        (mMaybeTypeOf stringTypeInstance)
                                        (maybeFunctionName [ "just" ])
                                        [ Value.AsPattern stringTypeInstance (Value.WildcardPattern stringTypeInstance) [ "t" ] ]
                                  , mIdOf [ "t" ] stringTypeInstance
                                  )
                                , ( Value.WildcardPattern (mMaybeTypeOf stringTypeInstance)
                                  , mStringLiteralOf "DEFAULT"
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( applySnowparkFunc "when" [ sDot (sVar "x") "is_not_null", sVar "x" ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sLit "DEFAULT" ] ]
                    in
                    Expect.equal mapped expected

        assertCaseWithMaybeWithDefaultAndNothing =
            test "Generate case of with Maybe type with Nothing and default case" <|
                \_ ->
                    let
                        inputCaseExpr =
                            mCaseOf (mIdOf [ "x" ] (mMaybeTypeOf stringTypeInstance))
                                [ ( Value.ConstructorPattern (mMaybeTypeOf stringTypeInstance) (maybeFunctionName [ "nothing" ]) []
                                  , mStringLiteralOf "DEFAULT1"
                                  )
                                , ( Value.WildcardPattern (mMaybeTypeOf stringTypeInstance)
                                  , mStringLiteralOf "DEFAULT2"
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( applySnowparkFunc "when" [ sDot (sVar "x") "is_not_null", applySnowparkFunc "lit" [ sLit "DEFAULT2" ] ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sLit "DEFAULT1" ] ]
                    in
                    Expect.equal mapped expected

        assertCaseWithTupleAndLiteralTuple =
            test "Generate case of with tuple and literal tuple as expression" <|
                \_ ->
                    let
                        innerJustPattern =
                            Value.ConstructorPattern
                                (mMaybeTypeOf stringTypeInstance)
                                (maybeFunctionName [ "just" ])
                                [ Value.AsPattern stringTypeInstance (Value.WildcardPattern stringTypeInstance) [ "t" ] ]

                        inputCaseExpr =
                            mCaseOf (mTuple2Of (mIdOf [ "x" ] (mMaybeTypeOf stringTypeInstance)) (mIdOf [ "y" ] (mMaybeTypeOf floatTypeInstance)))
                                [ ( Value.TuplePattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                        [ innerJustPattern, Value.WildcardPattern floatTypeInstance ]
                                  , mIdOf [ "t" ] stringTypeInstance
                                  )
                                , ( Value.TuplePattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                        [ Value.WildcardPattern stringTypeInstance, innerJustPattern ]
                                  , mStringLiteralOf "DEFAULT1"
                                  )
                                , ( Value.WildcardPattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                  , mStringLiteralOf "DEFAULT"
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( sCall
                                    ( applySnowparkFunc "when" [ sDot (sVar "x") "is_not_null", sVar "x" ]
                                    , "when"
                                    )
                                    [ sDot (sVar "y") "is_not_null", applySnowparkFunc "lit" [ sLit "DEFAULT1" ] ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sLit "DEFAULT" ] ]
                    in
                    Expect.equal mapped expected

        assertCaseWithTupleAndLiteralTupleWithTupleVar =
            test "Generate case of with tuple and tuple variable as expression" <|
                \_ ->
                    let
                        innerJustPattern =
                            Value.ConstructorPattern
                                (mMaybeTypeOf stringTypeInstance)
                                (maybeFunctionName [ "just" ])
                                [ Value.AsPattern stringTypeInstance (Value.WildcardPattern stringTypeInstance) [ "t" ] ]

                        inputCaseExpr =
                            mCaseOf (mIdOf [ "tVar" ] (Type.Tuple () [ stringTypeInstance, floatTypeInstance ]))
                                [ ( Value.TuplePattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                        [ innerJustPattern, Value.WildcardPattern floatTypeInstance ]
                                  , mIdOf [ "t" ] stringTypeInstance
                                  )
                                , ( Value.TuplePattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                        [ Value.WildcardPattern stringTypeInstance, innerJustPattern ]
                                  , mStringLiteralOf "DEFAULT1"
                                  )
                                , ( Value.WildcardPattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                  , mStringLiteralOf "DEFAULT"
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( sCall
                                    ( applySnowparkFunc "when" [ sDot (sExpCall (sVar "tVar") [ sIntLit 0 ]) "is_not_null", sExpCall (sVar "tVar") [ sIntLit 0 ] ]
                                    , "when"
                                    )
                                    [ sDot (sExpCall (sVar "tVar") [ sIntLit 1 ]) "is_not_null", applySnowparkFunc "lit" [ sLit "DEFAULT1" ] ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sLit "DEFAULT" ] ]
                    in
                    Expect.equal mapped expected

        assertCaseWithTupleAndLiteralTupleWithoutDefault =
            test "Generate case of with tuple and literal tuple as expression without default case" <|
                \_ ->
                    let
                        innerJustPattern =
                            Value.ConstructorPattern
                                (mMaybeTypeOf stringTypeInstance)
                                (maybeFunctionName [ "just" ])
                                [ Value.AsPattern stringTypeInstance (Value.WildcardPattern stringTypeInstance) [ "t" ] ]

                        inputCaseExpr =
                            mCaseOf (mTuple2Of (mIdOf [ "x" ] (mMaybeTypeOf stringTypeInstance)) (mIdOf [ "y" ] (mMaybeTypeOf floatTypeInstance)))
                                [ ( Value.TuplePattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                        [ innerJustPattern, Value.WildcardPattern floatTypeInstance ]
                                  , mIdOf [ "t" ] stringTypeInstance
                                  )
                                , ( Value.TuplePattern (Type.Tuple () [ stringTypeInstance, floatTypeInstance ])
                                        [ Value.WildcardPattern stringTypeInstance, innerJustPattern ]
                                  , mStringLiteralOf "DEFAULT1"
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( applySnowparkFunc "when" [ sDot (sVar "x") "is_not_null", sVar "x" ]
                                , "when"
                                )
                                [ sDot (sVar "y") "is_not_null", applySnowparkFunc "lit" [ sLit "DEFAULT1" ] ]
                    in
                    Expect.equal mapped expected

        assertCaseWithCustomTypeWithParameters =
            test "Generate case of with Custom type with parameters" <|
                \_ ->
                    let
                        timeRangeType =
                            Type.Reference () (FQName.fqn "UTest" "MyMod" "TimeRange") []

                        myModName name =
                            FQName.fqn "UTest" "MyMod" name

                        inputCaseExpr =
                            mCaseOf (mIdOf [ "x" ] timeRangeType)
                                [ ( Value.ConstructorPattern timeRangeType
                                        (myModName "Seconds")
                                        [ Value.AsPattern intTypeInstance (Value.WildcardPattern intTypeInstance) [ "t" ] ]
                                  , mIdOf [ "t" ] intTypeInstance
                                  )
                                , ( Value.ConstructorPattern timeRangeType
                                        (myModName "MinutesAndSeconds")
                                        [ Value.wildcardPattern intTypeInstance, Value.AsPattern intTypeInstance (Value.WildcardPattern intTypeInstance) [ "t" ] ]
                                  , mIdOf [ "t" ] intTypeInstance
                                  )
                                , ( Value.ConstructorPattern timeRangeType (myModName "Zero") []
                                  , mIntLiteralOf 100
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( sCall
                                    ( applySnowparkFunc "when"
                                        [ Scala.BinOp (sExpCall (sVar "x") [ sLit "__tag" ]) "===" (applySnowparkFunc "lit" [ sLit "Seconds" ])
                                        , sExpCall (sVar "x") [ sLit "field0" ]
                                        ]
                                    , "when"
                                    )
                                    [ Scala.BinOp (sExpCall (sVar "x") [ sLit "__tag" ]) "===" (applySnowparkFunc "lit" [ sLit "MinutesAndSeconds" ])
                                    , sExpCall (sVar "x") [ sLit "field1" ]
                                    ]
                                , "when"
                                )
                                [ Scala.BinOp (sExpCall (sVar "x") [ sLit "__tag" ]) "===" (applySnowparkFunc "lit" [ sLit "Zero" ])
                                , applySnowparkFunc "lit" [ sIntLit 100 ]
                                ]
                    in
                    Expect.equal mapped expected

        assertCaseWithCustomTypeWithParametersAndDefault =
            test "Generate case of with Custom type with parameters and default value" <|
                \_ ->
                    let
                        timeRangeType =
                            Type.Reference () (FQName.fqn "UTest" "MyMod" "TimeRange") []

                        myModName name =
                            FQName.fqn "UTest" "MyMod" name

                        inputCaseExpr =
                            mCaseOf (mIdOf [ "x" ] timeRangeType)
                                [ ( Value.ConstructorPattern timeRangeType
                                        (myModName "Seconds")
                                        [ Value.AsPattern intTypeInstance (Value.WildcardPattern intTypeInstance) [ "t" ] ]
                                  , mIdOf [ "t" ] intTypeInstance
                                  )
                                , ( Value.ConstructorPattern timeRangeType
                                        (myModName "MinutesAndSeconds")
                                        [ Value.wildcardPattern intTypeInstance, Value.AsPattern intTypeInstance (Value.WildcardPattern intTypeInstance) [ "t" ] ]
                                  , mIdOf [ "t" ] intTypeInstance
                                  )
                                , ( Value.WildcardPattern timeRangeType
                                  , mIntLiteralOf 101
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( sCall
                                    ( applySnowparkFunc "when"
                                        [ Scala.BinOp (sExpCall (sVar "x") [ sLit "__tag" ]) "===" (applySnowparkFunc "lit" [ sLit "Seconds" ])
                                        , sExpCall (sVar "x") [ sLit "field0" ]
                                        ]
                                    , "when"
                                    )
                                    [ Scala.BinOp (sExpCall (sVar "x") [ sLit "__tag" ]) "===" (applySnowparkFunc "lit" [ sLit "MinutesAndSeconds" ])
                                    , sExpCall (sVar "x") [ sLit "field1" ]
                                    ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sIntLit 101 ] ]
                    in
                    Expect.equal mapped expected

        assertCaseWithCustomTypeWithoutParameters =
            test "Generate case of with Custom type without parameters" <|
                \_ ->
                    let
                        deptKindType =
                            Type.Reference () (FQName.fqn "UTest" "MyMod" "DeptKind") []

                        myModName name =
                            FQName.fqn "UTest" "MyMod" name

                        inputCaseExpr =
                            mCaseOf (mIdOf [ "x" ] deptKindType)
                                [ ( Value.ConstructorPattern deptKindType (myModName "Hr") []
                                  , mIntLiteralOf 10
                                  )
                                , ( Value.ConstructorPattern deptKindType (myModName "It") []
                                  , mIntLiteralOf 20
                                  )
                                , ( Value.ConstructorPattern deptKindType (myModName "Logic") []
                                  , mIntLiteralOf 30
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( sCall
                                    ( applySnowparkFunc "when"
                                        [ Scala.BinOp (sVar "x") "===" (Scala.Ref [ "utest", "MyMod", "DeptKind" ] "Hr")
                                        , applySnowparkFunc "lit" [ sIntLit 10 ]
                                        ]
                                    , "when"
                                    )
                                    [ Scala.BinOp (sVar "x") "===" (Scala.Ref [ "utest", "MyMod", "DeptKind" ] "It")
                                    , applySnowparkFunc "lit" [ sIntLit 20 ]
                                    ]
                                , "when"
                                )
                                [ Scala.BinOp (sVar "x") "===" (Scala.Ref [ "utest", "MyMod", "DeptKind" ] "Logic")
                                , applySnowparkFunc "lit" [ sIntLit 30 ]
                                ]
                    in
                    Expect.equal mapped expected

        assertCaseWithCustomTypeWithoutParametersWithDefault =
            test "Generate case of with Custom type without parameters with default case" <|
                \_ ->
                    let
                        deptKindType =
                            Type.Reference () (FQName.fqn "UTest" "MyMod" "DeptKind") []

                        myModName name =
                            FQName.fqn "UTest" "MyMod" name

                        inputCaseExpr =
                            mCaseOf (mIdOf [ "x" ] deptKindType)
                                [ ( Value.ConstructorPattern deptKindType (myModName "Hr") []
                                  , mIntLiteralOf 10
                                  )
                                , ( Value.ConstructorPattern deptKindType (myModName "It") []
                                  , mIntLiteralOf 20
                                  )
                                , ( Value.WildcardPattern deptKindType
                                  , mIntLiteralOf 30
                                  )
                                ]

                        ( mapped, _ ) =
                            mapValue inputCaseExpr ctx

                        expected =
                            sCall
                                ( sCall
                                    ( applySnowparkFunc "when"
                                        [ Scala.BinOp (sVar "x") "===" (Scala.Ref [ "utest", "MyMod", "DeptKind" ] "Hr")
                                        , applySnowparkFunc "lit" [ sIntLit 10 ]
                                        ]
                                    , "when"
                                    )
                                    [ Scala.BinOp (sVar "x") "===" (Scala.Ref [ "utest", "MyMod", "DeptKind" ] "It")
                                    , applySnowparkFunc "lit" [ sIntLit 20 ]
                                    ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sIntLit 30 ] ]
                    in
                    Expect.equal mapped expected
    in
    describe "PatternConversionTests"
        [ assertCaseWithLiterals
        , assertCaseWithMaybeFullCases
        , assertCaseWithMaybeWithDefault
        , assertCaseWithMaybeWithDefaultAndNothing
        , assertCaseWithTupleAndLiteralTuple
        , assertCaseWithTupleAndLiteralTupleWithTupleVar
        , assertCaseWithTupleAndLiteralTupleWithoutDefault
        , assertCaseWithCustomTypeWithParameters
        , assertCaseWithCustomTypeWithParametersAndDefault
        , assertCaseWithCustomTypeWithoutParameters
        , assertCaseWithCustomTypeWithoutParametersWithDefault
        ]
