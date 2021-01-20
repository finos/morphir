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
    , millionth
    , bps
    , toString
    , toFloat
    , add
    , sub
    , negate
    , mul
    , truncate
    , round
    , gt
    , gte
    , eq
    , neq
    , lt
    , lte
    , compare
    , abs
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
@docs millionth
@docs bps


# Convert to

@docs toString
@docs toFloat


# Arithmetic operations

@docs add
@docs sub
@docs negate
@docs mul


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

@docs abs


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
fromFloat : Float -> Maybe Decimal
fromFloat f =
    D.fromFloat f


{-| Converts an Int to a Decimal that represents n hundreds.
-}
hundred : Int -> Decimal
hundred n =
    D.fromIntWithExponent n 2


{-| Converts an Int to a Decimal that represents n thousands
-}
thousand : Int -> Decimal
thousand n =
    D.fromIntWithExponent n 3


{-| Converts an Int to a Decimal that represents n millions.
-}
million : Int -> Decimal
million n =
    D.fromIntWithExponent n 6


{-| Converts an Int to a Decimal that represents n tenths.
-}
tenth : Int -> Decimal
tenth n =
    D.fromIntWithExponent n -1


{-| Converts an Int to a Decimal that represents n hundredths.
-}
hundredth : Int -> Decimal
hundredth n =
    D.fromIntWithExponent n -2


{-| Converts an Int to a Decimal that represents n basis points (i.e. 1/10 of % or a ten-thousandth
-}
bps : Int -> Decimal
bps n =
    D.fromIntWithExponent n -4


millionth : Int -> Decimal
millionth n =
    D.fromIntWithExponent n -6


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


{-| Converts a Decimal to a Float
-}
toFloat : Decimal -> Float
toFloat d =
    D.toFloat d


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


{-| Changes the sign of a Decimal
-}
negate : Decimal -> Decimal
negate value =
    D.negate value


{-| Truncates the Decimal to the specified decimal places
-}
truncate : Int -> Decimal -> Decimal
truncate n d =
    D.truncate n d


{-| Rounds the Decimal to the specified decimal places
-}
round : Int -> Decimal -> Decimal
round n d =
    D.round n d


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
    D.zero


{-| The number 1
-}
one : Decimal
one =
    D.one


{-| The number -1
-}
minusOne : Decimal
minusOne =
    D.minusOne
