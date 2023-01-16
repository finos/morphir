module Morphir.IR.SDK.Number exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType, orderType)
import Morphir.IR.SDK.Common exposing (toFQName, vSpec)
import Morphir.IR.SDK.Decimal exposing (decimalType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.Result exposing (resultType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModuleName
moduleName =
    Path.fromString "Number"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Decimal", OpaqueTypeSpecification [] |> Documented "Type that represents a Decimal." )
            ]
    , values =
        Dict.fromList
            [ vSpec "fromInt" [ ( "n", intType () ) ] (numberType ())
            , vSpec "equal" [ ( "a", numberType () ), ( "b", numberType () ) ] (boolType ())
            , vSpec "notEqual" [ ( "a", numberType () ), ( "b", numberType () ) ] (boolType ())
            , vSpec "lessThan" [ ( "a", numberType () ), ( "b", numberType () ) ] (boolType ())
            , vSpec "lessThanOrEqual" [ ( "a", numberType () ), ( "b", numberType () ) ] (boolType ())
            , vSpec "greaterThan" [ ( "a", numberType () ), ( "b", numberType () ) ] (boolType ())
            , vSpec "greaterThanOrEqual" [ ( "a", numberType () ), ( "b", numberType () ) ] (boolType ())
            , vSpec "add" [ ( "a", numberType () ), ( "b", numberType () ) ] (numberType ())
            , vSpec "subtract" [ ( "a", numberType () ), ( "b", numberType () ) ] (numberType ())
            , vSpec "multiply" [ ( "a", numberType () ), ( "b", numberType () ) ] (numberType ())
            , vSpec "divide" [ ( "a", numberType () ), ( "b", numberType () ) ] (resultType () (divisionByZeroType ()) (numberType ()))
            , vSpec "abs" [ ( "value", numberType () ) ] (numberType ())
            , vSpec "negate" [ ( "value", numberType () ) ] (numberType ())
            , vSpec "reciprocal" [ ( "value", numberType () ) ] (numberType ())
            , vSpec "coerceToDecimal" [ ( "default", decimalType () ), ( "number", numberType () ) ] (decimalType ())
            , vSpec "toDecimal" [ ( "number", numberType () ) ] (maybeType () (decimalType ()))
            , vSpec "toFractionalString" [ ( "num", numberType () ) ] (stringType ())
            , vSpec "simplify" [ ( "value", numberType () ) ] (maybeType () (numberType ()))
            , vSpec "isSimplified" [ ( "a", numberType () ) ] (boolType ())
            , vSpec "zero" [] (numberType ())
            , vSpec "one" [] (numberType ())
            ]
    , doc = Just "The Decimal number type and associated functions."
    }


numberType : a -> Type a
numberType attributes =
    Reference attributes (toFQName moduleName "Number") []


divisionByZeroType : a -> Type a
divisionByZeroType attributes =
    Reference attributes (toFQName moduleName "DivisionByZero") []
