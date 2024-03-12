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


module Morphir.IR.SDK.LocalDate exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal as Literal
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.Common exposing (toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)
import Morphir.SDK.LocalDate as LocalDate
import Morphir.Value.Native as Native


moduleName : ModuleName
moduleName =
    Path.fromString "LocalDate"


config =
    { baseType = stringType ()
    , toBaseType = toFQName moduleName "toISOString"
    , fromBaseType = toFQName moduleName "fromISO"
    }


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "LocalDate"
              , DerivedTypeSpecification [] config
                    |> Documented "Type that represents a date concept."
              )
            , ( Name.fromString "DayOfWeek"
              , CustomTypeSpecification []
                    (Dict.fromList
                        [ ( Name.fromString "Monday", [] )
                        , ( Name.fromString "Tuesday", [] )
                        , ( Name.fromString "Wednesday", [] )
                        , ( Name.fromString "Thursday", [] )
                        , ( Name.fromString "Friday", [] )
                        , ( Name.fromString "Saturday", [] )
                        , ( Name.fromString "Sunday", [] )
                        ]
                    )
                    |> Documented "Type that represents days of the week."
              )
            , ( Name.fromString "Month"
              , CustomTypeSpecification []
                    (Dict.fromList
                        [ ( Name.fromString "January", [] )
                        , ( Name.fromString "February", [] )
                        , ( Name.fromString "March", [] )
                        , ( Name.fromString "April", [] )
                        , ( Name.fromString "May", [] )
                        , ( Name.fromString "June", [] )
                        , ( Name.fromString "July", [] )
                        , ( Name.fromString "August", [] )
                        , ( Name.fromString "September", [] )
                        , ( Name.fromString "October", [] )
                        , ( Name.fromString "November", [] )
                        , ( Name.fromString "December", [] )
                        ]
                    )
                    |> Documented "Type that represents months of the year."
              )
            ]
    , values =
        Dict.fromList
            [ vSpec "fromCalendarDate" [ ( "y", intType () ), ( "m", monthType () ), ( "d", intType () ) ] (localDateType ())
            , vSpec "toISOString" [ ( "date", localDateType () ) ] (stringType ())
            , vSpec "fromISO" [ ( "iso", stringType () ) ] (maybeType () (localDateType ()))
            , vSpec "fromOrdinalDate" [ ( "y", intType () ), ( "dayOfyear", intType () ) ] (localDateType ())
            , vSpec "fromParts" [ ( "year", intType () ), ( "month", intType () ), ( "day", intType () ) ] (maybeType () (localDateType ()))
            , vSpec "day" [ ( "localDate", localDateType () ) ] (intType ())
            , vSpec "dayOfWeek" [ ( "localDate", localDateType () ) ] (dayOfWeekType ())
            , vSpec "diffInDays" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "diffInWeeks" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "diffInMonths" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "diffInYears" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "addDays" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            , vSpec "addWeeks" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            , vSpec "addMonths" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            , vSpec "addYears" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            , vSpec "isWeekend" [ ( "localDate", localDateType () ) ] (boolType ())
            , vSpec "isWeekday" [ ( "localDate", localDateType () ) ] (boolType ())
            , vSpec "month" [ ( "localDate", localDateType () ) ] (monthType ())
            , vSpec "monthNumber" [ ( "localDate", localDateType () ) ] (intType ())
            , vSpec "monthToInt" [ ( "m", monthType () ) ] (intType ())
            , vSpec "year" [ ( "localDate", localDateType () ) ] (intType ())
            ]
    , doc = Just "Contains the LocalDate type (representing a date concept), and it's associated functions."
    }


dayOfWeekType : a -> Type a
dayOfWeekType attributes =
    Reference attributes (toFQName moduleName "DayOfWeek") []


localDateType : a -> Type a
localDateType attributes =
    Reference attributes (toFQName moduleName "LocalDate") []


monthType : a -> Type a
monthType attributes =
    Reference attributes (toFQName moduleName "Month") []


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "fromISO"
      , Native.eval1 LocalDate.fromISO (Native.decodeLiteral Native.stringLiteral) (Native.encodeMaybe Native.encodeLocalDate)
      )
    , ( "toISOString"
      , Native.eval1 LocalDate.toISOString Native.decodeLocalDate (Native.encodeLiteral Literal.StringLiteral)
      )
    , ( "fromParts"
      , Native.eval3 LocalDate.fromParts
            (Native.decodeLiteral Native.intLiteral)
            (Native.decodeLiteral Native.intLiteral)
            (Native.decodeLiteral Native.intLiteral)
            (Native.encodeMaybe Native.encodeLocalDate)
      )
    , ( "diffInDays"
      , Native.eval2 LocalDate.diffInDays Native.decodeLocalDate Native.decodeLocalDate (Native.encodeLiteral Literal.intLiteral)
      )
    , ( "diffInWeeks"
      , Native.eval2 LocalDate.diffInWeeks Native.decodeLocalDate Native.decodeLocalDate (Native.encodeLiteral Literal.intLiteral)
      )
    , ( "diffInMonths"
      , Native.eval2 LocalDate.diffInMonths Native.decodeLocalDate Native.decodeLocalDate (Native.encodeLiteral Literal.intLiteral)
      )
    , ( "diffInYears"
      , Native.eval2 LocalDate.diffInYears Native.decodeLocalDate Native.decodeLocalDate (Native.encodeLiteral Literal.intLiteral)
      )
    , ( "addDays"
      , Native.eval2 LocalDate.addDays (Native.decodeLiteral Native.intLiteral) Native.decodeLocalDate Native.encodeLocalDate
      )
    , ( "addWeeks"
      , Native.eval2 LocalDate.addWeeks (Native.decodeLiteral Native.intLiteral) Native.decodeLocalDate Native.encodeLocalDate
      )
    , ( "addMonths"
      , Native.eval2 LocalDate.addMonths (Native.decodeLiteral Native.intLiteral) Native.decodeLocalDate Native.encodeLocalDate
      )
    , ( "addYears"
      , Native.eval2 LocalDate.addYears (Native.decodeLiteral Native.intLiteral) Native.decodeLocalDate Native.encodeLocalDate
      )
    ]


fromISO : a -> Value a a -> Value a a
fromISO a value =
    Value.Apply a (Value.Reference a ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "from", "i", "s", "o" ] )) value
