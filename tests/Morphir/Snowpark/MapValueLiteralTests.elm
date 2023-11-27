module Morphir.Snowpark.MapValueLiteralTests exposing (mapValueLiteralTests)
import Expect
import Test exposing (Test, describe, test)
import Morphir.IR.Literal as Literal
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value
import Morphir.IR.Type as Type
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.Snowpark.MappingContext exposing (emptyValueMappingContext)

functionNamespace : List String
functionNamespace = ["com", "snowflake", "snowpark", "functions"]

booleanReference : Type.Type ()
booleanReference = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "boolean" ] ) []
booleanTest : Scala.Value
booleanTest =  Scala.Apply
                        (Scala.Ref functionNamespace "lit")
                        ([Scala.ArgValue
                            Nothing (Scala.Literal (Scala.BooleanLit True))])

stringReference : Type.Type ()
stringReference = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "boolean" ] ) []
stringTest : Scala.Value
stringTest =  Scala.Apply
                        (Scala.Ref functionNamespace "lit")
                        ([Scala.ArgValue
                            Nothing (Scala.Literal (Scala.StringLit "Hello world"))])

characterReference : Type.Type ()
characterReference = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "character" ] ) []
characterTest : Scala.Value
characterTest =  Scala.Apply
                        (Scala.Ref functionNamespace "lit")
                        ([Scala.ArgValue
                            Nothing (Scala.Literal (Scala.CharacterLit 'C'))])

floatReference : Type.Type ()
floatReference = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) []
floatTest : Scala.Value
floatTest =  Scala.Apply
                        (Scala.Ref functionNamespace "lit")
                        ([Scala.ArgValue
                            Nothing (Scala.Literal (Scala.FloatLit 3.24))])


integerReference : Type.Type ()
integerReference = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "integer" ] ) []
integerTest : Scala.Value
integerTest =  Scala.Apply
                        (Scala.Ref functionNamespace "lit")
                        ([Scala.ArgValue
                            Nothing (Scala.Literal (Scala.IntegerLit 5))])

mapValueLiteralTests: Test
mapValueLiteralTests =
    let
        emptyContext = emptyValueMappingContext
        assertBooleanLiteral =
            test ("Convert boolean") <|
            \_ ->
                let
                    (mapped, _ ) =
                        mapValue (Value.Literal booleanReference (Literal.BoolLiteral True)) emptyContext
                in
                Expect.equal booleanTest mapped
        assertStringLiteral =
            test ("Convert string") <|
            \_ ->
                let
                    (mapped, _ ) =
                        (mapValue (Value.Literal stringReference (Literal.StringLiteral "Hello world")) emptyContext)
                in
                Expect.equal stringTest mapped
        assertCharacterLiteral =
            test ("Convert character") <|
            \_ ->
                let
                    (mapped, _ ) =
                        mapValue (Value.Literal characterReference (Literal.CharLiteral 'C')) emptyContext
                in
                Expect.equal characterTest mapped
        assertFloatLiteral =
            test ("Convert float") <|
            \_ ->
                let
                    (mapped, _ ) =
                        mapValue (Value.Literal floatReference (Literal.FloatLiteral 3.24)) emptyContext
                in
                Expect.equal floatTest mapped
        assertIntegerLiteral =
            test ("Convert integer") <|
            \_ ->
                let
                    (mapped, _) =
                        mapValue (Value.Literal integerReference (Literal.WholeNumberLiteral 5)) emptyContext
                in
                Expect.equal integerTest mapped
    in
    describe "literalMapTransform"
        [
            assertBooleanLiteral,
            assertStringLiteral,
            assertCharacterLiteral,
            assertFloatLiteral,
            assertIntegerLiteral
        ]