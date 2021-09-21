module Morphir.Reference.Model.SDK.String exposing (..)

import String


isDigit : Char -> Bool
isDigit value =
    if value >= '0' && value <= '9' then
        True

    else
        False


stringAll : String -> Bool
stringAll value =
    String.all isDigit value


stringMap : String -> String
stringMap value =
    String.map
        (\c ->
            if c == '/' then
                '.'

            else
                c
        )
        value


stringFoldL : String -> String -> String
stringFoldL x input =
    String.foldl String.cons x input


stringFoldR : String -> String -> String
stringFoldR x input =
    String.foldr String.cons x input
