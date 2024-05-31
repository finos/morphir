module Morphir.FuzzEx exposing (..)

import Basics exposing (abs)
import Fuzz exposing (..)


positiveInt : Fuzzer Int
positiveInt =
    int
        |> Fuzz.map
            (\n ->
                if n == 0 then
                    1

                else if n < 1 then
                    abs n

                else
                    n
            )


nonZeroInt : Fuzzer Int
nonZeroInt =
    int
        |> Fuzz.map
            (\n ->
                if n == 0 then
                    1

                else
                    n
            )
