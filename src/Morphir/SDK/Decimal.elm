module Morphir.SDK.Decimal exposing
    ( Decimal
    , fromInt
    , fromFloat
    , fromString
    , hundred
    , thousand
    , million
    , tenth
    , hundredth
    , thousandth
    , millionth
    , bps
    , toString
    , add
    , sub
    , negate
    , mul
    , div
    , divWithDefault
    , truncate
    , round
    , gt
    , gte
    , eq
    , neq
    , lt
    , lte
    , compare
    , abs, shiftDecimalLeft, shiftDecimalRight
    , zero
    , one
    , minusOne
    )

{-|


# The datatype

@docs Decimal


# Convert from

@docs fromInt
@docs fromFloat
@docs fromString


# Convert from known exponent

@docs hundred
@docs thousand
@docs million
@docs tenth
@docs hundredth
@docs thousandth
@docs millionth
@docs bps


# Convert to

@docs toString


# Arithmetic operations

@docs add
@docs sub
@docs negate
@docs mul
@docs div
@docs divWithDefault


# Rounding

@docs truncate
@docs round


# Comparing

@docs gt
@docs gte
@docs eq
@docs neq
@docs lt
@docs lte
@docs compare


# Misc operations

@docs abs, shiftDecimalLeft, shiftDecimalRight


# Common Constants

@docs zero
@docs one
@docs minusOne

-}

import Decimal as D


{-| The Decimal data type
-}
type alias Decimal =
    D.Decimal


{-| Converts an Int to a Decimal
-}
fromInt : Int -> Decimal
fromInt n =
    D.fromInt n


{-| Converts a Float to a Decimal
-}
fromFloat : Float -> Decimal
fromFloat f =
    let
        dec : D.Decimal
        dec =
            D.fromFloat f
    in
    if D.eq dec zero then
        zero

    else
        dec


{-| Converts an Int to a Decimal that represents n hundreds.
-}
hundred : Int -> Decimal
hundred n =
    D.fromInt (100 * n)


{-| Converts an Int to a Decimal that represents n thousands
-}
thousand : Int -> Decimal
thousand n =
    D.fromInt (1000 * n)


{-| Converts an Int to a Decimal that represents n millions.
-}
million : Int -> Decimal
million n =
    D.fromInt (n * 1000000)


{-| Converts an Int to a Decimal that represents n tenths.
-}
tenth : Int -> Decimal
tenth n =
    D.fromFloat (toFloat n * 0.1)


{-| Converts an Int to a Decimal that represents n hundredths.
-}
hundredth : Int -> Decimal
hundredth n =
    D.fromFloat (toFloat n * 0.01)


{-| Converts an Int to a Decimal that represents n thousandths.
-}
thousandth : Int -> Decimal
thousandth n =
    D.fromFloat (toFloat n * 0.001)


{-| Converts an Int to a Decimal that represents n basis points (i.e. 1/10 of % or a ten-thousandth
-}
bps : Int -> Decimal
bps n =
    D.fromFloat (toFloat n * 0.0001)


{-| Converts an Int to a Decimal that represents n millionth.
-}
millionth : Int -> Decimal
millionth n =
    D.fromFloat (toFloat n * 0.000001)


{-| Converts a String to a Maybe Decimal. The string shall be in the format [<sign>]<numbers>[.<numbers>][e<numbers>]
-}
fromString : String -> Maybe Decimal
fromString str =
    D.fromString str


{-| Converts a Decimal to a String
-}
toString : Decimal -> String
toString decimalValue =
    D.toString decimalValue


{-| Addition
-}
add : Decimal -> Decimal -> Decimal
add a b =
    D.add a b


{-| Subtraction
-}
sub : Decimal -> Decimal -> Decimal
sub a b =
    D.sub a b


{-| Multiplication
-}
mul : Decimal -> Decimal -> Decimal
mul a b =
    D.mul a b


{-| Divide two decimals
-}
div : Decimal -> Decimal -> Maybe Decimal
div a b =
    D.div a b


{-| Divide two decimals providing a default for the cases the calculation fails, such as divide by zero or overflow/underflow.
-}
divWithDefault : Decimal -> Decimal -> Decimal -> Decimal
divWithDefault default a b =
    div a b |> Maybe.withDefault default


{-| Shift the decimal n digits to the left.
-}
shiftDecimalLeft : Int -> Decimal -> Decimal
shiftDecimalLeft n value =
    fromFloat (10.0 ^ toFloat -n) |> mul value


{-| Shift the decimal n digits to the right.
-}
shiftDecimalRight : Int -> Decimal -> Decimal
shiftDecimalRight n value =
    10 ^ n |> fromInt |> mul value


{-| Changes the sign of a Decimal
-}
negate : Decimal -> Decimal
negate value =
    D.negate value


{-| Truncates the Decimal to the nearest integer with `TowardsZero` mode
-}
truncate : Decimal -> Decimal
truncate n =
    D.truncate n


{-| `round` to the nearest integer.
-}
round : Decimal -> Decimal
round n =
    D.round n


{-| Absolute value (sets the sign as positive)
-}
abs : Decimal -> Decimal
abs value =
    D.abs value


{-| Compares two Decimals
-}
compare : Decimal -> Decimal -> Order
compare a b =
    D.compare a b


{-| Equals
-}
eq : Decimal -> Decimal -> Bool
eq a b =
    D.eq a b


{-| Not equals
-}
neq : Decimal -> Decimal -> Bool
neq a b =
    not (eq a b)


{-| Greater than
-}
gt : Decimal -> Decimal -> Bool
gt a b =
    D.gt a b


{-| Greater than or equals
-}
gte : Decimal -> Decimal -> Bool
gte a b =
    D.gte a b


{-| Less than
-}
lt : Decimal -> Decimal -> Bool
lt a b =
    D.lt a b


{-| Less than or equals
-}
lte : Decimal -> Decimal -> Bool
lte a b =
    D.lte a b


{-| The number 0
-}
zero : Decimal
zero =
    D.fromInt 0


{-| The number 1
-}
one : Decimal
one =
    D.fromInt 1


{-| The number -1
-}
minusOne : Decimal
minusOne =
    D.fromInt -1
