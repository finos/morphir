module Morphir.Elm.Generator.API exposing (..)

import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)
import Random
import Random.Char as Random
import Random.Extra as Random
import Random.List as Random
import Random.String as Random


type Generator a
    = Generator (Random.Generator a)


type alias Seed =
    Random.Seed


g : Random.Generator a -> Generator a
g =
    Generator


createRandomSeed : Generator Seed
createRandomSeed =
    g Random.independentSeed


seed : Int -> Seed
seed =
    Random.initialSeed


constant : a -> Generator a
constant =
    g << Random.constant


bool : Generator Bool
bool =
    g <| Random.uniform True [ False ]


anyChar : Generator Char
anyChar =
    g <| Random.ascii


alphaChar : Generator Char
alphaChar =
    g <| Random.english


int : Generator Int
int =
    g <| Random.int Random.minInt Random.maxInt


intRange : Int -> Int -> Generator Int
intRange from to =
    g <| Random.int from to


niceFloat : Generator Float
niceFloat =
    g <|
        Random.float
            (toFloat Random.minInt)
            (toFloat Random.maxInt)


{-| Generates a string of 3 to 10 characters.
-}
string : Generator String
string =
    g <|
        Random.rangeLengthString 3 10 Random.english


maybe : Generator a -> Generator (Maybe a)
maybe =
    useRandom
        (Random.andThen
            (\a ->
                Random.uniform
                    (Just a)
                    [ Nothing ]
            )
        )


{-| Generate a list of length 1 - 100.
-}
list : Generator a -> Generator (List a)
list =
    useRandom
        (\internalGenA ->
            Random.int 1 100
                |> Random.andThen
                    (\i ->
                        Random.list i internalGenA
                    )
        )


oneOf : a -> List a -> Generator a
oneOf default ls =
    g <| Random.uniform default ls


andThen : (a -> Generator b) -> Generator a -> Generator b
andThen fn genA =
    toRandom genA
        |> Random.andThen (fn >> toRandom)
        |> g


map : (a -> b) -> Generator a -> Generator b
map fn =
    toRandom
        >> Random.map fn
        >> g


map2 : (a -> b -> c) -> Generator a -> Generator b -> Generator c
map2 fn genA genB =
    Random.map2 fn
        (toRandom genA)
        (toRandom genB)
        |> g


toRandom : Generator a -> Random.Generator a
toRandom generator =
    case generator of
        Generator rg ->
            rg


useRandom : (Random.Generator a -> Random.Generator b) -> Generator a -> Generator b
useRandom use =
    toRandom
        >> use
        >> g


combine : List (Generator a) -> Generator (List a)
combine generators =
    generators
        |> List.map toRandom
        |> Random.combine
        |> g


next : Seed -> Generator a -> a
next sd gen =
    let
        ( a, _ ) =
            Random.step
                (toRandom gen)
                sd
    in
    a


nextN : Int -> Seed -> Generator a -> List a
nextN n sd gen =
    nextNHelper n sd gen []


nextNHelper : Int -> Seed -> Generator a -> List a -> List a
nextNHelper n sd genA generatedSoFar =
    if n <= 0 && List.isEmpty generatedSoFar then
        -- 0 or negative starting value for n.
        -- default n to 1
        nextNHelper 1 sd genA generatedSoFar

    else if n <= 0 then
        generatedSoFar

    else
        let
            ( val, nextSeed ) =
                Random.step (toRandom genA) sd
        in
        nextNHelper (n - 1) nextSeed genA (val :: generatedSoFar)
