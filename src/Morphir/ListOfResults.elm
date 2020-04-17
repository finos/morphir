module Morphir.ListOfResults exposing (liftAllErrors, liftFirstError)


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


liftFirstError : List (Result e a) -> Result e (List a)
liftFirstError results =
    case liftAllErrors results of
        Ok a ->
            Ok a

        Err errors ->
            errors
                |> List.head
                |> Maybe.map Err
                |> Maybe.withDefault (Ok [])
