module Morphir.JsonSchema.AST exposing (..)

import Dict exposing (Dict)


type alias TypeName =
    String


type alias Schema =
    { id : String
    , schemaVersion : String
    , definitions : Dict TypeName SchemaType
    }



-- Used to enforce a Set type


type alias UniqueItems =
    Bool



{-
   The length of the array can be specified using the minItems and maxItems keywords.
   The numberOfItems is used to enforce this
   |
-}


type alias NumberOfItems =
    Int


type alias StringConstraints =
    { format : Maybe String
    }


type SchemaType
    = Integer
    | Array ArrayType UniqueItems
    | String StringConstraints
    | Number
    | Boolean
    | Object (Dict String SchemaType) (List TypeName)
    | Const String
    | Ref TypeName
    | OneOf (List SchemaType)
    | Null


type ArrayType
    = ListType SchemaType
    | TupleType (List SchemaType) NumberOfItems
