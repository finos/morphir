module Morphir.SDK.ResultList exposing
    ( ResultList
    , fromList
    , filter, filterOrFail, map, mapOrFail
    , errors, successes, partition
    , keepAllErrors, keepFirstError
    )

{-| This module contains operations that are specific to lists of results. These operations are very useful for modeling
processing pipelines where errors could happen at any point in the pipeline but they should not break the processing
itself.

@docs ResultList


# Creating

@docs fromList


# Processing

@docs filter, filterOrFail, map, mapOrFail


# Decomposing

@docs errors, successes, partition


# Mapping to single result

@docs keepAllErrors, keepFirstError

-}


{-| Type that represents a list that contains a mix of failed and successful records.
-}
type alias ResultList e a =
    List (Result e a)


{-| Create a result list from any list.

    fromList [ 1, 2, 3 ] == [ Ok 1, Ok 2, Ok 3 ]

-}
fromList : List a -> ResultList e a
fromList list =
    list
        |> List.map Ok


{-| Extract all errors from the result list.

    errors [ Ok 1, Ok 2, Ok 3, Ok 4 ] == []

    errors [ Ok 1, Err "foo", Ok 3, Err "bar" ] == [ Err "foo", Err "bar" ]

    errors [ Err "foo", Err "bar" ] == [ Err "foo", Err "bar" ]

-}
errors : ResultList e a -> List e
errors resultList =
    resultList
        |> List.filterMap
            (\result ->
                case result of
                    Err e ->
                        Just e

                    Ok _ ->
                        Nothing
            )


{-| Extract all successes from the result list.

    successes [ Ok 1, Ok 2, Ok 3, Ok 4 ] == [ Ok 1, Ok 2, Ok 3, Ok 4 ]

    successes [ Ok 1, Err "foo", Ok 3, Err "bar" ] == [ Ok 1, Ok 3 ]

    successes [ Err "foo", Err "bar" ] == []

-}
successes : ResultList e a -> List a
successes resultList =
    resultList
        |> List.filterMap
            (\result ->
                case result of
                    Ok a ->
                        Just a

                    Err _ ->
                        Nothing
            )


{-| Partition a result list into errors and successes.

    partition [ Ok 1, Ok 2, Ok 3, Ok 4 ] == ( [], [ Ok 1, Ok 2, Ok 3, Ok 4 ] )

    partition [ Ok 1, Err "foo", Ok 3, Err "bar" ] == ( [ Err "foo", Err "bar" ], [ Ok 1, Ok 3 ] )

    partition [ Err "foo", Err "bar" ] == ( [ Err "foo", Err "bar" ], [] )

-}
partition : ResultList e a -> ( List e, List a )
partition resultList =
    resultList
        |> List.foldr
            (\next ( errs, oks ) ->
                case next of
                    Ok ok ->
                        ( errs, ok :: oks )

                    Err err ->
                        ( err :: errs, oks )
            )
            ( [], [] )


{-| Filter a result list retaining all previously failed items.

    filter isOdd [ Ok 1, Ok 2, Ok 3 ] == [ Ok 1, Ok 3 ]

    filter isOdd [ Err "foo", Ok 2, Ok 3 ] == [ Err "foo", Ok 3 ]

-}
filter : (a -> Bool) -> ResultList e a -> ResultList e a
filter f resultList =
    resultList
        |> List.filter
            (\result ->
                case result of
                    Ok a ->
                        f a

                    Err _ ->
                        True
            )


{-| Filter a result list retaining all previously failed items.

    divide a =
        if a == 0 then
            Err "division by zero"

        else
            isOdd a

    filterOrFail divide [ Ok -1, Ok 0, Err "earlier", Ok 2 ] == [ Ok -1, Err "division by zero", Err "earlier" ]

-}
filterOrFail : (a -> Result e Bool) -> ResultList e a -> ResultList e a
filterOrFail f resultList =
    resultList
        |> List.filterMap
            (\result ->
                case result of
                    Ok a ->
                        case f a of
                            Ok True ->
                                Just (Ok a)

                            Ok False ->
                                Nothing

                            Err e ->
                                Just (Err e)

                    Err e ->
                        Just (Err e)
            )


{-| Map a result list retaining all previously failed items.

    map double [ Ok 1, Ok 2, Ok 3 ] == [ Ok 2, Ok 4, Ok 6 ]

    map isOdd [ Err "foo", Ok 2, Ok 3 ] == [ Err "foo", Ok 4, Ok 6 ]

-}
map : (a -> b) -> ResultList e a -> ResultList e b
map f resultList =
    resultList
        |> List.map (Result.map f)


{-| Map a result list retaining all previously failed items.

    divide a =
        if a == 0 then
            Err "division by zero"

        else
            Ok (100 / a)

    mapOrFail divide [ Ok -1, Ok 0, Err "earlier" ] == [ Ok -100, Err "division by zero", Err "earlier" ]

-}
mapOrFail : (a -> Result e b) -> ResultList e a -> ResultList e b
mapOrFail f resultList =
    resultList
        |> List.map (Result.andThen f)


{-| Turn a list of results into a single result keeping all errors.
-}
keepAllErrors : ResultList e a -> Result (List e) (List a)
keepAllErrors results =
    let
        oks : List a
        oks =
            results
                |> List.filterMap
                    (\result ->
                        result
                            |> Result.toMaybe
                    )

        errs : List e
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


{-| Turn a list of results into a single result keeping only the first error.
-}
keepFirstError : ResultList e a -> Result e (List a)
keepFirstError results =
    case keepAllErrors results of
        Ok a ->
            Ok a

        Err errs ->
            errs
                |> List.head
                |> Maybe.map Err
                |> Maybe.withDefault (Ok [])
