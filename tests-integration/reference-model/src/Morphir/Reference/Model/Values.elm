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


basicRecordMany : { foo : String, bar : Bool, baz : Int, record : { foo : String } }
basicRecordMany =
    { foo = "bar"
    , bar = False
    , baz = 15
    , record = basicRecordOne
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


basicIfThenElse2 : String -> String
basicIfThenElse2 ball =
    let
        a : Int
        a =
            1
    in
    if ball /= "ball" then
        ball

    else
        "Bye"


basicIfThenElse3 : Bool -> String
basicIfThenElse3 boolValueVariable =
    if boolValueVariable then
        "bool"

    else
        "Bye"


booleanExpressions : Bool -> Bool -> Bool -> Bool
booleanExpressions ball cat dog =
    ball && cat || dog


booleanExpressions2 : Bool -> Bool -> Bool -> Bool -> Bool
booleanExpressions2 a b c d =
    d && booleanExpressions a b c


booleanExpressions3 : Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool
booleanExpressions3 a b c d e f =
    a || b && booleanExpressions2 c d e f


booleanExpressions4 : Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool
booleanExpressions4 a b c d e f g h =
    a || b && booleanExpressions3 c d e f g h


type alias FruitAction =
    { fruitType : String
    , amount : Float
    }


noHarvest : List FruitAction
noHarvest =
    []


basicIfThenElse4 : Float -> Float -> Float -> Float -> Float -> List FruitAction
basicIfThenElse4 greenApple redApple amberApple greenPear redPear =
    if greenApple == 0 || redApple == 0 || greenApple == redApple then
        noHarvest

    else
        let
            redGreenApple : Float
            redGreenApple =
                redApple + greenApple
        in
        if redGreenApple > 0 then
            let
                appleAmount : Float
                appleAmount =
                    10
            in
            [ { fruitType = "apple", amount = appleAmount }
            , { fruitType = "pear", amount = 5 }
            ]

        else
            let
                appleAmount : Float
                appleAmount =
                    15

                bananaAmount : Float
                bananaAmount =
                    158.3
            in
            [ { fruitType = "apple", amount = appleAmount }
            , { fruitType = "pear", amount = 5 }
            , FruitAction "banana" bananaAmount
            ]


basicPatternMatchWildcard : String -> String -> String -> Int
basicPatternMatchWildcard s p q =
    case ( s, p, q ) of
        _ ->
            1


nestedPatternMatch : String -> String -> String -> String -> String -> Int
nestedPatternMatch a b c d e =
    case ( a, b ) of
        ( "foo", "bar" ) ->
            case ( d, e ) of
                _ ->
                    1

        _ ->
            case c of
                "bar" ->
                    2

                _ ->
                    3


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


simpleJustMaybe : Maybe String
simpleJustMaybe =
    Just "value"


simpleNothing : Maybe String
simpleNothing =
    Nothing


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


functionString : String -> String
functionString myStr =
    functionString2 myStr |> String.trim


functionString2 : String -> String
functionString2 temp =
    temp


functionString3 : String -> String
functionString3 myStr =
    myStr |> String.trim


parseMonth : String -> Maybe Int
parseMonth userInput =
    String.toInt userInput
        |> Maybe.andThen toValidMonth


parseMonth2 : String -> Maybe Int
parseMonth2 userInput =
    String.toInt userInput
        |> Maybe.map (\input -> Just input)
        |> Maybe.withDefault Nothing


toValidMonth : Int -> Maybe Int
toValidMonth month =
    if 1 <= month && month <= 12 then
        Just month

    else
        Nothing


maybeMap2 : String -> String -> Maybe Int
maybeMap2 input1 input2 =
    Maybe.map2 (+) (String.toInt input1) (String.toInt input2)


maybeMap2Lambda : String -> String -> Maybe Int
maybeMap2Lambda input1 input2 =
    Maybe.map2 (\val1 val2 -> val1 + val2) (String.toInt input1) (String.toInt input2)


maybeMap3 : String -> String -> String -> Maybe Int
maybeMap3 input1 input2 input3 =
    Maybe.map3 (\val1 val2 val3 -> val1 * val2 * val3) (String.toInt input1) (String.toInt input2) (String.toInt input3)


maybeMap4 : String -> String -> String -> String -> Maybe Int
maybeMap4 input1 input2 input3 input4 =
    Maybe.map4 (\val1 val2 val3 val4 -> val1 * val2 * val3 * val4) (String.toInt input1) (String.toInt input2) (String.toInt input3) (String.toInt input4)


maybeMap5 : String -> String -> String -> String -> String -> Maybe Int
maybeMap5 input1 input2 input3 input4 input5 =
    Maybe.map5 (\val1 val2 val3 val4 val5 -> val1 * val2 * val3 * val4 + val5) (String.toInt input1) (String.toInt input2) (String.toInt input3) (String.toInt input4) (String.toInt input5)


listAll : List Int -> Bool
listAll list =
    List.all
        (\val ->
            if modBy 2 val == 0 then
                True

            else
                False
        )
        list


isEven : Int -> Bool
isEven value =
    if modBy 2 value == 0 then
        True

    else
        False


modByTest : Int -> Int
modByTest value =
    modBy 2 value


listAny : List Int -> Bool
listAny list =
    List.any isEven list


listPartition : List Int -> ( List Int, List Int )
listPartition list =
    List.partition (\x -> x < 3) list


listPartition2 : List Int -> ( List Int, List Int )
listPartition2 list =
    List.partition isEven list


listUnzip : List ( Int, String ) -> ( List Int, List String )
listUnzip list =
    List.unzip list


listConcatMap : List Int -> Int -> List Int
listConcatMap list num =
    List.concatMap (\value -> value |> List.repeat num) list


listMap2 : List Int -> List Int -> List Int
listMap2 list1 list2 =
    List.map2 (+) list1 list2


listFoldl1 : Int -> List Int -> Int
listFoldl1 value list1 =
    List.foldl (+) value list1


listFoldl2 : List Int -> List Int -> List number
listFoldl2 list1 list2 =
    List.foldl (::) list1 list2


listFoldr1 : Int -> List Int -> Int
listFoldr1 value list1 =
    List.foldr (+) value list1


listFoldr2 : List Int -> List Int -> List number
listFoldr2 list1 list2 =
    List.foldr (::) list1 list2


listCons : Int -> List Int -> List Int
listCons value list =
    value :: list
