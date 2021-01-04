module Morphir.Compiler.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Compiler exposing (Error(..), ErrorInSourceFile, FileLocation, SourceLocation, SourceRange)


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
