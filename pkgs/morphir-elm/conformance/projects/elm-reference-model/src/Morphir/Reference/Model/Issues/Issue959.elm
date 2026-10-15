module Morphir.Reference.Model.Issues.Issue959 exposing (..)


type alias Foo =
    { field1 : Maybe String
    }


foo : Foo
foo =
    Foo Nothing
