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


module TestIsItemAntique exposing (..)

import CsvUtils exposing (antiqueEncoder)
import AntiquesDataSource exposing (antiquesDataSource)
import SparkTests.Rules.Income.Antique exposing (is_item_antique)
import TestUtils exposing (executeTest)
import Test exposing (Test)

testIsItemAntique : Test
testIsItemAntique = executeTest "is_item_antique" antiquesDataSource (List.filter is_item_antique) antiqueEncoder

