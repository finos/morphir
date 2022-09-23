module Morphir.Reference.Model.TypeAscription exposing (..)


type Custom
    = Ctor1
    | Ctor2


use : Bool
use =
    target Ctor1 Ctor2


target : a -> a -> Bool
target a b =
    True
