module Morphir.Snowpark.MapValueLiteralTests exposing
    ( mapIfValueExpressionsTests
    , mapLetValueExpressionsTests
    , mapValueLiteralTests
    )

import Expect
import Morphir.IR.Literal as Literal
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( addFunction
        , intTypeInstance
        , mFuncTypeOf
        , mIdOf
        , mIntLiteralOf
        , mLetOf
        , sBlock
        , sCall
        , sExpCall
        , sIntLit
        , sVar
        )
import Morphir.Snowpark.Constants as Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MappingContext exposing (emptyValueMappingContext)
import Morphir.Snowpark.ReferenceUtils exposing (curryCall)
import Test exposing (Test, describe, test)


functionNamespace : List String
functionNamespace =
    [ "com", "snowflake", "snowpark", "functions" ]


booleanReference : Type.Type ()
booleanReference =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "boolean" ] ) []


booleanTest : Scala.Value
booleanTest =
    Scala.Apply
        (Scala.Ref functionNamespace "lit")
        [ Scala.ArgValue
            Nothing
            (Scala.Literal (Scala.BooleanLit True))
        ]


stringReference : Type.Type ()
stringReference =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "boolean" ] ) []


stringTest : Scala.Value
stringTest =
    Scala.Apply
        (Scala.Ref functionNamespace "lit")
        [ Scala.ArgValue
            Nothing
            (Scala.Literal (Scala.StringLit "Hello world"))
        ]


characterReference : Type.Type ()
characterReference =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "character" ] ) []


characterTest : Scala.Value
characterTest =
    Scala.Apply
        (Scala.Ref functionNamespace "lit")
        [ Scala.ArgValue
            Nothing
            (Scala.Literal (Scala.CharacterLit 'C'))
        ]


floatReference : Type.Type ()
floatReference =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) []


floatTest : Scala.Value
floatTest =
    Scala.Apply
        (Scala.Ref functionNamespace "lit")
        [ Scala.ArgValue
            Nothing
            (Scala.Literal (Scala.FloatLit 3.24))
        ]


integerReference : Type.Type ()
integerReference =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "integer" ] ) []


integerTest : Scala.Value
integerTest =
    Scala.Apply
        (Scala.Ref functionNamespace "lit")
        [ Scala.ArgValue
            Nothing
            (Scala.Literal (Scala.IntegerLit 5))
        ]


mapValueLiteralTests : Test
mapValueLiteralTests =
    let
        emptyContext =
            emptyValueMappingContext

        assertBooleanLiteral =
            test "Convert boolean" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (Value.Literal booleanReference (Literal.BoolLiteral True)) emptyContext
                    in
                    Expect.equal booleanTest mapped

        assertStringLiteral =
            test "Convert string" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (Value.Literal stringReference (Literal.StringLiteral "Hello world")) emptyContext
                    in
                    Expect.equal stringTest mapped

        assertCharacterLiteral =
            test "Convert character" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (Value.Literal characterReference (Literal.CharLiteral 'C')) emptyContext
                    in
                    Expect.equal characterTest mapped

        assertFloatLiteral =
            test "Convert float" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (Value.Literal floatReference (Literal.FloatLiteral 3.24)) emptyContext
                    in
                    Expect.equal floatTest mapped

        assertIntegerLiteral =
            test "Convert integer" <|
                \_ ->
                    let
                        ( mapped, _ ) =
                            mapValue (Value.Literal integerReference (Literal.WholeNumberLiteral 5)) emptyContext
                    in
                    Expect.equal integerTest mapped
    in
    describe "literalMapTransform"
        [ assertBooleanLiteral
        , assertStringLiteral
        , assertCharacterLiteral
        , assertFloatLiteral
        , assertIntegerLiteral
        ]


mapIfValueExpressionsTests : Test
mapIfValueExpressionsTests =
    let
        emptyContext =
            emptyValueMappingContext

        assertIfExprGeneration =
            test "Generation for if expressions" <|
                \_ ->
                    let
                        ifExample =
                            Value.IfThenElse intTypeInstance (mIdOf [ "flag" ] booleanReference) (mIntLiteralOf 10) (mIntLiteralOf 20)

                        ( mapped, _ ) =
                            mapValue ifExample emptyContext

                        expectedIf =
                            sCall
                                ( applySnowparkFunc "when" [ sVar "flag", applySnowparkFunc "lit" [ sIntLit 10 ] ]
                                , "otherwise"
                                )
                                [ applySnowparkFunc "lit" [ sIntLit 20 ] ]
                    in
                    Expect.equal expectedIf mapped
    in
    describe "IF Value mappings"
        [ assertIfExprGeneration
        ]


