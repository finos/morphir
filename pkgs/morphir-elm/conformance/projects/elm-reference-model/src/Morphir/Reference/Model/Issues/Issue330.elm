module Morphir.Reference.Model.Issues.Issue330 exposing (..)


type MyType
    = MyType String


toString : MyType -> String
toString (MyType v) =
    v


bar : String
bar =
    toString (MyType "bar")
