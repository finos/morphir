module Morphir.Elm.IncrementalFrontend.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend
import Morphir.Elm.IncrementalResolve.Codec as IncrementalResolveCodec
import Morphir.IR.Name.Codec exposing (encodeName)
import Morphir.IR.Path.Codec exposing (encodePath)
import Morphir.IR.Repo.Codec as RepoCodec
import Parser


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
        IncrementalFrontend.ModuleCycleDetected fromModuleName toModuleName ->
            [ Encode.string "ModuleCycleDetected"
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

        IncrementalFrontend.TypeCycleDetected from to ->
            Encode.list identity
                [ Encode.string "TypeCycleDetected"
                , encodeName from
                , encodeName to
                ]

        IncrementalFrontend.ResolveError moduleName e ->
            Encode.list identity
                [ Encode.string "ResolveError"
                , encodePath moduleName
                , IncrementalResolveCodec.encodeError e
                ]
