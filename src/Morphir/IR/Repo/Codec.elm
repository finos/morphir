module Morphir.IR.Repo.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Elm.ModuleName as Module
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Repo exposing (Error(..), Errors)
import Parser


{-| convert a Morphir.IR.ModuleName into a string
-}
moduleNameToString : ModuleName -> String
moduleNameToString moduleName =
    moduleName
        |> List.map Name.toTitleCase
        |> String.join "."


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
encodeParserDeadEnd : List Parser.DeadEnd -> Encode.Value
encodeParserDeadEnd deadEnds =
    deadEnds
        |> List.map
            (\{ row, col, problem } ->
                String.concat
                    [ mapParserProblem problem
                    , " at line "
                    , String.fromInt row
                    , ":"
                    , String.fromInt col
                    ]
            )
        |> Encode.list Encode.string


{-| encode a Repo Error
-}
encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ModuleNotFound moduleName ->
            moduleName
                |> moduleNameToString
                |> (\moduleNameAsString ->
                        String.concat [ "Module not found: ", moduleNameAsString ]
                   )
                |> Encode.string

        ModuleHasDependents moduleName dependentModuleNames ->
            Encode.list identity
                [ Encode.string
                    (String.concat
                        [ "The following modules depend on "
                        , moduleName |> moduleNameToString
                        ]
                    )
                , Encode.set
                    (moduleNameToString >> Encode.string)
                    dependentModuleNames
                ]

        ModuleAlreadyExist moduleName ->
            String.concat
                [ moduleName
                    |> moduleNameToString
                , " Already exists"
                ]
                |> Encode.string
