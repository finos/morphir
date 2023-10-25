module Morphir.Decoration.Model.Composites exposing (..)


type alias SourceRecord =
    { name : String
    , sequenceNumber : Float
    , details : String
    }


type alias DatabaseName =
    String


type Repositories
    = Database DatabaseName
    | FileSystem String
    | Memory
