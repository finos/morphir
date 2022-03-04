module Morphir.Elm.IncrementalFrontend.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend
import Morphir.Elm.ModuleName as ModuleName exposing (ModuleName)
import Morphir.IR.Repo.Codec as RepoCodec
import Parser


{-| convert a Problem into a string in an attempt to produce a meaningful error
-}
mapParserProblem : Parser.Problem -> String
mapParserProblem problem =
    case problem of
        Parser.Expecting token ->
            String.concat [ "Expecting: ", token ]

        Parser.ExpectingInt ->
            "Expecting integer"

        Parser.ExpectingHex ->
            "Expecting hexadecimal"

        Parser.ExpectingOctal ->
            "Expecting octal"

        Parser.ExpectingBinary ->
            "Expecting binary"

        Parser.ExpectingFloat ->
            "Expecting float"

        Parser.ExpectingNumber ->
            "Expecting number"

        Parser.ExpectingVariable ->
            "Expecting variable"

        Parser.ExpectingSymbol symbol ->
            String.concat [ "Expecting symbol: ", symbol ]

        Parser.ExpectingKeyword keyword ->
            String.concat [ "Expecting keyword: ", keyword ]

        Parser.ExpectingEnd ->
            "Expecting end"

        Parser.UnexpectedChar ->
            "Unexpected character"

        Parser.Problem message ->
            String.concat [ "Problem: ", message ]

        Parser.BadRepeat ->
            "Bad repeat"


{-| encode a Parser.DeadEnd into a List of String
-}
errorStringFromParserDeadEnds : List Parser.DeadEnd -> String
errorStringFromParserDeadEnds deadEnds =
    deadEnds
        |> List.map
            (\{ row, col, problem } ->
                String.concat
                    [ "\t"
                    , mapParserProblem problem
                    , " at line "
                    , String.fromInt row
                    , ":"
                    , String.fromInt col
                    ]
            )
        |> String.join "\n"


encodeError : IncrementalFrontend.Error -> Encode.Value
encodeError error =
    case error of
        IncrementalFrontend.CycleDetected fromModuleName toModuleName ->
            String.concat
                [ "Circular module dependency detected at "
                , fromModuleName
                    |> ModuleName.fromIRModuleName
                    |> ModuleName.toString
                , " -> "
                , toModuleName
                    |> ModuleName.fromIRModuleName
                    |> ModuleName.toString
                ]
                |> Encode.string

        IncrementalFrontend.InvalidModuleName moduleName ->
            String.concat
                [ "Invalid module name: "
                , moduleName
                    |> ModuleName.toString
                ]
                |> Encode.string

        IncrementalFrontend.ParseError path deadEnds ->
            String.join "\n"
                [ String.concat [ "Found some errors while parsing ", path ]
                , errorStringFromParserDeadEnds deadEnds
                ]
                |> Encode.string

        IncrementalFrontend.RepoError errors ->
            Encode.list RepoCodec.encodeError errors
