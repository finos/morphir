module Morphir.Reference.Model.Issues.Issue969 exposing (..)


identity : a -> a
identity a =
    a


map : (a -> a) -> a -> a
map f v =
    f v


useMap : String -> String
useMap str =
    map identity str


apply : List (Maybe Float) -> List Float
apply strings =
    strings
        |> List.filterMap identity
