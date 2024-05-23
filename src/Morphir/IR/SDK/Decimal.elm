module Morphir.IR.SDK.Decimal exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, encodeOrder, floatType, intType, orderType)
import Morphir.IR.SDK.Common exposing (toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.SDK.Decimal as Decimal
import Morphir.Value.Native as Native exposing (decimalLiteral, decodeLiteral, encodeLiteral, encodeMaybe, eval0, eval1, eval2, eval3)


moduleName : ModuleName
moduleName =
    Path.fromString "Decimal"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Decimal", OpaqueTypeSpecification [] |> Documented "Type that represents a Decimal." )
            ]
    , values =
        Dict.fromList
            [ vSpec "fromInt" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "fromFloat" [ ( "f", floatType () ) ] (decimalType ())
            , vSpec "fromString" [ ( "str", stringType () ) ] (maybeType () (decimalType ()))
            , vSpec "hundred" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "thousand" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "million" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "tenth" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "hundredth" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "thousandth" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "millionth" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "bps" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "toString" [ ( "decimalValue", decimalType () ) ] (stringType ())
            , vSpec "toFloat" [ ( "d", decimalType () ) ] (floatType ())
            , vSpec "add" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (decimalType ())
            , vSpec "sub" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (decimalType ())
            , vSpec "negate" [ ( "value", decimalType () ) ] (decimalType ())
            , vSpec "mul" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (decimalType ())
            , vSpec "div" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (maybeType () (decimalType ()))
            , vSpec "divWithDefault" [ ( "default", decimalType () ), ( "a", decimalType () ), ( "b", decimalType () ) ] (decimalType ())
            , vSpec "truncate" [ ( "d", decimalType () ) ] (decimalType ())
            , vSpec "round" [ ( "d", decimalType () ) ] (decimalType ())
            , vSpec "gt" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (boolType ())
            , vSpec "gte" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (boolType ())
            , vSpec "eq" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (boolType ())
            , vSpec "neq" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (boolType ())
            , vSpec "lt" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (boolType ())
            , vSpec "lte" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (boolType ())
            , vSpec "compare" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (orderType ())
            , vSpec "abs" [ ( "value", decimalType () ) ] (decimalType ())
            , vSpec "shiftDecimalLeft" [ ( "n", intType () ), ( "value", decimalType () ) ] (decimalType ())
            , vSpec "shiftDecimalRight" [ ( "n", intType () ), ( "value", decimalType () ) ] (decimalType ())
            , vSpec "zero" [] (decimalType ())
            , vSpec "one" [] (decimalType ())
            , vSpec "minusOne" [] (decimalType ())
            ]
    , doc = Just "Contains the Decimal type representing a real number with some decimal precision, and it's associated functions."
    }


decimalType : a -> Type a
decimalType attributes =
    Reference attributes (toFQName moduleName "Decimal") []


roundingModeType : a -> Type a
roundingModeType attributes =
    Reference attributes (toFQName moduleName "RoundingMode") []


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "fromInt"
      , eval1 Decimal.fromInt (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "toString"
      , eval1 Decimal.toString (decodeLiteral decimalLiteral) (encodeLiteral StringLiteral)
      )
    , ( "fromFloat"
      , eval1 Decimal.fromFloat (decodeLiteral Native.floatLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "hundred"
      , eval1 Decimal.hundred (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "thousand"
      , eval1 Decimal.thousand (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "million"
      , eval1 Decimal.million (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "hundredth"
      , eval1 Decimal.hundredth (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "thousandth"
      , eval1 Decimal.thousandth (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "millionth"
      , eval1 Decimal.millionth (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "tenth"
      , eval1 Decimal.millionth (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "bps"
      , eval1 Decimal.bps (decodeLiteral Native.intLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "add"
      , eval2 Decimal.add (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "sub"
      , eval2 Decimal.sub (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "negate"
      , eval1 Decimal.negate (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "mul"
      , eval2 Decimal.mul (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "div"
      , eval2 Decimal.div (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeMaybe <| encodeLiteral DecimalLiteral)
      )
    , ( "divWithDefault"
      , eval3 Decimal.divWithDefault (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "truncate"
      , eval1 Decimal.truncate (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "round"
      , eval1 Decimal.round (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "gt"
      , eval2 Decimal.gt (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "gte"
      , eval2 Decimal.gte (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "eq"
      , eval2 Decimal.eq (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "neq"
      , eval2 Decimal.neq (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "lt"
      , eval2 Decimal.lt (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "lte"
      , eval2 Decimal.lte (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeLiteral BoolLiteral)
      )
    , ( "compare"
      , eval2 Decimal.compare (decodeLiteral decimalLiteral) (decodeLiteral decimalLiteral) (encodeOrder >> Ok)
      )
    , ( "abs"
      , eval1 Decimal.abs (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "shiftDecimalLeft"
      , eval2 Decimal.shiftDecimalLeft (decodeLiteral Native.intLiteral) (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "shiftDecimalRight"
      , eval2 Decimal.shiftDecimalRight (decodeLiteral Native.intLiteral) (decodeLiteral decimalLiteral) (encodeLiteral DecimalLiteral)
      )
    , ( "zero"
      , eval0 Decimal.zero (encodeLiteral DecimalLiteral)
      )
    , ( "one"
      , eval0 Decimal.one (encodeLiteral DecimalLiteral)
      )
    , ( "minusOne"
      , eval0 Decimal.minusOne (encodeLiteral DecimalLiteral)
      )
    ]
