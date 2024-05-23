module Morphir.SDK.Number exposing
    ( Number(..)
    , fromInt
    , equal, notEqual, lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual
    , add, subtract, multiply, divide, abs, negate, reciprocal
    , toFractionalString, toDecimal, coerceToDecimal
    , simplify, isSimplified
    , zero, one
    )

{-| This module provides a way to represent a number without the risk of rounding issues or division by zero for any of
the basic operations: `+`, `-`, `*`, `/`. More accurately a `Number` represents an arbitrary-precision rational number.
If you need irrational numbers please use a `Float`.

@docs Number


# Convert from

@docs fromInt


# Comparison

@docs equal, notEqual, lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual


# Arithmetic

@docs add, subtract, multiply, divide, abs, negate, reciprocal


# Convert to

@docs toFractionalString, toDecimal, coerceToDecimal


# Misc

@docs simplify, isSimplified


# Constants

@docs zero, one

-}

import BigInt as BigInt exposing (BigInt)
import Morphir.SDK.Decimal as Decimal exposing (Decimal)


{-| Represents an arbitrary-precision rational number.
-}
type Number
    = Rational BigInt BigInt


type DivisionByZero
    = DivisionByZero


{-| Create a Number by converting it from an Int
-}
fromInt : Int -> Number
fromInt int =
    Rational (BigInt.fromInt int) (BigInt.fromInt 1)


{-| Turn a number into a decimal.
NOTE: it is possible for this operation to fail if the Number is a rational number for 0.
-}
toDecimal : Number -> Maybe Decimal
toDecimal (Rational nominator denominator) =
    let
        div_ ( n, d ) =
            Decimal.div n d
    in
    Maybe.map2
        Tuple.pair
        (nominator |> BigInt.toString |> Decimal.fromString)
        (denominator |> BigInt.toString |> Decimal.fromString)
        |> Maybe.andThen div_


{-| Turn a number into a decimal, by providing a default value in the case things go awry.
-}
coerceToDecimal : Decimal -> Number -> Decimal
coerceToDecimal default (Rational nominator denominator) =
    Maybe.map2
        (Decimal.divWithDefault default)
        (nominator |> BigInt.toString |> Decimal.fromString)
        (denominator |> BigInt.toString |> Decimal.fromString)
        |> Maybe.withDefault default


{-| Checks if two numbers are equal.

    equal one one == True

    equal one (divide ten ten) == True

    equal one zero == False

-}
equal : Number -> Number -> Bool
equal =
    compareWith (==)


{-| Checks if two numbers are not equal.

    notEqual one zero == True

    notEqual zero one == True

    notEqual one one == False

-}
notEqual : Number -> Number -> Bool
notEqual =
    compareWith (/=)


{-| Checks if the first number is less than the second
-}
lessThan : Number -> Number -> Bool
lessThan =
    compareWith BigInt.lt


{-| Checks if the first number is less than or equal to the second
-}
lessThanOrEqual : Number -> Number -> Bool
lessThanOrEqual =
    compareWith BigInt.lte


{-| Checks if the first number is greater than the second
-}
greaterThan : Number -> Number -> Bool
greaterThan =
    compareWith BigInt.gt


{-| Checks if the first number is greater or equal than the second
-}
greaterThanOrEqual : Number -> Number -> Bool
greaterThanOrEqual =
    compareWith BigInt.gte


compareWith : (BigInt -> BigInt -> a) -> Number -> Number -> a
compareWith f (Rational a b) (Rational c d) =
    f
        (BigInt.mul a d)
        (BigInt.mul b c)


{-| Negate the given number, thus flipping the sign.
-}
negate : Number -> Number
negate (Rational a b) =
    Rational
        (BigInt.negate a)
        b


{-| Takes the absolute value of the number
-}
abs : Number -> Number
abs (Rational a b) =
    Rational
        (BigInt.abs a)
        (BigInt.abs b)


{-| Calculates the reciprocal of the number
-}
reciprocal : Number -> Number
reciprocal ((Rational nominator denominator) as number) =
    if isZero number then
        number

    else
        Rational
            denominator
            nominator


{-| Adds two numbers together.
-}
add : Number -> Number -> Number
add (Rational a b) (Rational c d) =
    Rational
        (BigInt.add
            (BigInt.mul a d)
            (BigInt.mul b c)
        )
        (BigInt.mul b d)


{-| Subtracts one number from the other.
-}
subtract : Number -> Number -> Number
subtract (Rational a b) (Rational c d) =
    Rational
        (BigInt.sub
            (BigInt.mul a d)
            (BigInt.mul b c)
        )
        (BigInt.mul b d)


{-| Multiplies two numbers together
-}
multiply : Number -> Number -> Number
multiply (Rational a b) (Rational c d) =
    Rational
        (BigInt.mul a c)
        (BigInt.mul b d)


{-| Division
-}
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


gcd : BigInt -> BigInt -> Maybe BigInt
gcd a b =
    let
        zero_ =
            BigInt.fromInt 0

        gcd_ x maybeY =
            case maybeY of
                Nothing ->
                    Nothing

                Just y ->
                    if y == zero_ then
                        Just x

                    else
                        gcd_ y (BigInt.modBy y x)
    in
    gcd_ (BigInt.abs a) (BigInt.abs b |> Just)


{-| Tries to simplify the number.
-}
simplify : Number -> Maybe Number
simplify (Rational numerator denominator) =
    let
        zero_ =
            BigInt.fromInt 0

        denominatorIsZero =
            bigIntsAreEqual denominator zero_
    in
    if denominatorIsZero then
        Nothing

    else
        let
            commonFactor =
                gcd numerator denominator

            reducedNumerator =
                commonFactor
                    |> Maybe.andThen (\gcf -> BigInt.divmod numerator gcf |> Maybe.map Tuple.first)

            reducedDenominator =
                commonFactor
                    |> Maybe.andThen (\gcf -> BigInt.divmod denominator gcf |> Maybe.map Tuple.first)
        in
        Maybe.map2 Rational reducedNumerator reducedDenominator


{-| Tells if the number is simplified
-}
isSimplified : Number -> Bool
isSimplified ((Rational originalNumerator originalDenominator) as num) =
    case simplify num of
        Nothing ->
            True

        Just (Rational numerator denominator) ->
            bigIntsAreEqual originalNumerator numerator && bigIntsAreEqual originalDenominator denominator


{-| Create a fractional representation of the number
-}
toFractionalString : Number -> String
toFractionalString (Rational numerator denominator) =
    BigInt.toString numerator ++ "/" ++ BigInt.toString denominator


isZero : Number -> Bool
isZero (Rational nominator _) =
    nominator == BigInt.fromInt 0


{-| Constant for 0
-}
zero : Number
zero =
    Rational (BigInt.fromInt 0) (BigInt.fromInt 1)


{-| Constant for one
-}
one : Number
one =
    Rational (BigInt.fromInt 1) (BigInt.fromInt 1)


ten : Number
ten =
    Rational (BigInt.fromInt 10) (BigInt.fromInt 1)


bigIntsAreEqual : BigInt -> BigInt -> Bool
bigIntsAreEqual a b =
    case BigInt.compare a b of
        EQ ->
            True

        _ ->
            False


bigIntIsZero : BigInt -> Bool
bigIntIsZero n =
    bigIntsAreEqual (BigInt.fromInt 0) n
