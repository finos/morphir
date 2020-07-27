module Morphir.SDK.List exposing
    ( singleton, repeat, range, cons
    , map, indexedMap, foldl, foldr, filter, filterMap
    , length, reverse, member, all, any, maximum, minimum, sum, product
    , append, concat, concatMap, intersperse, map2, map3, map4, map5
    , sort, sortBy, sortWith
    , isEmpty, head, tail, take, drop, partition, unzip
    , last, init
    , innerJoin, leftJoin, rightJoin
    )

{-| This module is an extension of the `List` module in `elm/core`. It includes all functions from `elm/core` so that
you can use it without changing existing code. Simply add the following import to use:

    import Morphir.SDK.List as List

You can create a `List` in Elm with the `[1,2,3]` syntax, so lists are
used all over the place. This module has a bunch of functions to help you work
with them!


# Create

@docs singleton, repeat, range, cons


# Transform

@docs map, indexedMap, foldl, foldr, filter, filterMap


# Utilities

@docs length, reverse, member, all, any, maximum, minimum, sum, product


# Combine

@docs append, concat, concatMap, intersperse, map2, map3, map4, map5


# Sort

@docs sort, sortBy, sortWith


# Deconstruct

@docs isEmpty, head, tail, take, drop, partition, unzip
@docs last, init


# Joins

@docs innerJoin, leftJoin, rightJoin

-}

-- CREATE


{-| Create a list with only one element:
singleton 1234 == [1234]
singleton "hi" == ["hi"]
-}
singleton : a -> List a
singleton value =
    List.singleton value


{-| Create a list with _n_ copies of a value:
repeat 3 (0,0) == [(0,0),(0,0),(0,0)]
-}
repeat : Int -> a -> List a
repeat n value =
    List.repeat n value


{-| Create a list of numbers, every element increasing by one.
You give the lowest and highest number that should be in the list.
range 3 6 == [3, 4, 5, 6]
range 3 3 == [3]
range 6 3 == []
-}
range : Int -> Int -> List Int
range lo hi =
    List.range lo hi


{-| Add an element to the front of a list.
1 :: [2,3] == [1,2,3]
1 :: [] == [1]
This operator is pronounced _cons_ for historical reasons, but you can think
of it like pushing an entry onto a stack.
-}
cons : a -> List a -> List a
cons =
    (::)



-- TRANSFORM


{-| Apply a function to every element of a list.
map sqrt [1,4,9] == [1,2,3]
map not [True,False,True] == [False,True,False]
So `map func [ a, b, c ]` is the same as `[ func a, func b, func c ]`
-}
map : (a -> b) -> List a -> List b
map f xs =
    List.map f xs


{-| Same as `map` but the function is also applied to the index of each
element (starting at zero).
indexedMap Tuple.pair ["Tom","Sue","Bob"] == [ (0,"Tom"), (1,"Sue"), (2,"Bob") ]
-}
indexedMap : (Int -> a -> b) -> List a -> List b
indexedMap f xs =
    List.indexedMap f xs


{-| Reduce a list from the left.
foldl (+) 0 [1,2,3] == 6
foldl (::) [][1,2,3] == [3,2,1]
So `foldl step state [1,2,3]` is like saying:
state
|> step 1
|> step 2
|> step 3
-}
foldl : (a -> b -> b) -> b -> List a -> b
foldl func acc list =
    List.foldl func acc list


{-| Reduce a list from the right.
foldr (+) 0 [1,2,3] == 6
foldr (::) [][1,2,3] == [1,2,3]
So `foldr step state [1,2,3]` is like saying:
state
|> step 3
|> step 2
|> step 1
-}
foldr : (a -> b -> b) -> b -> List a -> b
foldr fn acc ls =
    List.foldr fn acc ls


{-| Keep elements that satisfy the test.
filter isEven [1,2,3,4,5,6] == [2,4,6]
-}
filter : (a -> Bool) -> List a -> List a
filter isGood list =
    List.filter isGood list


{-| Filter out certain values. For example, maybe you have a bunch of strings
from an untrusted source and you want to turn them into numbers:
numbers : List Int
numbers =
filterMap String.toInt ["3", "hi", "12", "4th", "May"]
-- numbers == [3, 12]
-}
filterMap : (a -> Maybe b) -> List a -> List b
filterMap f xs =
    List.filterMap f xs


