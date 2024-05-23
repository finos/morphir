module Morphir.SDK.Dict exposing
    ( Dict
    , empty, singleton, insert, update, remove
    , isEmpty, member, get, size
    , keys, values, toList, fromList
    , map, foldl, foldr, filter, partition
    , union, intersect, diff, merge
    )

{-| A dictionary mapping unique keys to values. The keys can be any comparable
type. This includes `Int`, `Float`, `Time`, `Char`, `String`, and tuples or
lists of comparable types.

Insert, remove, and query operations all take _O(log n)_ time.


# Dictionaries

@docs Dict


# Build

@docs empty, singleton, insert, update, remove


# Query

@docs isEmpty, member, get, size


# Lists

@docs keys, values, toList, fromList


# Transform

@docs map, foldl, foldr, filter, partition


# Combine

@docs union, intersect, diff, merge

-}

import AssocList


{-| A dictionary of keys and values. So a `Dict String User` is a dictionary
that lets you look up a `String` (such as user names) and find the associated
`User`.

    import Dict exposing (Dict)

    users : Dict String User
    users =
        Dict.fromList
            [ ( "Alice", User "Alice" 28 1.65 )
            , ( "Bob", User "Bob" 19 1.82 )
            , ( "Chuck", User "Chuck" 33 1.75 )
            ]

    type alias User =
        { name : String
        , age : Int
        , height : Float
        }

-}
type alias Dict k v =
    AssocList.Dict k v


{-| Create an empty dictionary.
-}
empty : Dict k v
empty =
    AssocList.empty


{-| Get the value associated with a key. If the key is not found, return
`Nothing`. This is useful when you are not sure if a key will be in the
dictionary.

    animals = fromList [ ("Tom", Cat), ("Jerry", Mouse) ]

    get "Tom"   animals == Just Cat
    get "Jerry" animals == Just Mouse
    get "Spike" animals == Nothing

-}
get : comp -> Dict comp v -> Maybe v
get =
    AssocList.get


{-| Determine if a key is in a dictionary.
-}
member : comp -> Dict comp v -> Bool
member =
    AssocList.member


{-| Determine the number of key-value pairs in the dictionary.
-}
size : Dict k v -> Int
size =
    AssocList.size


{-| Determine if a dictionary is empty.

    isEmpty empty == True

-}
isEmpty : Dict k v -> Bool
isEmpty =
    AssocList.isEmpty


{-| Insert a key-value pair into a dictionary. Replaces value when there is
a collision.
-}
insert : comp -> v -> Dict comp v -> Dict comp v
insert =
    AssocList.insert


{-| Remove a key-value pair from a dictionary. If the key is not found,
no changes are made.
-}
remove : comp -> Dict comp v -> Dict comp v
remove =
    AssocList.remove


{-| Update the value of a dictionary for a specific key with a given function.
-}
update : comp -> (Maybe v -> Maybe v) -> Dict comp v -> Dict comp v
update =
    AssocList.update


{-| Create a dictionary with one key-value pair.
-}
singleton : comp -> v -> Dict comp v
singleton =
    AssocList.singleton



-- COMBINE


{-| Combine two dictionaries. If there is a collision, preference is given
to the first dictionary.
-}
union : Dict comp v -> Dict comp v -> Dict comp v
union =
    AssocList.union


{-| Keep a key-value pair when its key appears in the second dictionary.
Preference is given to values in the first dictionary.
-}
intersect : Dict comp v -> Dict comp v -> Dict comp v
intersect =
    AssocList.intersect


{-| Keep a key-value pair when its key does not appear in the second dictionary.
-}
diff : Dict comp a -> Dict comp b -> Dict comp a
diff =
    AssocList.diff


{-| The most general way of combining two dictionaries. You provide three
accumulators for when a given key appears:

1.  Only in the left dictionary.
2.  In both dictionaries.
3.  Only in the right dictionary.

You then traverse all the keys from lowest to highest, building up whatever
you want.

-}
merge :
    (comp -> a -> result -> result)
    -> (comp -> a -> b -> result -> result)
    -> (comp -> b -> result -> result)
    -> Dict comp a
    -> Dict comp b
    -> result
    -> result
merge =
    AssocList.merge



-- TRANSFORM


{-| Apply a function to all values in a dictionary.
-}
map : (k -> a -> b) -> Dict k a -> Dict k b
map =
    AssocList.map


{-| Fold over the key-value pairs in a dictionary from lowest key to highest key.

    import Dict exposing (Dict)

    getAges : Dict String User -> List String
    getAges users =
        Dict.foldl addAge [] users

    addAge : String -> User -> List String -> List String
    addAge _ user ages =
        user.age :: ages

    -- getAges users == [33,19,28]

-}
foldl : (k -> v -> b -> b) -> b -> Dict k v -> b
foldl =
    AssocList.foldl


{-| Fold over the key-value pairs in a dictionary from highest key to lowest key.

    import Dict exposing (Dict)

    getAges : Dict String User -> List String
    getAges users =
        Dict.foldr addAge [] users

    addAge : String -> User -> List String -> List String
    addAge _ user ages =
        user.age :: ages

    -- getAges users == [28,19,33]

-}
foldr : (k -> v -> b -> b) -> b -> Dict k v -> b
foldr =
    AssocList.foldr


{-| Keep only the key-value pairs that pass the given test.
-}
filter : (comp -> v -> Bool) -> Dict comp v -> Dict comp v
filter =
    AssocList.filter


{-| Partition a dictionary according to some test. The first dictionary
contains all key-value pairs which passed the test, and the second contains
the pairs that did not.
-}
partition : (comp -> v -> Bool) -> Dict comp v -> ( Dict comp v, Dict comp v )
partition =
    AssocList.partition



-- LISTS


{-| Get all of the keys in a dictionary, sorted from lowest to highest.

    keys (fromList [ ( 0, "Alice" ), ( 1, "Bob" ) ]) == [ 0, 1 ]

-}
keys : Dict k v -> List k
keys =
    AssocList.keys


{-| Get all of the values in a dictionary, in the order of their keys.

    values (fromList [ ( 0, "Alice" ), ( 1, "Bob" ) ]) == [ "Alice", "Bob" ]

-}
values : Dict k v -> List v
values =
    AssocList.values


{-| Convert a dictionary into an association list of key-value pairs, sorted by keys.
-}
toList : Dict k v -> List ( k, v )
toList =
    AssocList.toList


{-| Convert an association list into a dictionary.
-}
fromList : List ( comp, v ) -> Dict comp v
fromList =
    AssocList.fromList
