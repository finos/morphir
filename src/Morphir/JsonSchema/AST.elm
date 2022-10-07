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


type alias UniqueItems =
    Bool


type SchemaType
    = Integer
    | Array ArrayType UniqueItems
    | String
    | Number
    | Boolean
    | Object (Dict String SchemaType)
    | Const String
    | Ref TypeName
    | OneOf (List SchemaType)
    | Null


type ArrayType
    = ListType SchemaType
    | TupleType (List SchemaType)
