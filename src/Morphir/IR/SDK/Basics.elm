{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.IR.SDK.Basics exposing (add, and, boolType, composeLeft, composeRight, divide, equal, floatType, greaterThan, greaterThanOrEqual, intType, integerDivide, isNumber, lessThan, lessThanOrEqual, moduleName, moduleSpec, multiply, nativeFunctions, negate, neverType, notEqual, or, orderType, power, subtract)

import Dict exposing (Dict)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native exposing (boolLiteral, charLiteral, eval1, eval2, expectLiteral, floatLiteral, intLiteral, oneOf, returnLiteral, stringLiteral)


moduleName : ModuleName
moduleName =
    Path.fromString "Basics"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Int", OpaqueTypeSpecification [] |> Documented "Type that represents an integer value." )
            , ( Name.fromString "Float", OpaqueTypeSpecification [] |> Documented "Type that represents a floating-point number." )
            , ( Name.fromString "Order"
              , CustomTypeSpecification []
                    (Dict.fromList
                        [ ( Name.fromString "LT", [] )
                        , ( Name.fromString "EQ", [] )
                        , ( Name.fromString "GT", [] )
                        ]
                    )
                    |> Documented "Represents the relative ordering of two things. The relations are less than, equal to, and greater than."
              )
            , ( Name.fromString "Bool", OpaqueTypeSpecification [] |> Documented "Type that represents a boolean value." )
            , ( Name.fromString "Never", OpaqueTypeSpecification [] |> Documented "A value that can never happen!" )
            ]
    , values =
        Dict.fromList
            -- number
            [ vSpec "add" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
            , vSpec "subtract" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
            , vSpec "multiply" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
            , vSpec "divide" [ ( "a", floatType () ), ( "b", floatType () ) ] (floatType ())
            , vSpec "integerDivide" [ ( "a", intType () ), ( "b", intType () ) ] (intType ())
            , vSpec "power" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
            , vSpec "toFloat" [ ( "a", intType () ) ] (floatType ())
            , vSpec "round" [ ( "a", floatType () ) ] (intType ())
            , vSpec "floor" [ ( "a", floatType () ) ] (intType ())
            , vSpec "ceiling" [ ( "a", floatType () ) ] (intType ())
            , vSpec "truncate" [ ( "a", floatType () ) ] (intType ())
            , vSpec "modBy" [ ( "a", intType () ), ( "b", intType () ) ] (intType ())
            , vSpec "remainderBy" [ ( "a", intType () ), ( "b", intType () ) ] (intType ())
            , vSpec "negate" [ ( "a", tVar "number" ) ] (tVar "number")
            , vSpec "abs" [ ( "a", tVar "number" ) ] (tVar "number")
            , vSpec "clamp" [ ( "a", tVar "number" ), ( "b", tVar "number" ), ( "c", tVar "number" ) ] (tVar "number")
            , vSpec "isNaN" [ ( "a", floatType () ) ] (boolType ())
            , vSpec "isInfinite" [ ( "a", floatType () ) ] (boolType ())
            , vSpec "sqrt" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "logBase" [ ( "a", floatType () ), ( "b", floatType () ) ] (floatType ())
            , vSpec "e" [] (floatType ())
            , vSpec "pi" [] (floatType ())
            , vSpec "cos" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "sin" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "tan" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "acos" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "asin" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "atan" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "atan2" [ ( "a", floatType () ), ( "b", floatType () ) ] (floatType ())
            , vSpec "degrees" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "radians" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "turns" [ ( "a", floatType () ) ] (floatType ())
            , vSpec "toPolar" [ ( "a", Type.Tuple () [ floatType (), floatType () ] ) ] (Type.Tuple () [ floatType (), floatType () ])
            , vSpec "fromPolar" [ ( "a", Type.Tuple () [ floatType (), floatType () ] ) ] (Type.Tuple () [ floatType (), floatType () ])

            -- eq
            , vSpec "equal" [ ( "a", tVar "eq" ), ( "b", tVar "eq" ) ] (boolType ())
            , vSpec "notEqual" [ ( "a", tVar "eq" ), ( "b", tVar "eq" ) ] (boolType ())

            -- comparable
            , vSpec "lessThan" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
            , vSpec "greaterThan" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
            , vSpec "lessThanOrEqual" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
            , vSpec "greaterThanOrEqual" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
            , vSpec "max" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (tVar "comparable")
            , vSpec "min" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (tVar "comparable")
            , vSpec "compare" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (orderType ())

            -- Bool
            , vSpec "not" [ ( "a", boolType () ) ] (boolType ())
            , vSpec "and" [ ( "a", boolType () ), ( "b", boolType () ) ] (boolType ())
            , vSpec "or" [ ( "a", boolType () ), ( "b", boolType () ) ] (boolType ())
            , vSpec "xor" [ ( "a", boolType () ), ( "b", boolType () ) ] (boolType ())

            -- appendable
            , vSpec "append" [ ( "a", tVar "appendable" ), ( "b", tVar "appendable" ) ] (tVar "appendable")

            -- break
            , vSpec "identity" [ ( "a", tVar "a" ) ] (tVar "a")
            , vSpec "always" [ ( "a", tVar "a" ), ( "b", tVar "b" ) ] (tVar "a")
            , vSpec "composeLeft" [ ( "g", tFun [ tVar "b" ] (tVar "c") ), ( "f", tFun [ tVar "a" ] (tVar "b") ) ] (tFun [ tVar "a" ] (tVar "c"))
            , vSpec "composeRight" [ ( "f", tFun [ tVar "a" ] (tVar "b") ), ( "g", tFun [ tVar "b" ] (tVar "c") ) ] (tFun [ tVar "a" ] (tVar "c"))
            , vSpec "never" [ ( "a", neverType () ) ] (tVar "a")
            ]
    }


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "not"
      , eval1 not (expectLiteral boolLiteral) (returnLiteral BoolLiteral)
      )
    , ( "and"
      , eval2 (&&) (expectLiteral boolLiteral) (expectLiteral boolLiteral) (returnLiteral BoolLiteral)
      )
    , ( "or"
      , eval2 (||) (expectLiteral boolLiteral) (expectLiteral boolLiteral) (returnLiteral BoolLiteral)
      )
    , ( "xor"
      , eval2 xor (expectLiteral boolLiteral) (expectLiteral boolLiteral) (returnLiteral BoolLiteral)
      )
    , ( "add"
      , oneOf
            [ eval2 (+) (expectLiteral intLiteral) (expectLiteral intLiteral) (returnLiteral IntLiteral)
            , eval2 (+) (expectLiteral floatLiteral) (expectLiteral floatLiteral) (returnLiteral FloatLiteral)
            ]
      )
    , ( "subtract"
      , oneOf
            [ eval2 (-) (expectLiteral intLiteral) (expectLiteral intLiteral) (returnLiteral IntLiteral)
            , eval2 (-) (expectLiteral floatLiteral) (expectLiteral floatLiteral) (returnLiteral FloatLiteral)
            ]
      )
    , ( "multiply"
      , oneOf
            [ eval2 (*) (expectLiteral intLiteral) (expectLiteral intLiteral) (returnLiteral IntLiteral)
            , eval2 (*) (expectLiteral floatLiteral) (expectLiteral floatLiteral) (returnLiteral FloatLiteral)
            ]
      )
    , ( "divide"
      , eval2 (/) (expectLiteral floatLiteral) (expectLiteral floatLiteral) (returnLiteral FloatLiteral)
      )
    , ( "integerDivide"
      , eval2 (//) (expectLiteral intLiteral) (expectLiteral intLiteral) (returnLiteral IntLiteral)
      )
    , ( "equal"
      , Native.binaryStrict
            (\arg1 arg2 ->
                -- We use structural equality similar to Elm with the difference that Elm fails when you try to compare
                -- two functions but we will actually compare if the implementations are the same.
                Ok (Value.Literal () (BoolLiteral (arg1 == arg2)))
            )
      )
    , ( "notEqual"
      , Native.binaryStrict
            (\arg1 arg2 ->
                -- We use structural equality similar to Elm with the difference that Elm fails when you try to compare
                -- two functions but we will actually compare if the implementations are the same.
                Ok (Value.Literal () (BoolLiteral (arg1 /= arg2)))
            )
      )
    , ( "lessThan"
      , oneOf
            -- TODO: this is only a limited subset of comparable values, we should implement for all
            [ eval2 (<) (expectLiteral intLiteral) (expectLiteral intLiteral) (returnLiteral BoolLiteral)
            , eval2 (<) (expectLiteral floatLiteral) (expectLiteral floatLiteral) (returnLiteral BoolLiteral)
            , eval2 (<) (expectLiteral charLiteral) (expectLiteral charLiteral) (returnLiteral BoolLiteral)
            , eval2 (<) (expectLiteral stringLiteral) (expectLiteral stringLiteral) (returnLiteral BoolLiteral)
            ]
      )
    , ( "greaterThan"
      , oneOf
            -- TODO: this is only a limited subset of comparable values, we should implement for all
            [ eval2 (>) (expectLiteral intLiteral) (expectLiteral intLiteral) (returnLiteral BoolLiteral)
            , eval2 (>) (expectLiteral floatLiteral) (expectLiteral floatLiteral) (returnLiteral BoolLiteral)
            , eval2 (>) (expectLiteral charLiteral) (expectLiteral charLiteral) (returnLiteral BoolLiteral)
            , eval2 (>) (expectLiteral stringLiteral) (expectLiteral stringLiteral) (returnLiteral BoolLiteral)
            ]
      )
    , ( "abs"
      , oneOf
            [ eval1 abs (expectLiteral intLiteral) (returnLiteral IntLiteral)
            , eval1 abs (expectLiteral floatLiteral) (returnLiteral FloatLiteral)
            ]
      )
    ]


