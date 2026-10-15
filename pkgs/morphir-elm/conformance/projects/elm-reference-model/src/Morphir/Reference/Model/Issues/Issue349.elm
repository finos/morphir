module Morphir.Reference.Model.Issues.Issue349 exposing (..)


type alias Result a =
    { foo : List a
    }


f : Result a
f =
    { foo =
        []
    }
