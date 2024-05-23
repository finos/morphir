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


module Morphir.IR.SDK.Basics exposing (add, and, append, boolType, composeLeft, composeRight, divide, encodeOrder, equal, floatType, greaterThan, greaterThanOrEqual, intType, integerDivide, isNumber, lessThan, lessThanOrEqual, moduleName, moduleSpec, multiply, nativeFunctions, negate, neverType, notEqual, or, orderType, power, subtract)

import Dict exposing (Dict)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native exposing (boolLiteral, decodeList, decodeLiteral, decodeRaw, encodeList, encodeLiteral, encodeRaw, eval1, eval2, eval3, floatLiteral, intLiteral, oneOf, stringLiteral)
import Morphir.Value.Native.Comparable as Comparable exposing (compareValue, max, min)
import Morphir.Value.Native.Eq as Eq


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
    , doc = Just "Types and functions representing basic mathematical concepts and operations"
    }


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "not"
      , eval1 not (decodeLiteral boolLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "and"
      , eval2 (&&) (decodeLiteral boolLiteral) (decodeLiteral boolLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "or"
      , eval2 (||) (decodeLiteral boolLiteral) (decodeLiteral boolLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "xor"
      , eval2 xor (decodeLiteral boolLiteral) (decodeLiteral boolLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "add"
      , oneOf
            [ eval2 (+) (decodeLiteral intLiteral) (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
            , eval2 (+) (decodeLiteral floatLiteral) (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "subtract"
      , oneOf
            [ eval2 (-) (decodeLiteral intLiteral) (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
            , eval2 (-) (decodeLiteral floatLiteral) (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "multiply"
      , oneOf
            [ eval2 (*) (decodeLiteral intLiteral) (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
            , eval2 (*) (decodeLiteral floatLiteral) (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "divide"
      , eval2 (/) (decodeLiteral floatLiteral) (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
      )
    , ( "integerDivide"
      , eval2 (//) (decodeLiteral intLiteral) (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
      )
    , ( "power"
      , oneOf
            [ eval2 (^) (decodeLiteral intLiteral) (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
            , eval2 (^) (decodeLiteral floatLiteral) (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "equal"
      , Native.binaryStrict
            (\arg1 arg2 ->
                -- We use structural equality similar to Elm with the difference that Elm fails when you try to compare
                -- two functions but we will actually compare if the implementations are the same.
                Eq.equal arg1 arg2 |> Result.map (\bool -> Value.Literal () (BoolLiteral bool))
            )
      )
    , ( "notEqual"
      , Native.binaryStrict
            (\arg1 arg2 ->
                -- We use structural equality similar to Elm with the difference that Elm fails when you try to compare
                -- two functions but we will actually compare if the implementations are the same.
                Eq.notEqual arg1 arg2 |> Result.map (\bool -> Value.Literal () (BoolLiteral bool))
            )
      )
    , ( "identity"
      , Native.unaryStrict
            (\arg1 -> arg1)
      )
    , ( "always"
      , Native.binaryStrict
            (\arg1 _ -> Ok arg1)
      )
    , ( "never"
      , \eval args ->
            Err (UnexpectedArguments args)
      )
    , ( "composeLeft"
      , \eval args ->
            case args of
                [ fun1, fun2, arg1 ] ->
                    eval
                        (Value.Apply ()
                            fun2
                            arg1
                        )
                        |> Result.andThen
                            (\arg2 ->
                                eval
                                    (Value.Apply ()
                                        fun1
                                        arg2
                                    )
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "composeRight"
      , \eval args ->
            case args of
                [ fun1, fun2, arg1 ] ->
                    eval
                        (Value.Apply ()
                            fun1
                            arg1
                        )
                        |> Result.andThen
                            (\arg2 ->
                                eval
                                    (Value.Apply ()
                                        fun2
                                        arg2
                                    )
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "lessThan"
      , Native.binaryStrict
            (\arg1 arg2 ->
                Comparable.lessThan arg1 arg2 |> Result.map (\bool -> Value.Literal () (BoolLiteral bool))
            )
      )
    , ( "greaterThan"
      , Native.binaryStrict
            (\arg1 arg2 ->
                Comparable.greaterThan arg1 arg2 |> Result.map (\bool -> Value.Literal () (BoolLiteral bool))
            )
      )
    , ( "lessThanOrEqual"
      , Native.binaryStrict
            (\arg1 arg2 ->
                Comparable.lessThanOrEqual arg1 arg2 |> Result.map (\bool -> Value.Literal () (BoolLiteral bool))
            )
      )
    , ( "greaterThanOrEqual"
      , Native.binaryStrict
            (\arg1 arg2 ->
                Comparable.greaterThanOrEqual arg1 arg2 |> Result.map (\bool -> Value.Literal () (BoolLiteral bool))
            )
      )
    , ( "abs"
      , oneOf
            [ eval1 abs (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
            , eval1 abs (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "toFloat"
      , oneOf
            [ eval1 toFloat (decodeLiteral intLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "negate"
      , oneOf
            [ eval1 Basics.negate (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
            , eval1 Basics.negate (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "clamp"
      , oneOf
            [ eval3 Basics.clamp (decodeLiteral intLiteral) (decodeLiteral intLiteral) (decodeLiteral intLiteral) (encodeLiteral WholeNumberLiteral)
            , eval3 Basics.clamp (decodeLiteral floatLiteral) (decodeLiteral floatLiteral) (decodeLiteral floatLiteral) (encodeLiteral FloatLiteral)
            ]
      )
    , ( "max"
      , Native.binaryStrict
            (\arg1 arg2 ->
                Comparable.max arg1 arg2
            )
      )
    , ( "min"
      , Native.binaryStrict
            (\arg1 arg2 ->
                Comparable.min arg1 arg2
            )
      )
    , ( "append"
      , oneOf
            [ eval2 (++) (decodeLiteral stringLiteral) (decodeLiteral stringLiteral) (encodeLiteral StringLiteral)
            , eval2 (++) (decodeList decodeRaw) (decodeList decodeRaw) (encodeList encodeRaw)
            ]
      )
    , ( "compare"
      , Native.binaryStrict
            (\arg1 arg2 ->
                compareValue arg1 arg2
                    |> Result.map encodeOrder
            )
      )
    ]


encodeOrder : Order -> Value () ()
encodeOrder =
    \order ->
        let
            val =
                case order of
                    GT ->
                        "GT"

                    LT ->
                        "LT"

                    EQ ->
                        "EQ"
        in
        Value.Constructor () (toFQName moduleName val)


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


append : a -> Value ta a
append a =
    Value.Reference a (toFQName moduleName "append")


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
        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            True

        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            True

        _ ->
            False
