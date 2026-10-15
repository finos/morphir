module Morphir.Reference.Model.TypeAscription exposing (..)


type Custom
    = ZeroArgCtor
    | OneArgCtor String
    | TwoArgCtor String Int


useCase0 : Bool
useCase0 =
    target1 ZeroArgCtor


useCase1 : String -> Bool
useCase1 str =
    target1 (OneArgCtor str)


useCase2 : String -> Int -> Bool
useCase2 str int =
    target2 (OneArgCtor str) (TwoArgCtor str int)


useCase3 : Bool
useCase3 =
    target3 TwoArgCtor


target1 : a -> Bool
target1 a =
    True


target2 : a -> a -> Bool
target2 a1 a2 =
    True


target3 : (String -> Int -> Custom) -> Bool
target3 ctor =
    True


letRecursion items =
    let
        addHelper prev lst =
            case lst of
                [] ->
                    prev
                head :: rest ->
                    addHelper (prev + head) rest
    in
    addHelper 0 items