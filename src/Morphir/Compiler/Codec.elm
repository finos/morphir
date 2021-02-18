module Morphir.Compiler.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Compiler exposing (Error(..), ErrorInSourceFile, FileLocation, SourceLocation, SourceRange)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec exposing (decodeDistribution, encodeDistribution)


{-| This is a manually managed version number to be able to handle breaking changes in the IR format more explicitly.
-}
latestIRFormatVersion : Int
latestIRFormatVersion =
    1


encodeIR : Distribution -> Encode.Value
encodeIR distro =
    Encode.object
        [ ( "formatVersion", Encode.int latestIRFormatVersion )
        , ( "distribution", encodeDistribution distro )
        ]


decodeIR : Decode.Decoder Distribution
decodeIR =
    Decode.oneOf
        [ Decode.field "formatVersion" Decode.int
            |> Decode.andThen
                (\formatVersion ->
                    if formatVersion == latestIRFormatVersion then
                        Decode.field "distribution" decodeDistribution

                    else
                        Decode.fail
                            (String.concat
                                [ "The IR is using format version "
                                , String.fromInt formatVersion
                                , " but the latest format version is "
                                , String.fromInt latestIRFormatVersion
                                , ". Please regenerate it!"
                                ]
                            )
                )
        , Decode.fail "The IR is in an old format that doesn't have a format version on it. Please regenerate it!"
        ]


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ErrorsInSourceFile filePath errorInSourceFiles ->
            Encode.list identity
                [ Encode.string "errors_in_source_file"
                , Encode.string filePath
                , Encode.list encodeErrorInSourceFile errorInSourceFiles
                ]

        ErrorAcrossSourceFiles errorAcrossSourceFiles ->
            Encode.list identity
                [ Encode.string "error_across_source_files"
                , Encode.object
                    [ ( "errorMessage", Encode.string errorAcrossSourceFiles.errorMessage )
                    , ( "files", Encode.list Encode.string errorAcrossSourceFiles.files )
                    ]
                ]


{-| Encode ErrorInSourceFile.
-}
encodeErrorInSourceFile : ErrorInSourceFile -> Encode.Value
encodeErrorInSourceFile errorInSourceFile =
    Encode.object
        [ ( "errorMessage", Encode.string errorInSourceFile.errorMessage )
        , ( "sourceLocations", Encode.list encodeSourceRange errorInSourceFile.sourceLocations )
        ]


{-| Encode FileLocation.
-}
encodeFileLocation : FileLocation -> Encode.Value
encodeFileLocation fileLocation =
    Encode.object
        [ ( "filePath", Encode.string fileLocation.filePath )
        , ( "sourceLocation", encodeSourceRange fileLocation.sourceLocation )
        ]


{-| Encode SourceRange.
-}
encodeSourceRange : SourceRange -> Encode.Value
encodeSourceRange sourceRange =
    Encode.object
        [ ( "start", encodeSourceLocation sourceRange.start )
        , ( "end", encodeSourceLocation sourceRange.end )
        ]


{-| Encode SourceLocation.
-}
encodeSourceLocation : SourceLocation -> Encode.Value
encodeSourceLocation sourceLocation =
    Encode.object
        [ ( "row", Encode.int sourceLocation.row )
        , ( "column", Encode.int sourceLocation.column )
        ]
