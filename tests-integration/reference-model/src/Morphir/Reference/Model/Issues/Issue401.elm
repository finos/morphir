module Morphir.Reference.Model.Issues.Issue401 exposing (..)


type alias Foo =
    { field : String
    }


foo : Foo -> Bool
foo ldTrade =
    ldTrade.field == "foo"


bar : Foo -> String
bar ldTrade =
    if foo ldTrade then
        ""

    else
        ""
