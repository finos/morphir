module Morphir.Reference.Model.Issues.Issue571 exposing (..)


type alias Input =
    { flag : String
    }


topLevel : Input -> Int
topLevel input =
    if isFoo input then
        1

    else
        2


isFoo : Input -> Bool
isFoo input =
    input.flag == "foo"
