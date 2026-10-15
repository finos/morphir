module Morphir.Reference.Model.SDK.Result exposing (..)

import Result


resultMap : Float -> Result x Float
resultMap input =
    Result.map sqrt (Ok input)


resultMap2 : x -> Result x Float
resultMap2 input =
    Result.map sqrt (Err input)


resultWithDefault : Int -> String -> Int
resultWithDefault input resultType =
    case resultType of
        "Ok" ->
            Result.withDefault input (Ok 123)

        "Err" ->
            Result.withDefault input (Err "Err Selected")

        _ ->
            Result.withDefault input (Err "Wrong Input")


resultToMaybe : Int -> String -> Maybe Int
resultToMaybe value input =
    case input of
        "Ok" ->
            Result.toMaybe (Err input)

        _ ->
            Result.toMaybe (Ok value)


resultParseInt : Int -> String -> Result String Int
resultParseInt value string =
    resultToMaybe value string |> Result.fromMaybe (String.append "error parsing string: " string)


resultMapError : String -> String -> Result String Int
resultMapError resultType errorMessage =
    case resultType of
        "Ok" ->
            Result.mapError (\oldError -> errorMessage) (Ok 123)

        "Err" ->
            Result.mapError (\oldError -> errorMessage) (Err "Cannot parse")

        _ ->
            Result.mapError (\oldError -> errorMessage) (Err "Wrong Input")
