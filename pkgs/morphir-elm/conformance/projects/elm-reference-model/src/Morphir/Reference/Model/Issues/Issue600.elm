module Morphir.Reference.Model.Issues.Issue600 exposing (..)


foo : Int -> Int
foo a =
    let
        bar : Int -> Int -> Int -> Int
        bar c d e =
            e
    in
    bar 1 2 a
