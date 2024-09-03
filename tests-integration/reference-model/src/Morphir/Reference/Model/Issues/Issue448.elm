module Morphir.Reference.Model.Issues.Issue448 exposing (..)

import Morphir.SDK.Rule exposing (Rule, chain)


ruleSet : Rule Int String
ruleSet =
    chain []


apply : Int -> String
apply input =
    ruleSet input
        |> Maybe.withDefault "foo"
