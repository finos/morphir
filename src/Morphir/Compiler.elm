module Morphir.Compiler exposing (..)


type alias FilePath =
    String


type Error
    = ErrorsInSourceFile FilePath (List ErrorInSourceFile)
    | ErrorAcrossSourceFiles
        { errorMessage : String
        , files : List FilePath
        }


{-| -}
type alias ErrorInSourceFile =
    { errorMessage : String
    , sourceLocations : List SourceRange
    }


type alias FileLocation =
    { filePath : FilePath
    , sourceLocation : SourceRange
    }


{-| -}
type alias SourceRange =
    { start : SourceLocation
    , end : SourceLocation
    }


{-| -}
type alias SourceLocation =
    { row : Int
    , column : Int
    }
