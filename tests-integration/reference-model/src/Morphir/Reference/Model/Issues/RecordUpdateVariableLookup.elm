module Morphir.Reference.Model.Issues.RecordUpdateVariableLookup exposing (..)


type alias Foo = 
    { test : Int
    }

foo : Foo
foo =
    { test = 1 }


bar : Foo
bar =
    { foo | test = 2 }    