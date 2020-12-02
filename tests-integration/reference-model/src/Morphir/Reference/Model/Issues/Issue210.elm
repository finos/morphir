module Morphir.Reference.Model.Issues.Issue210 exposing (..)

import Set exposing (Set)


foo : Set String
foo =
    Set.fromList
        [ "a"
        , "b"
        , "c"
        ]


isFoo : String -> Bool
isFoo s =
    Set.member s foo
