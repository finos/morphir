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


{-| convert a Parser.DeadEnd into a List of String
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
    let
        encodeIRModuleName moduleName =
            Encode.list (Encode.list Encode.string) moduleName

        encodeElmModuleName moduleName =
            Encode.list Encode.string moduleName

        encodeProblem problem =
            case problem of
                Parser.Expecting token ->
                    Encode.list Encode.string [ "Expecting", token ]

                Parser.ExpectingInt ->
                    Encode.string "ExpectingInt"

                Parser.ExpectingHex ->
                    Encode.string "ExpectingHex"

                Parser.ExpectingOctal ->
                    Encode.string "ExpectingOctal"

                Parser.ExpectingBinary ->
                    Encode.string "ExpectingBinary"

                Parser.ExpectingFloat ->
                    Encode.string "ExpectingFloat"

                Parser.ExpectingNumber ->
                    Encode.string "ExpectingNumber"

                Parser.ExpectingVariable ->
                    Encode.string "ExpectingVariable"

                Parser.ExpectingSymbol symbol ->
                    Encode.list Encode.string [ "Expecting symbol", symbol ]

                Parser.ExpectingKeyword keyword ->
                    Encode.list Encode.string [ "ExpectingKeyword", keyword ]

                Parser.ExpectingEnd ->
                    Encode.string "ExpectingEnd"

                Parser.UnexpectedChar ->
                    Encode.string "UnexpectedChar"

                Parser.Problem message ->
                    Encode.list Encode.string [ "Problem", message ]

                Parser.BadRepeat ->
                    Encode.string "BadRepeat"

        encodeDeadEnd deadEnd =
            deadEnd
                |> (\{ row, col, problem } ->
                        Encode.object
                            [ ( "row", Encode.int row )
                            , ( "col", Encode.int col )
                            , ( "problem", encodeProblem problem )
                            ]
                   )
    in
    case error of
        IncrementalFrontend.CycleDetected fromModuleName toModuleName ->
            [ Encode.string "CycleDetected"
            , encodeIRModuleName fromModuleName
            , encodeIRModuleName toModuleName
            ]
                |> Encode.list identity

        IncrementalFrontend.InvalidModuleName moduleName ->
            [ Encode.string "InvalidModuleName"
            , encodeElmModuleName moduleName
            ]
                |> Encode.list identity

        IncrementalFrontend.ParseError path deadEnds ->
            [ Encode.string "ParserError"
            , Encode.string path
            , Encode.list encodeDeadEnd deadEnds
            ]
                |> Encode.list identity

        IncrementalFrontend.RepoError errors ->
            Encode.list RepoCodec.encodeError errors
