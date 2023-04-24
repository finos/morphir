module TestModel.CollectionTypes exposing (..)

import Dict exposing (Dict)
import Set exposing (Set)


type alias StringList =
    List String


type alias OneArgList a =
    List a


type alias SetList =
    Set Int


type alias DictType a b =
    Dict a b
