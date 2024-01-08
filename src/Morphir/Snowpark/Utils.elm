module Morphir.Snowpark.Utils exposing (collectMaybeList, tryAlternatives)


tryAlternatives : List (() -> Maybe a) -> Maybe a
tryAlternatives cases =
    case cases of
        first :: rest ->
            case first () of
                (Just _) as result ->
                    result

                _ ->
                    tryAlternatives rest

        [] ->
            Nothing


collectMaybeList : (a -> Maybe b) -> List a -> Maybe (List b)
collectMaybeList action aList =
    collectMaybeListAux action aList []


collectMaybeListAux : (a -> Maybe b) -> List a -> List b -> Maybe (List b)
collectMaybeListAux action aList current =
    case aList of
        first :: rest ->
            action first
                |> Maybe.map (\newFirst -> collectMaybeListAux action rest (newFirst :: current))
                |> Maybe.withDefault Nothing

        [] ->
            Just (List.reverse current)