orderType : a -> Type a
orderType attributes =
    Reference attributes (toFQName moduleName "Order") []


neverType : a -> Type a
neverType attributes =
    Reference attributes (toFQName moduleName "Never") []


equal : a -> Value ta a
equal a =
    Value.Reference a (toFQName moduleName "equal")


notEqual : a -> Value ta a
notEqual a =
    Value.Reference a (toFQName moduleName "notEqual")


boolType : a -> Type a
boolType attributes =
    Reference attributes (toFQName moduleName "Bool") []


and : a -> Value ta a
and a =
    Value.Reference a (toFQName moduleName "and")


or : a -> Value ta a
or a =
    Value.Reference a (toFQName moduleName "or")


negate : a -> a -> Value ta a -> Value ta a
negate refAttributes valueAttributes arg =
    Value.Apply valueAttributes (Value.Reference refAttributes (toFQName moduleName "negate")) arg


add : a -> Value ta a
add a =
    Value.Reference a (toFQName moduleName "add")


subtract : a -> Value ta a
subtract a =
    Value.Reference a (toFQName moduleName "subtract")


multiply : a -> Value ta a
multiply a =
    Value.Reference a (toFQName moduleName "multiply")


power : a -> Value ta a
power a =
    Value.Reference a (toFQName moduleName "power")


