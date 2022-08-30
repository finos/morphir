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


module TestUtils exposing (..)


import Expect exposing (Expectation)
import Test exposing (..)


executeTest : String -> Result x a -> (a -> b) -> (b -> s) -> Test
executeTest testName inputData testFunction outputToString =
    let
        testOutput : Result x b
        testOutput =
            inputData
                |> Result.map testFunction

        outputText =
            testOutput
                |> Result.map outputToString
        _ =
            Debug.log ("expected_results_" ++ testName ++ ".csv") outputText
    in
    test
        ("Testing " ++ testName)
        (\_ -> Expect.ok outputText)
