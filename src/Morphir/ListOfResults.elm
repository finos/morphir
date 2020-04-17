module Morphir.ListOfResults exposing (liftLastError, reduce, toResultOfList)


reduce : (List a -> b) -> List (Result e a) -> Result e b
reduce f results =
    let
        oks =
            results
                |> List.filterMap
                    (\result ->
                        result
                            |> Result.toMaybe
                    )

        errs =
            results
                |> List.filterMap
                    (\result ->
                        case result of
                            Ok _ ->
                                Nothing

                            Err e ->
                                Just e
                    )
    in
    case errs of
        [] ->
            Ok (f oks)

        firstError :: _ ->
            Err firstError


toResultOfList : List (Result e a) -> Result (List e) (List a)
toResultOfList results =
    let
        oks =
            results
                |> List.filterMap
                    (\result ->
                        result
                            |> Result.toMaybe
                    )

        errs =
            results
                |> List.filterMap
                    (\result ->
                        case result of
                            Ok _ ->
                                Nothing

                            Err e ->
                                Just e
                    )
    in
    case errs of
        [] ->
            Ok oks

        _ ->
            Err errs


{-| Turn a list of results into a single result of a list returning only the last error in the list.
-}
liftLastError : List (Result e a) -> Result e (List a)
liftLastError results =
    List.foldr (Result.map2 (::)) (Ok []) results
