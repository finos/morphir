module Morphir.Reference.Model.Issues.Issue962 exposing (Foo, test)


type Foo
    = Foo String Bool


test foo =
    case foo of
        Foo s _ ->
            s
