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


module Morphir.IR.Literal exposing (Literal(..), boolLiteral, charLiteral, stringLiteral, intLiteral, floatLiteral)

{-| Literals represent fixed values in the IR. We support the same set of basic types as Elm which almost matches JSON's supported values:

  - Bool
  - Char
  - String
  - Int
  - Float

@docs Literal, boolLiteral, charLiteral, stringLiteral, intLiteral, floatLiteral

-}
import Morphir.SDK.Decimal exposing (Decimal)
import Morphir.SDK.UUID exposing (UUID)



{-| Type that represents a literal value.
-}
type Literal
    = BoolLiteral Bool
    | CharLiteral Char
    | StringLiteral String
    | WholeNumberLiteral Int
    | FloatLiteral Float
    | DecimalLiteral Decimal


{-| Represents a boolean value. Only possible values are: `True`, `False`
-}
boolLiteral : Bool -> Literal
boolLiteral value =
    BoolLiteral value


{-| Represents a character value. Some possible values: `'a'`, `'Z'`, `'3'`
-}
charLiteral : Char -> Literal
charLiteral value =
    CharLiteral value


{-| Represents a string value. Some possible values: `""`, `"foo"`, `"Bar baz: 123"`
-}
stringLiteral : String -> Literal
stringLiteral value =
    StringLiteral value


{-| Represents an integer value. Some possible values: `0`, `-1`, `9832479`
-}
intLiteral : Int -> Literal
intLiteral value =
    WholeNumberLiteral value


{-| Represents a floating-point number. Some possible values: `1.25`, `-13.4`
-}
floatLiteral : Float -> Literal
floatLiteral value =
    FloatLiteral value
