module Morphir.IR.SDK.Decimal exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType, orderType)
import Morphir.IR.SDK.Common exposing (toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type exposing (Specification(..), Type(..))


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
            , vSpec "millionth" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "bps" [ ( "n", intType () ) ] (decimalType ())
            , vSpec "toString" [ ( "decimalValue", decimalType () ) ] (stringType ())
            , vSpec "toFloat" [ ( "d", decimalType () ) ] (floatType ())
            , vSpec "add" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (decimalType ())
            , vSpec "sub" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (decimalType ())
            , vSpec "negate" [ ( "value", decimalType () ) ] (decimalType ())
            , vSpec "mul" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (decimalType ())
            , vSpec "div" [ ( "a", decimalType () ), ( "b", decimalType () ) ] (maybeType () (decimalType ()))
            , vSpec "divWithDefault" [ ( "default", decimalType () ), ( "a", decimalType () ), ( "b", decimalType () ) ] (maybeType () (decimalType ()))
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
    }


decimalType : a -> Type a
decimalType attributes =
    Reference attributes (toFQName moduleName "Decimal") []


roundingModeType : a -> Type a
roundingModeType attributes =
    Reference attributes (toFQName moduleName "RoundingMode") []
