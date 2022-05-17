module Morphir.Reference.Model.Sample.DataDefinition.Field.SubProduct exposing (..)


type alias SubProduct =
    String


isSameAsCategory : SubProduct -> Bool
isSameAsCategory subProduct =
    subProduct == "Same Category"
