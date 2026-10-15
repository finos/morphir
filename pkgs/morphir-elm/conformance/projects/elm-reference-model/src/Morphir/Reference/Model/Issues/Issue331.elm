module Morphir.Reference.Model.Issues.Issue331 exposing (..)


type MyType
    = MyType String String


foo : List String -> List MyType
foo list =
    List.map2 MyType list list
