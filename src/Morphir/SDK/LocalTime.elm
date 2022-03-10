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


module Morphir.SDK.LocalTime exposing
    ( fromMilliseconds
    , addHours
    , addMinutes
    , addSeconds
    , diffInHours
    , diffInMinutes
    , diffInSeconds
    , fromISO
    , LocalTime
    )

{-| This module adds the definition of basic time without time zones.


# Types

@docs LocalTime


# Time Math

@docs addHours
@docs addMinutes
@docs addSeconds
@docs diffInHours
@docs diffInMinutes
@docs diffInSeconds



# Constructors

@docs fromISO
@docs fromMilliseconds
-}

import Iso8601 exposing (toTime)
import Time exposing (Posix, millisToPosix, posixToMillis)


{-| Concept of time without time zones.
-}
type alias LocalTime =
    Posix


{-| Add the given hours to a given time
-}
addHours : Int -> LocalTime -> LocalTime
addHours hrs time =
    millisToPosix <|
        posixToMillis time
            + (3600000 * hrs)


{-| Add the given minutes to a given time.
-}
addMinutes : Int -> LocalTime -> LocalTime
addMinutes minutes time =
    millisToPosix <|
        posixToMillis time
            + (minutes * 60000)


{-| Add the given seconds to a given time.
-}
addSeconds : Int -> LocalTime -> LocalTime
addSeconds seconds time =
    millisToPosix <|
        posixToMillis time
            + (seconds * 1000)


{-| Find the difference of give times in hours
-}
diffInHours : LocalTime -> LocalTime -> Int
diffInHours timeA timeB =
    (posixToMillis timeA - posixToMillis timeB) // 3600000


{-| Find the difference of give times in minutes
-}
diffInMinutes : LocalTime -> LocalTime -> Int
diffInMinutes timeA timeB =
    (posixToMillis timeA - posixToMillis timeB) // 60000


{-| Find the difference of give times in minutes
-}
diffInSeconds : LocalTime -> LocalTime -> Int
diffInSeconds timeA timeB =
    (posixToMillis timeA - posixToMillis timeB) // 1000


{-| Construct a LocalTime based on ISO formatted string. Opportunity for error denoted by Maybe return type.
-}
fromISO : String -> Maybe LocalTime
fromISO iso =
    Result.toMaybe <|
        toTime iso


{-| Construct a LocalTime based on number of milliseconds from epoch. Opportunity for error denoted by Maybe return type.
-}
fromMilliseconds : Int -> LocalTime
fromMilliseconds millis =
    millisToPosix millis