mapLetValueExpressionsTests : Test
mapLetValueExpressionsTests =
    let
        emptyContext =
            emptyValueMappingContext

        assertLetExprGenerationWithOneBinding =
            test "Generation for let expressions with one binding" <|
                \_ ->
                    let
                        letExample =
                            mLetOf [ "tmp" ] (mIntLiteralOf 10) (curryCall ( addFunction intTypeInstance, [ mIdOf [ "tmp" ] intTypeInstance, mIntLiteralOf 10 ] ))

                        ( mapped, _ ) =
                            mapValue letExample emptyContext

                        expectedVal =
                            sBlock (Scala.BinOp (sVar "tmp") "+" (applySnowparkFunc "lit" [ sIntLit 10 ]))
                                [ ( "tmp", applySnowparkFunc "lit" [ sIntLit 10 ] ) ]
                    in
                    Expect.equal expectedVal mapped

        assertLetExprGenerationWithSeveralBindings =
            test "Generation for let expressions with several bindings" <|
                \_ ->
                    let
                        letExample =
                            mLetOf [ "tmp1" ] (mIntLiteralOf 10) <|
                                mLetOf [ "tmp2" ] (mIntLiteralOf 20) <|
                                    mLetOf [ "tmp3" ] (mIntLiteralOf 30) (curryCall ( addFunction intTypeInstance, [ mIdOf [ "tmp1" ] intTypeInstance, mIntLiteralOf 10 ] ))

                        ( mapped, _ ) =
                            mapValue letExample emptyContext

                        expectedVal =
                            sBlock (Scala.BinOp (sVar "tmp1") "+" (applySnowparkFunc "lit" [ sIntLit 10 ]))
                                [ ( "tmp1", applySnowparkFunc "lit" [ sIntLit 10 ] )
                                , ( "tmp2", applySnowparkFunc "lit" [ sIntLit 20 ] )
                                , ( "tmp3", applySnowparkFunc "lit" [ sIntLit 30 ] )
                                ]
                    in
                    Expect.equal expectedVal mapped

        assertLetExprGenerationWithFunctionDecl =
            test "Generation for let expressions with function decls" <|
                \_ ->
                    let
                        userDefinedFuncType =
                            mFuncTypeOf intTypeInstance (mFuncTypeOf intTypeInstance intTypeInstance)

                        letLambda =
                            Value.Lambda userDefinedFuncType
                                (Value.AsPattern intTypeInstance (Value.WildcardPattern intTypeInstance) [ "x" ])
                                (curryCall ( addFunction intTypeInstance, [ mIdOf [ "x" ] intTypeInstance, mIdOf [ "x" ] intTypeInstance ] ))

                        letExample =
                            Value.LetDefinition
                                userDefinedFuncType
                                [ "double" ]
                                { inputTypes = []
                                , outputType = userDefinedFuncType
                                , body = letLambda
                                }
                                (curryCall ( mIdOf [ "double" ] userDefinedFuncType, [ mIdOf [ "tmp1" ] intTypeInstance ] ))

                        ( mapped, _ ) =
                            mapValue letExample emptyContext

                        lambdaArgDecl =
                            { modifiers = [], tpe = Constants.typeRefForSnowparkType "Column", name = "x", defaultValue = Nothing }

                        expectedVal =
                            Scala.Block
                                [ Scala.FunctionDecl
                                    { modifiers = []
                                    , name = "double"
                                    , typeArgs = []
                                    , args = [ [ lambdaArgDecl ] ]
                                    , returnType = Nothing
                                    , body = Just <| Scala.BinOp (sVar "x") "+" (sVar "x")
                                    }
                                ]
                                (sExpCall (sVar "double") [ sVar "tmp1" ])
                    in
                    Expect.equal expectedVal mapped
    in
    describe "Let Value mappings"
        [ assertLetExprGenerationWithOneBinding
        , assertLetExprGenerationWithSeveralBindings
        , assertLetExprGenerationWithFunctionDecl
        ]
