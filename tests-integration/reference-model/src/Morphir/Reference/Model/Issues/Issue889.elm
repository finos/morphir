module Morphir.Reference.Model.Issues.Issue889 exposing (..)


type alias Foo =
    { bar : Int
    }


foo : Foo
foo =
    let
        a =
            True
    in
    { bar = 1
    }
