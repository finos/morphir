module Morphir.Reference.Model.ValueEditors exposing (..)


bool : Bool -> Bool
bool input =
    input


char : Char -> Char
char input =
    input


string : String -> String
string input =
    input


int : Int -> Int
int input =
    input


float : Float -> Float
float input =
    if input == 0 then
        0

    else
        input


type alias Price =
    Float


priceAlias : Price -> Price
priceAlias price =
    if price == 0 then
        0

    else
        price


record1 : { boolField : Bool } -> Bool
record1 input =
    input.boolField


record2 : { boolField : Bool, intField : Int } -> Bool
record2 input =
    input.boolField


record3 : { boolField : Bool, intField : Int, floatField : Float } -> Int
record3 input =
    if input.boolField then
        if input.floatField < 5 then
            0

        else
            1

    else if input.intField > 10 then
        2

    else
        3


record4 : { boolField : Bool, intField : Int, floatField : Float } -> { boolField : Bool, intField : Int } -> Float
record4 foo bar =
    foo.floatField


record5 : { foo : { boolField : Bool, intField : Int, floatField : Float }, bar : { boolField : Bool, intField : Int } } -> Bool
record5 input =
    input.foo.boolField


record6 : { first : { foo : { boolField : Bool, intField : Int, floatField : Float }, bar : { boolField : Bool, intField : Int } }, second : { foo : { boolField : Bool, intField : Int, floatField : Float }, bar : { boolField : Bool, intField : Int } } } -> Bool
record6 input =
    input.first.foo.boolField


type SmallEnum
    = OptionOne
    | OptionTwo
    | OptionThree


smallEnum : SmallEnum -> SmallEnum
smallEnum input =
    input


type LargeEnum
    = Option1
    | Option2
    | Option3
    | Option4
    | Option5
    | Option6
    | Option7
    | Option8
    | Option9
    | Option10
    | Option11
    | Option12
    | Option13
    | Option14
    | Option15
    | Option16
    | Option17
    | Option18
    | Option19
    | Option20


largeEnum : LargeEnum -> LargeEnum
largeEnum input =
    input


maybe1 : Maybe Int -> Int
maybe1 input =
    case input of
        Just value ->
            value

        Nothing ->
            0


maybe2 : Maybe SmallEnum -> Maybe SmallEnum
maybe2 input =
    input


list1 : List Int -> List Int
list1 input =
    input


list2 : List { boolField : Bool, intField : Int } -> List { boolField : Bool, intField : Int }
list2 input =
    input


list3 : List { boolField : Bool, intField : Int, smallEnum : SmallEnum } -> List { boolField : Bool, intField : Int, smallEnum : SmallEnum }
list3 input =
    input
