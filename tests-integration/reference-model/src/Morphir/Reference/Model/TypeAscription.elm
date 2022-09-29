module Morphir.Reference.Model.TypeAscription exposing (..)


type alias Item =
    { name : String
    , brand : String
    , price : Float
    }


type Custom
    = Ctor1
    | Ctor2
    | Ctor3 String
    | Ctor4 String Int
    | Ctor5 Custom String
    | Ctor6 Item


use : Bool
use =
    target Ctor1 Ctor2


use1 : String -> Bool
use1 a =
    target1 (Ctor3 a)


use2 : String -> Int -> Bool
use2 a b =
    Ctor4 a b
        |> target Ctor1


use3 : String -> Bool
use3 str =
    target (Ctor5 Ctor1 str) (Ctor3 str)


use4 : Item -> Bool
use4 itm =
    target1 (Ctor6 itm)


target : a -> a -> Bool
target a b =
    True


target1 : a -> Bool
target1 a =
    True