intType : a -> Type a
intType attributes =
    Reference attributes (toFQName moduleName "Int") []


integerDivide : a -> Value ta a
integerDivide a =
    Value.Reference a (toFQName moduleName "integerDivide")


floatType : a -> Type a
floatType attributes =
    Reference attributes (toFQName moduleName "Float") []


divide : a -> Value ta a
divide a =
    Value.Reference a (toFQName moduleName "divide")


lessThan : a -> Value ta a
lessThan a =
    Value.Reference a (toFQName moduleName "lessThan")


lessThanOrEqual : a -> Value ta a
lessThanOrEqual a =
    Value.Reference a (toFQName moduleName "lessThanOrEqual")


greaterThan : a -> Value ta a
greaterThan a =
    Value.Reference a (toFQName moduleName "greaterThan")


greaterThanOrEqual : a -> Value ta a
greaterThanOrEqual a =
    Value.Reference a (toFQName moduleName "greaterThanOrEqual")


composeLeft : a -> Value ta a
composeLeft a =
    Value.Reference a (toFQName moduleName "composeLeft")


composeRight : a -> Value ta a
composeRight a =
    Value.Reference a (toFQName moduleName "composeRight")


isNumber : Type ta -> Bool
isNumber tpe =
    case tpe of
        Reference a ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            True

        Reference a ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            True

        _ ->
            False


