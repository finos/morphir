module Morphir.Reference.Model.Issues.Issue450 exposing (..)


bar : List Int -> (Int -> Bool) -> List Int
bar list filter =
    list
        |> List.filter filter
