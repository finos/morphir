module Morphir.Snowpark.MapValueOperatorTests exposing (mapValueListTest)

import Expect
import Test exposing (Test, describe, test)
import Morphir.IR.Value as ValueIR
import Morphir.IR.Literal as Literal
import Morphir.IR.Type as TypeIR
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.MappingContext exposing (emptyValueMappingContext)
import Morphir.Snowpark.CommonTestUtils exposing (morphirNamespace)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)

createNumberLiteral : Int -> ValueIR.Value va (TypeIR.Type ())
createNumberLiteral number = 
    ValueIR.Literal (
            TypeIR.Reference 
                        ()
                        ( morphirNamespace,[["string"]],["string"] )
                        []
        )
        (Literal.WholeNumberLiteral number)

inputOperatorTest : List String -> ValueIR.Value ta (TypeIR.Type ())
inputOperatorTest operatorName = 
    ValueIR.Apply
    (TypeIR.Reference 
        () ([["morphir"],["s","d","k"]],[["basics"]],["int"])[]
    )
    (ValueIR.Apply 
        (TypeIR.Function 
            ()
            (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["int"]) [])
            (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["int"]) [])
        )
        (ValueIR.Reference
            (TypeIR.Function
                ()
                (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["int"]) [])
                (TypeIR.Function () (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["int"]) []) (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["int"]) []))
            )
            ([["morphir"],["s","d","k"]],[["basics"]], operatorName)
        )
        (createNumberLiteral 5)
    )
    (createNumberLiteral 6)

outputOperatorTest : String -> Scala.Value
outputOperatorTest operator =
    Scala.BinOp (Scala.Apply (Scala.Ref ["com","snowflake","snowpark","functions"] "lit") [Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 5))])
        operator
        (Scala.Apply (Scala.Ref ["com","snowflake","snowpark","functions"] "lit") [Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 6))])

mapValueListTest : Test
mapValueListTest =
    let
        emptyContext = emptyValueMappingContext
        assertAddTest =
            test ("add") <|
                \_ ->
                    let
                        (mapped, _) =
                            mapValue (inputOperatorTest ["add"])  emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "+")
        assertSubstractTest =
            test ("Substract") <|
                \_ ->
                    let
                        (mapped, _) =
                            mapValue (inputOperatorTest ["subtract"]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "-")
        assertMultiplyTest =
            test ("multiply") <|
                \_ ->
                    let
                        (mapped, _) =
                            mapValue (inputOperatorTest ["multiply"]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "*")
        assertdivideTest =
            test ("divide") <|
                \_ ->
                    let
                        (mapped, _) =
                            mapValue (inputOperatorTest ["divide"]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "/")
        assertintegerdivideTest =
            test ("integer divide") <|
                \_ ->
                    let 
                        (mapped, _) =
                            mapValue (inputOperatorTest ["integer", "divide"]) emptyContext
                    in
                    Expect.equal mapped (outputOperatorTest "/")
    in
    describe "arithmetic operators"
        [
            assertAddTest
            , assertSubstractTest
            , assertMultiplyTest
            , assertdivideTest
            , assertintegerdivideTest
        ]
    