evaluateNumberArithmetic : Value () () -> Value () () -> String -> Result Error (Value () ())
evaluateNumberArithmetic num1 num2 operator =
    let
        evalNumber v1 v2 opr literal =
            case opr of
                "+" ->
                    v1 + v2 |> literal |> Value.Literal () |> Ok

                "-" ->
                    v1 - v2 |> literal |> Value.Literal () |> Ok

                "*" ->
                    v1 * v2 |> literal |> Value.Literal () |> Ok

                _ ->
                    Err (UnexpectedOperator opr)
    in
    case ( num1, num2 ) of
        ( Value.Literal _ (FloatLiteral v1), Value.Literal _ (FloatLiteral v2) ) ->
            evalNumber v1 v2 operator FloatLiteral

        ( Value.Literal _ (IntLiteral v1), Value.Literal _ (IntLiteral v2) ) ->
            evalNumber v1 v2 operator IntLiteral

        ( Value.Literal _ (FloatLiteral v1), Value.Literal _ (IntLiteral v2) ) ->
            evalNumber v1 (toFloat v2) operator FloatLiteral

        ( Value.Literal _ (IntLiteral v1), Value.Literal _ (FloatLiteral v2) ) ->
            evalNumber (toFloat v1) v2 operator FloatLiteral

        _ ->
            Err (ExpectedNumberTypeArguments [ num1, num2 ])


evaluateBooleanArithmetic : Value () () -> Value () () -> String -> Result Error (Value () ())
evaluateBooleanArithmetic num1 num2 operator =
    let
        evalBool v1 v2 opr =
            case opr of
                ">" ->
                    Ok (Value.Literal () (BoolLiteral (v1 > v2)))

                "<" ->
                    Ok (Value.Literal () (BoolLiteral (v1 < v2)))

                "=" ->
                    Ok (Value.Literal () (BoolLiteral (v1 == v2)))

                "/=" ->
                    Ok (Value.Literal () (BoolLiteral (v1 /= v2)))

                _ ->
                    Err (UnexpectedOperator opr)
    in
    case ( num1, num2 ) of
        ( Value.Literal _ (FloatLiteral v1), Value.Literal _ (FloatLiteral v2) ) ->
            evalBool v1 v2 operator

        ( Value.Literal _ (IntLiteral v1), Value.Literal _ (IntLiteral v2) ) ->
            evalBool v1 v2 operator

        ( Value.Literal _ (FloatLiteral v1), Value.Literal _ (IntLiteral v2) ) ->
            evalBool v1 (toFloat v2) operator

        ( Value.Literal _ (IntLiteral v1), Value.Literal _ (FloatLiteral v2) ) ->
            evalBool (toFloat v1) v2 operator

        ( Value.Literal _ (CharLiteral v1), Value.Literal _ (CharLiteral v2) ) ->
            evalBool v1 v2 operator

        ( Value.Literal _ (StringLiteral v1), Value.Literal _ (StringLiteral v2) ) ->
            evalBool v1 v2 operator

        _ ->
            Err (UnexpectedArguments [ num1, num2 ])
