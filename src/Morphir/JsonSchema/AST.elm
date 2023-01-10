module Morphir.JsonSchema.AST exposing (..)

import Dict exposing (Dict)


type alias TypeName =
    String


type alias FieldName =
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


type alias StringConstraints =
    { format : Maybe String
    }



{-
   The SchemaType of a JsonSchema is modeled as one of
   10 different types as given below:
   |
-}


type SchemaType
    = Integer
    | Array ArrayType UniqueItems
    | String StringConstraints
    | Number
    | Boolean
    | Object (Dict String SchemaType) (List FieldName)
    | Const String
    | Ref TypeName
    | OneOf (List SchemaType)
    | Null



{-
   The ArrayType argument to the Array indicates if
   the array is validated as a List <br>
   The UniqueItems argument to the Array indicates if the
   array is a Set. In this case the UniqueItems is set to True.
   The ArrayType is given below:|
-}


type ArrayType
    = ListType SchemaType
    | TupleType (List SchemaType)
