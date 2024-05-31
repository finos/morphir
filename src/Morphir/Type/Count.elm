module Morphir.Type.Count exposing (..)


type Count a
    = Count (Int -> ( Int, a ))


apply : Int -> Count a -> ( Int, a )
apply seed (Count counter) =
    counter seed


one : (Int -> a) -> Count a
one f =
    Count
        (\counter ->
            ( counter + 1, f counter )
        )


oneOrReuse : Maybe Int -> (Int -> a) -> Count a
oneOrReuse maybeReuse f =
    Count
        (\counter ->
            case maybeReuse of
                Just reuse ->
                    ( counter, f reuse )

                Nothing ->
                    ( counter + 1, f counter )
        )


two : (Int -> Int -> a) -> Count a
two f =
    Count
        (\counter ->
            ( counter + 2, f counter (counter + 1) )
        )


three : (Int -> Int -> Int -> a) -> Count a
three f =
    Count
        (\counter ->
            ( counter + 3, f counter (counter + 1) (counter + 2) )
        )


none : a -> Count a
none a =
    Count
        (\counter ->
            ( counter, a )
        )


map : (a -> b) -> Count a -> Count b
map f (Count indexerA) =
    Count
        (\index ->
            let
                ( indexA, a ) =
                    indexerA index
            in
            ( indexA, f a )
        )


map2 : (a -> b -> c) -> Count a -> Count b -> Count c
map2 f (Count indexerA) (Count indexerB) =
    Count
        (\index ->
            let
                ( indexA, a ) =
                    indexerA index

                ( indexB, b ) =
                    indexerB indexA
            in
            ( indexB, f a b )
        )


map3 : (a -> b -> c -> d) -> Count a -> Count b -> Count c -> Count d
map3 f (Count indexerA) (Count indexerB) (Count indexerC) =
    Count
        (\index ->
            let
                ( indexA, a ) =
                    indexerA index

                ( indexB, b ) =
                    indexerB indexA

                ( indexC, c ) =
                    indexerC indexB
            in
            ( indexC, f a b c )
        )


all : List (Count a) -> Count (List a)
all counters =
    Count
        (\counter ->
            counters
                |> List.foldr
                    (\(Count nextCounter) ( counterSoFar, itemsSoFar ) ->
                        let
                            ( nextCount, nextItem ) =
                                nextCounter counterSoFar
                        in
                        ( nextCount, nextItem :: itemsSoFar )
                    )
                    ( counter, [] )
        )


andThen : (a -> Count b) -> Count a -> Count b
andThen f (Count counterA) =
    Count
        (\counter ->
            let
                ( nextCount, a ) =
                    counterA counter

                (Count counterB) =
                    f a
            in
            counterB nextCount
        )
