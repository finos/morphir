module TestModel.CollectionTypes exposing (..)

import Set exposing (Set)
import Dict exposing (Dict)


type alias Department =
    List String


type alias Queries =
    Set String

type alias Antonyms =
    Dict String String