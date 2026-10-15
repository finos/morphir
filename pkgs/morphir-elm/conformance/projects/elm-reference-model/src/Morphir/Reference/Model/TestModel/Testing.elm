module Morphir.Reference.Model.TestModel.Testing exposing (..)

import Morphir.SDK.Decimal as Decimal exposing (Decimal)


fo20000o : Decimal
fo20000o =
    Decimal.fromFloat 1.0


type MyType
    = OneThing
    | OtherThing


type alias MyRecord =
    { key1 : MyType
    , key2 : MyType
    }


type alias MyList =
    List ( MyType, MyType )


type alias MyList2 =
    MyList


decimalAddition : Decimal -> Decimal -> Decimal
decimalAddition a b =
    Decimal.add a b


mapping : MyList -> a -> (a -> MyList) -> MyList
mapping ml s toMyList =
    case ml of
        [] ->
            toMyList s

        h :: t ->
            h :: mapping t s toMyList


test1 : MyList
test1 =
    [ ( OneThing, OtherThing ) ]


test2 : List ( MyType, MyType )
test2 =
    [ ( OneThing, OtherThing ) ]


test3 : List ( MyList, MyList )
test3 =
    [ ( test1, test2 ) ]


test4 : MyList2
test4 =
    [ ( OneThing, OtherThing ) ]


test5 : List MyRecord
test5 =
    [ { key1 = OneThing, key2 = OtherThing }, { key1 = OneThing, key2 = OtherThing } ]

test6 : String -> Int -> Maybe String -> Maybe Int -> List MyRecord
test6 a b c d =
    [ { key1 = OneThing, key2 = OtherThing }, { key1 = OneThing, key2 = OtherThing } ]

test7 : Maybe String -> String -> String
test7 maybeString string = 
    case maybeString of
        Nothing ->
            "xxxxx"
        _ ->
            string

test8 : Maybe String -> Maybe String
test8 maybeString = 
    case maybeString of
        Just s ->
            Just "just string"
        _ ->
           Nothing



newTest : String -> Bool -> Int -> Int -> Int -> MyType
newTest a b q w e=
    if (add3 q w e) > 6 then
        if b then
            case a of
                "a" ->
                    OtherThing

                "b" ->
                    OtherThing

                _ ->
                    OneThing

        else
            case a of
                "b" ->
                    OneThing

                "a" ->
                    OtherThing

                _ ->
                    OtherThing
    else
        OtherThing


newTest2 : String -> Bool -> MyType
newTest2 a b =
    newTest3 a b 3 4 5

newTest3 : String -> Bool -> Int -> Int -> Int -> MyType
newTest3 a b q w e =
    case a of
        "a" ->
            if b then
                case a of
                    "a" ->
                        OtherThing

                    "b" ->
                        OtherThing

                    _ ->
                        OneThing

            else
                case a of
                    "b" ->
                        OneThing

                    "a" ->
                        OtherThing

                    _ ->
                        OtherThing

        "b" ->
            newTest a False q w e

        _ ->
            OneThing

example1 : Bool -> Maybe Bool -> String
example1 a b =
    if a then
        case b of
            Just sth ->
                if sth then
                    "foo"
                else
                    "bar"

            Nothing ->
                "bar"

    else
        "bar"

example2 : Maybe String -> Bool -> String
example2 a b =
    case a of
        Just set ->
            if set == "a" && b then
                "b"
            else
                ""
        Nothing ->
            ""

add2 : Int -> Int -> Int
add2 a b =
    a + b

add3 : Int -> Int -> Int -> Int
add3 a b c =
    c + add2 a b

add4 : Int -> Int -> Int -> Int -> Int
add4 a b c d =
    d + add3 a b c

add7 : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int
add7 a b c d e f g =
    (add3 a b c) + (add4 d e f g)


powerRecursive : Int -> Int -> Int
powerRecursive x n =
    if n == 0 then
        1
    else if n == 1 then
        x
    else
        x * (powerRecursive x (n - 1))