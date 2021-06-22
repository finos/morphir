module Morphir.Reference.Model.Issues.Issue407 exposing (BigRecord, foo, foo1, foo1Clash, foo1Clash2, foo2, foo3)


type alias BigRecord =
    { field1 : Int
    , field2 : Int
    , field3 : Int
    , field4 : Int
    , field5 : Int
    , field6 : Int
    , field7 : Int
    , field8 : Int
    , field9 : Int
    , field10 : Int
    , field11 : Int
    , field12 : Int
    , field13 : Int
    , field14 : Int
    , field15 : Int
    , field16 : Int
    , field17 : Int
    , field18 : Int
    , field19 : Int
    , field20 : Int
    , field21 : Int
    , field22 : Int
    , field23 : Int
    }


foo : BigRecord
foo =
    BigRecord 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23


foo1 : Int -> BigRecord
foo1 =
    BigRecord 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22


foo1Clash : Int -> Int -> BigRecord
foo1Clash a0 =
    BigRecord 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 a0


foo1Clash2 : Int -> BigRecord
foo1Clash2 =
    let
        a0 : Int
        a0 =
            22
    in
    BigRecord 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 a0


foo2 : Int -> Int -> BigRecord
foo2 =
    BigRecord 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21


foo3 : BigRecord
foo3 =
    { field1 = 1
    , field2 = 2
    , field3 = 3
    , field4 = 4
    , field5 = 5
    , field6 = 6
    , field7 = 7
    , field8 = 8
    , field9 = 9
    , field10 = 10
    , field11 = 11
    , field12 = 12
    , field13 = 13
    , field14 = 14
    , field15 = 15
    , field16 = 16
    , field17 = 17
    , field18 = 18
    , field19 = 19
    , field20 = 20
    , field21 = 21
    , field22 = 22
    , field23 = 23
    }
