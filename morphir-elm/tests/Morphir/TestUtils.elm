module Morphir.TestUtils exposing (..)

import Expect exposing (Expectation)


expectTrue : String -> Bool -> Expectation
expectTrue message actual =
    if actual == True then
        Expect.pass

    else
        Expect.fail message


expectFalse : String -> Bool -> Expectation
expectFalse message actual =
    if actual == False then
        Expect.pass

    else
        Expect.fail message