maybeCons : (a -> Maybe b) -> a -> List b -> List b
maybeCons f mx xs =
    case f mx of
        Just x ->
            cons x xs

        Nothing ->
            xs



-- UTILITIES


{-| Determine the length of a list.
length [1,2,3] == 3
-}
length : List a -> Int
length xs =
    foldl (\_ i -> i + 1) 0 xs


{-| Reverse a list.
reverse [1,2,3,4] == [4,3,2,1]
-}
reverse : List a -> List a
reverse list =
    foldl cons [] list


{-| Figure out whether a list contains a value.
member 9 [1,2,3,4] == False
member 4 [1,2,3,4] == True
-}
member : a -> List a -> Bool
member x xs =
    any (\a -> a == x) xs


{-| Determine if all elements satisfy some test.
all isEven [2,4] == True
all isEven [2,3] == False
all isEven [] == True
-}
all : (a -> Bool) -> List a -> Bool
all isOkay list =
    not (any (not << isOkay) list)


{-| Determine if any elements satisfy some test.
any isEven [2,3] == True
any isEven [1,3] == False
any isEven [] == False
-}
any : (a -> Bool) -> List a -> Bool
any isOkay list =
    case list of
        [] ->
            False

        x :: xs ->
            -- note: (isOkay x || any isOkay xs) would not get TCO
            if isOkay x then
                True

            else
                any isOkay xs


{-| Find the maximum element in a non-empty list.
maximum [1,4,2] == Just 4
maximum [] == Nothing
-}
maximum : List comparable -> Maybe comparable
maximum list =
    case list of
        x :: xs ->
            Just (foldl max x xs)

        _ ->
            Nothing


{-| Find the minimum element in a non-empty list.
minimum [3,2,1] == Just 1
minimum [] == Nothing
-}
minimum : List comparable -> Maybe comparable
minimum list =
    case list of
        x :: xs ->
            Just (foldl min x xs)

        _ ->
            Nothing


{-| Get the sum of the list elements.
sum [1,2,3] == 6
sum [1,1,1] == 3
sum [] == 0
-}
sum : List number -> number
sum numbers =
    foldl (+) 0 numbers


{-| Get the product of the list elements.
product [2,2,2] == 8
product [3,3,3] == 27
product [] == 1
-}
product : List number -> number
product numbers =
    foldl (*) 1 numbers



-- COMBINE


