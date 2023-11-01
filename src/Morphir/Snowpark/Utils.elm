module Morphir.Snowpark.Utils exposing (tryAlternatives)


tryAlternatives : List (() -> Maybe a) -> Maybe a
tryAlternatives cases =
   case cases of
       first::rest ->
            case first () of
                Just _ as result -> 
                    result
                _ ->
                    tryAlternatives rest
       [] -> 
            Nothing
