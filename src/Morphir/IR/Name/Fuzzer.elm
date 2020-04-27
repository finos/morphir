module Morphir.IR.Name.Fuzzer exposing (..)

{-| Name fuzzer.
-}

import Fuzz exposing (Fuzzer)
import Morphir.IR.Name as Name exposing (Name)


fuzzName : Fuzzer Name
fuzzName =
    let
        nouns =
            [ "area"
            , "benchmark"
            , "book"
            , "business"
            , "company"
            , "country"
            , "currency"
            , "day"
            , "description"
            , "entity"
            , "fact"
            , "family"
            , "from"
            , "government"
            , "group"
            , "home"
            , "id"
            , "job"
            , "left"
            , "lot"
            , "market"
            , "minute"
            , "money"
            , "month"
            , "name"
            , "number"
            , "owner"
            , "parent"
            , "part"
            , "problem"
            , "rate"
            , "right"
            , "state"
            , "source"
            , "system"
            , "time"
            , "title"
            , "to"
            , "valid"
            , "week"
            , "work"
            , "world"
            , "year"
            ]

        fuzzWord =
            nouns
                |> List.map Fuzz.constant
                |> Fuzz.oneOf
    in
    Fuzz.list fuzzWord
        |> Fuzz.map (List.take 3)
        |> Fuzz.map Name.fromList
