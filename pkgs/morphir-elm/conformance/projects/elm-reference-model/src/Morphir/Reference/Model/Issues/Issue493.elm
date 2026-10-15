module Morphir.Reference.Model.Issues.Issue493 exposing (functionString, functionString2)


functionString : String -> String
functionString myStr =
    String.trim (functionString2 myStr)


functionString2 : String -> String
functionString2 temp =
    temp
