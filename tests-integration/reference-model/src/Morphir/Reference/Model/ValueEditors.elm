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
    input


type alias Price =
    Float


priceAlias : Price -> Price
priceAlias price =
    price


record1 : { boolField : Bool } -> Bool
record1 input =
    input.boolField


record2 : { boolField : Bool, intField : Int } -> Bool
record2 input =
    input.boolField


record3 : { boolField : Bool, intField : Int, floatField : Float } -> Bool
record3 input =
    input.boolField


record4 : { boolField : Bool, intField : Int, floatField : Float } -> { boolField : Bool, intField : Int } -> Bool
record4 foo bar =
    foo.boolField


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
