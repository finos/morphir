module Morphir.Reference.Model.Values exposing (..)

import Morphir.Reference.Model.Types exposing (Custom(..), FooBarBazRecord)


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


basicDestructure : int
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
