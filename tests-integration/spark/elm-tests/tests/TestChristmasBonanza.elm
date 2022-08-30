{-
   Copyright 2022 Morgan Stanley

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


module TestChristmasBonanza exposing (..)

import AntiquesDataSource exposing (antiquesDataSource)
import SparkTests.Rules.Income.Antique exposing (christmas_bonanza_15percent_priceRange)
import TestUtils exposing (executeTest)
import Test exposing (Test)

-- lazy csv export - We know the output's a single tuple so we mangle it into a csv using sed later.
testChristmasBonanza : Test
testChristmasBonanza = executeTest "christmas_bonanza_15percent_priceRange" antiquesDataSource christmas_bonanza_15percent_priceRange (\a -> a)
