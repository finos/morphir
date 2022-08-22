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
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (intType)
import Morphir.IR.SDK.Common exposing (toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type exposing (Specification(..), Type(..))
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
            [ ( Name.fromString "LocalDate", DerivedTypeSpecification [] config |> Documented "Type that represents a date concept." )
            ]
    , values =
        Dict.fromList
            [ vSpec "toISOString" [ ( "date", localDateType () ) ] (stringType ())
            , vSpec "fromISO" [ ( "iso", stringType () ) ] (maybeType () (localDateType ()))
            , vSpec "fromParts" [ ( "year", intType () ), ( "month", intType () ), ( "day", intType () ) ] (maybeType () (localDateType ()))
            , vSpec "diffInDays" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "diffInWeeks" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "diffInMonths" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "diffInYears" [ ( "date1", localDateType () ), ( "date2", localDateType () ) ] (intType ())
            , vSpec "addDays" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            , vSpec "addWeeks" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            , vSpec "addMonths" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            , vSpec "addYears" [ ( "offset", intType () ), ( "startDate", localDateType () ) ] (localDateType ())
            ]
    }


localDateType : a -> Type a
localDateType attributes =
    Reference attributes (toFQName moduleName "LocalDate") []


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "fromISO"
      , Native.eval1 LocalDate.fromISO (Native.decodeLiteral Native.stringLiteral) (Native.encodeMaybe Native.encodeLocalDate)
      )
    , ( "toISOString"
      , Native.eval1 LocalDate.toISOString Native.decodeLocalDate (Native.encodeLiteral Literal.StringLiteral)
      )
    ]
