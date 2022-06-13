module Morphir.JsonSchema.AST exposing (..)

import Dict exposing (Dict)


type alias TypeName =
    String


type alias Schema =
    { dirPath : List String
    , fileName : String
    , id : String
    , schemaVersion : String
    , definitions : Dict TypeName SchemaType
    }


type SchemaType
    = Integer
    | Array SchemaType
    | String
    | Number
    | Boolean
    | Object (Dict String SchemaType)
