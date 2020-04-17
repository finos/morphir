module Morphir.ListOfResults exposing (liftAllErrors, reduce)


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


liftAllErrors : List (Result e a) -> Result (List e) (List a)
liftAllErrors results =
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