{-| Put two lists together.
append [1,1,2][3,5,8] == [1,1,2,3,5,8]
append ['a','b']['c'] == ['a','b','c']
You can also use [the `(++)` operator](Basics#++) to append lists.
-}
append : List a -> List a -> List a
append xs ys =
    case ys of
        [] ->
            xs

        _ ->
            foldr cons ys xs


{-| Concatenate a bunch of lists into a single list:
concat [[1,2],[3],[4,5]] == [1,2,3,4,5]
-}
concat : List (List a) -> List a
concat lists =
    foldr append [] lists


{-| Map a given function onto a list and flatten the resulting lists.
concatMap f xs == concat (map f xs)
-}
concatMap : (a -> List b) -> List a -> List b
concatMap f list =
    concat (map f list)


{-| Places the given value between all members of the given list.
intersperse "on" ["turtles","turtles","turtles"] == ["turtles","on","turtles","on","turtles"]
-}
intersperse : a -> List a -> List a
intersperse sep xs =
    case xs of
        [] ->
            []

        hd :: tl ->
            let
                step x rest =
                    cons sep (cons x rest)

                spersed =
                    foldr step [] tl
            in
            cons hd spersed


{-| Combine two lists, combining them with the given function.
If one list is longer, the extra elements are dropped.
totals : List Int -> List Int -> List Int
totals xs ys =
List.map2 (+) xs ys
-- totals [1,2,3][4,5,6] == [5,7,9]
pairs : List a -> List b -> List (a,b)
pairs xs ys =
List.map2 Tuple.pair xs ys
-- pairs ["alice","bob","chuck"][2,5,7,8]
-- == [("alice",2),("bob",5),("chuck",7)]
-}
map2 : (a -> b -> result) -> List a -> List b -> List result
map2 =
    Elm.Kernel.List.map2


{-| -}
map3 : (a -> b -> c -> result) -> List a -> List b -> List c -> List result
map3 =
    Elm.Kernel.List.map3


{-| -}
map4 : (a -> b -> c -> d -> result) -> List a -> List b -> List c -> List d -> List result
map4 =
    Elm.Kernel.List.map4


{-| -}
map5 : (a -> b -> c -> d -> e -> result) -> List a -> List b -> List c -> List d -> List e -> List result
map5 =
    Elm.Kernel.List.map5



-- SORT


{-| Sort values from lowest to highest
sort [3,1,5] == [1,3,5]
-}
sort : List comparable -> List comparable
sort xs =
    sortBy identity xs


{-| Sort values by a derived property.
alice = { name="Alice", height=1.62 }
bob = { name="Bob" , height=1.85 }
chuck = { name="Chuck", height=1.76 }
sortBy .name [chuck,alice,bob] == [alice,bob,chuck]
sortBy .height [chuck,alice,bob] == [alice,chuck,bob]
sortBy String.length ["mouse","cat"] == ["cat","mouse"]
-}
sortBy : (a -> comparable) -> List a -> List a
sortBy =
    Elm.Kernel.List.sortBy


{-| Sort values with a custom comparison function.
sortWith flippedComparison [1,2,3,4,5] == [5,4,3,2,1]
flippedComparison a b =
case compare a b of
LT -> GT
EQ -> EQ
GT -> LT
This is also the most general sort function, allowing you
to define any other: `sort == sortWith compare`
-}
sortWith : (a -> a -> Order) -> List a -> List a
sortWith =
    Elm.Kernel.List.sortWith



-- DECONSTRUCT


{-| Determine if a list is empty.
isEmpty [] == True
**Note:** It is usually preferable to use a `case` to test this so you do not
forget to handle the `(x :: xs)` case as well!
-}
isEmpty : List a -> Bool
isEmpty xs =
    case xs of
        [] ->
            True

        _ ->
            False


{-| Extract the first element of a list.
head [1,2,3] == Just 1
head [] == Nothing
**Note:** It is usually preferable to use a `case` to deconstruct a `List`
because it gives you `(x :: xs)` and you can work with both subparts.
-}
head : List a -> Maybe a
head list =
    case list of
        x :: xs ->
            Just x

        [] ->
            Nothing


{-| Extract the rest of the list.
tail [1,2,3] == Just [2,3]
tail [] == Nothing
**Note:** It is usually preferable to use a `case` to deconstruct a `List`
because it gives you `(x :: xs)` and you can work with both subparts.
-}
tail : List a -> Maybe (List a)
tail list =
    case list of
        x :: xs ->
            Just xs

        [] ->
            Nothing


{-| Take the first _n_ members of a list.
take 2 [1,2,3,4] == [1,2]
-}
take : Int -> List a -> List a
take n list =
    takeFast 0 n list


takeFast : Int -> Int -> List a -> List a
takeFast ctr n list =
    if n <= 0 then
        []

    else
        case ( n, list ) of
            ( _, [] ) ->
                list

            ( 1, x :: _ ) ->
                [ x ]

            ( 2, x :: y :: _ ) ->
                [ x, y ]

            ( 3, x :: y :: z :: _ ) ->
                [ x, y, z ]

            ( _, x :: y :: z :: w :: tl ) ->
                if ctr > 1000 then
                    cons x (cons y (cons z (cons w (takeTailRec (n - 4) tl))))

                else
                    cons x (cons y (cons z (cons w (takeFast (ctr + 1) (n - 4) tl))))

            _ ->
                list


takeTailRec : Int -> List a -> List a
takeTailRec n list =
    reverse (takeReverse n list [])


takeReverse : Int -> List a -> List a -> List a
takeReverse n list kept =
    if n <= 0 then
        kept

    else
        case list of
            [] ->
                kept

            x :: xs ->
                takeReverse (n - 1) xs (cons x kept)


{-| Drop the first _n_ members of a list.
drop 2 [1,2,3,4] == [3,4]
-}
drop : Int -> List a -> List a
drop n list =
    if n <= 0 then
        list

    else
        case list of
            [] ->
                list

            x :: xs ->
                drop (n - 1) xs


{-| Partition a list based on some test. The first list contains all values
that satisfy the test, and the second list contains all the value that do not.
partition (\\x -> x < 3) [0,1,2,3,4,5] == ([0,1,2], [3,4,5])
partition isEven [0,1,2,3,4,5] == ([0,2,4], [1,3,5])
-}
partition : (a -> Bool) -> List a -> ( List a, List a )
partition pred list =
    let
        step x ( trues, falses ) =
            if pred x then
                ( cons x trues, falses )

            else
                ( trues, cons x falses )
    in
    foldr step ( [], [] ) list


{-| Decompose a list of tuples into a tuple of lists.

    unzip [ ( 0, True ), ( 17, False ), ( 1337, True ) ] == ( [ 0, 17, 1337 ], [ True, False, True ] )

-}
unzip : List ( a, b ) -> ( List a, List b )
unzip pairs =
    let
        step ( x, y ) ( xs, ys ) =
            ( cons x xs, cons y ys )
    in
    foldr step ( [], [] ) pairs


{-| Returns the last element of a list.

    last [ 1, 2, 3 ] == Just 3

    last [] == Nothing

-}
last : List a -> Maybe a
last list =
    list
        |> List.reverse
        |> List.head


{-| Returns all elements of a list except for the last.

    init [ 1, 2, 3 ] == Just [ 1, 2 ]

    init [] == Nothing

-}
init : List a -> Maybe (List a)
init list =
    list
        |> List.reverse
        |> List.tail
        |> Maybe.map List.reverse


{-| Simulates a SQL inner-join.

    dataSetA =
        [ ( 1, "a" ), ( 2, "b" ) ]

    dataSetB =
        [ ( 3, "C" ), ( 2, "B" ) ]

    dataSetA
        |> innerJoin dataSetB
            (\a b ->
               Tuple.first a == Tuple.first b
            ) ==
            [ ( ( 2, "b" ), ( 2, "B" ) )
            ]

-}
innerJoin : List b -> (a -> b -> Bool) -> List a -> List ( a, b )
innerJoin listB onPredicate listA =
    listA
        |> List.concatMap
            (\a ->
                listB
                    |> List.filterMap
                        (\b ->
                            if onPredicate a b then
                                Just ( a, b )

                            else
                                Nothing
                        )
            )


{-| Simulates a SQL left-outer-join.

    dataSetA =
        [ ( 1, "a" ), ( 2, "b" ) ]

    dataSetB =
        [ ( 3, "C" ), ( 2, "B" ) ]

    dataSetA
        |> leftJoin dataSetB
            (\a b ->
               Tuple.first a == Tuple.first b
            ) ==
            [ ( ( 1, "a" ), Nothing )
            , ( ( 2, "b" ), Just ( 2, "B" ) )
            ]

-}
leftJoin : List b -> (a -> b -> Bool) -> List a -> List ( a, Maybe b )
leftJoin listB onPredicate listA =
    listA
        |> List.concatMap
            (\a ->
                let
                    matchingRows =
                        listB
                            |> List.filterMap
                                (\b ->
                                    if onPredicate a b then
                                        Just ( a, Just b )

                                    else
                                        Nothing
                                )
                in
                if List.isEmpty matchingRows then
                    [ ( a, Nothing ) ]

                else
                    matchingRows
            )


{-| Simulates a SQL right-outer-join.

    dataSetA =
        [ ( 1, "a" ), ( 2, "b" ) ]

    dataSetB =
        [ ( 3, "C" ), ( 2, "B" ) ]

    dataSetA
        |> rightJoin dataSetB
            (\a b ->
               Tuple.first a == Tuple.first b
            ) ==
            [ ( Just ( 2, "b" ), ( 2, "B" ) )
            , ( Nothing, ( 3, "C" ) )
            ]

-}
rightJoin : List b -> (a -> b -> Bool) -> List a -> List ( Maybe a, b )
rightJoin listB onPredicate listA =
    listB
        |> List.concatMap
            (\b ->
                let
                    matchingRows =
                        listA
                            |> List.filterMap
                                (\a ->
                                    if onPredicate a b then
                                        Just ( Just a, b )

                                    else
                                        Nothing
                                )
                in
                if List.isEmpty matchingRows then
                    [ ( Nothing, b ) ]

                else
                    matchingRows
            )
