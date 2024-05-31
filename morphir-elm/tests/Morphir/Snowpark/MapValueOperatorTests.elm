module Morphir.Snowpark.MapValueOperatorTests exposing (mapValueListTest)

import Expect
import Morphir.IR.Literal as Literal
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( floatTypeInstance
        , intTypeInstance
        , mFloatLiteralOf
        , mFuncTypeOf
        , mIntLiteralOf
        , morphirNamespace
        , sExpCall
        , sFloatLit
        , sSnowparkRefFuncion
        )
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MappingContext exposing (emptyValueMappingContext)
import Test exposing (Test, describe, test)


createNumberLiteral : Int -> ValueIR.Value va (TypeIR.Type ())
createNumberLiteral number =
    ValueIR.Literal
        (TypeIR.Reference
            ()
            ( morphirNamespace, [ [ "string" ] ], [ "string" ] )
            []
        )
        (Literal.WholeNumberLiteral number)


floorInput : ValueIR.TypedValue
floorInput =
    ValueIR.Apply intTypeInstance floorRef <| mFloatLiteralOf 2.5


floorRef : ValueIR.TypedValue
floorRef =
    ValueIR.Reference
        (mFuncTypeOf floatTypeInstance intTypeInstance)
        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "floor" ] )


floorExpected : Scala.Value
floorExpected =
    sExpCall (sSnowparkRefFuncion "floor") <| floorParams


floorParams : List Scala.Value
floorParams =
    [ sExpCall (sSnowparkRefFuncion "lit") <| [ sFloatLit 2.5 ] ]


modbyInput : ValueIR.TypedValue
modbyInput =
    ValueIR.Apply intTypeInstance modbyFunction <| mIntLiteralOf 6


modbyFunction : ValueIR.TypedValue
modbyFunction =
    ValueIR.Apply (mFuncTypeOf intTypeInstance intTypeInstance) modbyRef <| mIntLiteralOf 5


modbyRef : ValueIR.TypedValue
modbyRef =
    ValueIR.Reference
        (mFuncTypeOf intTypeInstance (mFuncTypeOf intTypeInstance intTypeInstance))
        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "mod", "by" ] )


inputOperatorTest : List String -> ValueIR.Value ta (TypeIR.Type ())
inputOperatorTest operatorName =
    ValueIR.Apply
        (TypeIR.Reference
            ()
            ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] )
            []
        )
        (ValueIR.Apply
            (TypeIR.Function
                ()
                (TypeIR.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [])
                (TypeIR.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [])
            )
            (ValueIR.Reference
                (TypeIR.Function
                    ()
                    (TypeIR.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [])
                    (TypeIR.Function () (TypeIR.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) []) (TypeIR.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) []))
                )
                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], operatorName )
            )
            (createNumberLiteral 5)
        )
        (createNumberLiteral 6)


outputOperatorTest : String -> Scala.Value
outputOperatorTest operator =
    Scala.BinOp (Scala.Apply (Scala.Ref [ "com", "snowflake", "snowpark", "functions" ] "lit") [ Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 5)) ])
        operator
        (Scala.Apply (Scala.Ref [ "com", "snowflake", "snowpark", "functions" ] "lit") [ Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 6)) ])


mapValueListTest : Test
mapValueListTest =
    let
        emptyContext =
            emptyValueMappingContext

        assertAddTest =
            test "add" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (inputOperatorTest [ "add" ]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "+")

        assertSubstractTest =
            test "Substract" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (inputOperatorTest [ "subtract" ]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "-")

        assertMultiplyTest =
            test "multiply" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (inputOperatorTest [ "multiply" ]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "*")

        assertdivideTest =
            test "divide" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (inputOperatorTest [ "divide" ]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "/")

        assertintegerdivideTest =
            test "integer divide" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (inputOperatorTest [ "integer", "divide" ]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "/")

        assertModbyTest =
            test "modby test" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue modbyInput emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "%")

        assertFloorTest =
            test "floor test" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue floorInput emptyContext
                    in
                    Expect.equal mapped floorExpected
    in
    describe "arithmetic operators"
        [ assertAddTest
        , assertSubstractTest
        , assertMultiplyTest
        , assertdivideTest
        , assertintegerdivideTest
        , assertModbyTest
        , assertFloorTest
        ]
