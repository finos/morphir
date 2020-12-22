module Morphir.Reference.Model.Values exposing (..)

import Morphir.Reference.Model.Types as Types exposing (Custom(..), FooBarBazRecord)
import String exposing (fromInt)


basicLiteralBool : Bool
basicLiteralBool =
    True


basicLiteralChar : Char
basicLiteralChar =
    'Z'


basicLiteralString : String
basicLiteralString =
    "foo bar"


basicLiteralInt : Int
basicLiteralInt =
    42


basicLiteralFloat : Float
basicLiteralFloat =
    3.14


basicConstructor1 : Custom
basicConstructor1 =
    CustomNoArg


basicConstructor2 : Custom
basicConstructor2 =
    CustomOneArg False


basicConstructor3 : Custom
basicConstructor3 =
    CustomTwoArg "Baz" 12345


basicRecordConstructor : FooBarBazRecord
basicRecordConstructor =
    FooBarBazRecord "foo" True 42


basicTuple2 : ( Int, String )
basicTuple2 =
    ( 13, "Tuple Two" )


basicTuple3 : ( Bool, Int, Bool )
basicTuple3 =
    ( True, 14, False )


basicListEmpty : List Int
basicListEmpty =
    []


basicListOne : List String
basicListOne =
    [ "single element" ]


basicListMany : List Char
basicListMany =
    [ 'a', 'b', 'c', 'd' ]


basicRecordEmpty : {}
basicRecordEmpty =
    {}


basicRecordOne : { foo : String }
basicRecordOne =
    { foo = "bar"
    }


basicRecordMany : { foo : String, bar : Bool, baz : Int }
basicRecordMany =
    { foo = "bar"
    , bar = False
    , baz = 15
    }


listOfRecords : List { foo : String, bar : Bool, baz : Int }
listOfRecords =
    [ { foo = "bar"
      , bar = False
      , baz = 15
      }
    , { foo = "foo"
      , bar = True
      , baz = 437
      }
    , { foo = "much longer"
      , bar = False
      , baz = -1500
      }
    ]


basicField : { foo : String } -> String
basicField rec =
    rec.foo


basicFieldFunction : { foo : String } -> String
basicFieldFunction =
    .foo


basicLetDefinition : Int
basicLetDefinition =
    let
        a : Int
        a =
            1

        b : Int
        b =
            a

        d : Int -> Int
        d i =
            i
    in
    d b


basicLetRecursion : Int
basicLetRecursion =
    let
        a : Int -> Int
        a i =
            b (i - 1)

        b : Int -> Int
        b i =
            if i < 0 then
                0

            else
                a i
    in
    a 10


basicDestructure : Int
basicDestructure =
    let
        ( a, b ) =
            ( 1, 2 )
    in
    b


basicIfThenElse : Int -> Int -> String
basicIfThenElse a b =
    if a < b then
        "Less"

    else
        "Greater or equal"


basicPatternMatchWildcard : String -> Int
basicPatternMatchWildcard s =
    case s of
        _ ->
            1


basicUpdateRecord : FooBarBazRecord -> FooBarBazRecord
basicUpdateRecord rec =
    { rec
        | baz = rec.baz + 1
    }


basicUnit : ()
basicUnit =
    ()


sdkBasicsValues : List Bool
sdkBasicsValues =
    [ 4 + 3 == 7
    , 4 - 3 == 1
    , 4 * 2.5 == 10
    , 10 / 4 == 2.5
    , 11 // 5 == 2
    , 2 ^ 3 == 8
    , toFloat 2 == 2.0
    , round 2.5 == 3
    , floor 2.78 == 2
    , ceiling 2.13 == 3
    , truncate 2.56 == 2
    , 1 == 1
    , 1 /= 2
    , (1 < 2) == True
    , (1 > 2) == False
    , (1 <= 2) == True
    , (1 >= 2) == False
    , max 1 2 == 2
    , min 1 2 == 1
    ]


sdkMaybeValues : List Bool
sdkMaybeValues =
    [ Maybe.andThen (always Nothing) Nothing == Nothing
    , Maybe.map fromInt (Just 42) == Just "42"
    , Maybe.map2 (\a b -> [ a, b ]) (Just 1) (Just 2) == Just [ 1.5, 2 ]
    , Maybe.map3 (\a b c -> [ a, b, c ]) (Just 1) (Just 2) (Just 3) == Just [ 1, 2.3, 3 ]
    , Maybe.map4 (\a b c d -> [ a, b, c, d ]) (Just 1) (Just 2) (Just 3) (Just 4) == Just [ 1, 2, 3.4, 4 ]
    , Maybe.map5 (\a b c d e -> [ a, b, c, d, e ]) (Just 1) (Just 2) (Just 3) (Just 4) (Just 5) == Just [ 1, 2, 3, 4.5, 5 ]
    , Maybe.withDefault 13 Nothing == 13.2
    ]


fieldFunctionAsArg : List FooBarBazRecord -> List String
fieldFunctionAsArg list =
    list
        |> List.filter (\x -> x.bar)
        |> List.map .foo


functionToMethod1 : Int
functionToMethod1 =
    Types.customToInt CustomNoArg


functionToMethod2 : Int
functionToMethod2 =
    Types.customToInt2 False (CustomOneArg True)


functionToMethod3 : String
functionToMethod3 =
    Types.fooBarBazToString (FooBarBazRecord "foo" False 43)
