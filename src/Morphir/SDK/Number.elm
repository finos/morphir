module Morphir.SDK.Number exposing
    ( Number(..)
    , equal, notEqual
    , add, divide, fromInt, zero
    )

{-| This module provides a way to represent a number without the risk of rounding issues or division by zero for any of
the basic operations: `+`, `-`, `*`, `/`. More accurately a `Number` represents an arbitrary-precision rational number.
If you need irrational numbers please use a `Float`.

@docs Number


# Comparison

@docs equal, notEqual

-}

import BigInt exposing (BigInt)
import Decimal as D
import Morphir.SDK.Decimal exposing (Decimal)


{-| Represents an arbitrary-precision rational number.
-}
type Number
    = Rational BigInt BigInt


type DivisionByZero
    = DivisionByZero


fromInt : Int -> Number
fromInt int =
    Rational (BigInt.fromInt int) (BigInt.fromInt 1)


{-| Turn a number into a decimal.
-}
toDecimal : Number -> Decimal
toDecimal (Rational nominator denominator) =
    Maybe.map2
        (/)
        (nominator |> BigInt.toString |> String.toFloat)
        (denominator |> BigInt.toString |> String.toFloat)
        |> Maybe.andThen Morphir.SDK.Decimal.fromFloat
        |> Maybe.withDefault (Morphir.SDK.Decimal.fromInt 0)


{-| Checks if two numbers are equal.

    equal one one == True

    equal one (divide ten ten) == True

    equal one zero == False

-}
equal : Number -> Number -> Bool
equal =
    compareWith (==)


notEqual : Number -> Number -> Bool
notEqual =
    compareWith (/=)


lessThan : Number -> Number -> Bool
lessThan =
    compareWith BigInt.lt


lessThanOrEqual : Number -> Number -> Bool
lessThanOrEqual =
    compareWith BigInt.lte


greaterThan : Number -> Number -> Bool
greaterThan =
    compareWith BigInt.gt


greaterThanOrEqual : Number -> Number -> Bool
greaterThanOrEqual =
    compareWith BigInt.gte


compareWith : (BigInt -> BigInt -> a) -> Number -> Number -> a
compareWith f (Rational a b) (Rational c d) =
    f
        (BigInt.mul a d)
        (BigInt.mul b c)


negate : Number -> Number
negate (Rational a b) =
    Rational
        (BigInt.negate a)
        b


reciprocal : Number -> Number
reciprocal ((Rational nominator denominator) as number) =
    if isZero number then
        number

    else
        Rational
            denominator
            nominator


add : Number -> Number -> Number
add (Rational a b) (Rational c d) =
    Rational
        (BigInt.add
            (BigInt.mul a d)
            (BigInt.mul b c)
        )
        (BigInt.mul b d)


subtract : Number -> Number -> Number
subtract (Rational a b) (Rational c d) =
    Rational
        (BigInt.sub
            (BigInt.mul a d)
            (BigInt.mul b c)
        )
        (BigInt.mul b d)


multiply : Number -> Number -> Number
multiply (Rational a b) (Rational c d) =
    Rational
        (BigInt.mul a c)
        (BigInt.mul b d)


divide : Number -> Number -> Result DivisionByZero Number
divide (Rational a b) ((Rational c d) as denominator) =
    if isZero denominator then
        Err DivisionByZero

    else
        Ok
            (Rational
                (BigInt.mul a d)
                (BigInt.mul b c)
            )


isZero : Number -> Bool
isZero (Rational nominator _) =
    nominator == BigInt.fromInt 0


zero : Number
zero =
    Rational (BigInt.fromInt 0) (BigInt.fromInt 1)


one : Number
one =
    Rational (BigInt.fromInt 1) (BigInt.fromInt 1)


ten : Number
ten =
    Rational (BigInt.fromInt 10) (BigInt.fromInt 1)
