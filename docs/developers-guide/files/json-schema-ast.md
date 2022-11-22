# Json Schema AST
This is documentation of the [Json Schema AST](../../../src/Morphir/JsonSchema/AST.elm)
It describes the conceptual model for deriving a JSON Schema from a Morphir module.

## Schema
This is a representation of a JSON Schema.
It is modeled as a record with three fields:
- id
- schemaVersion
- definitions
The definitions property holds all the sub-schemas as a dictionary of 
TypeName and SchemaType
```elm
type alias Schema =
    { id : String
    , schemaVersion : String
    , definitions : Dict TypeName SchemaType
    }
```

## SchemaType
The SchemaType of a JsonSchema is modeled as one of 
10 different types as given below:

```elm
type SchemaType
    = Integer
    | Array ArrayType UniqueItems
    | String StringConstraints
    | Number
    | Boolean
    | Object (Dict String SchemaType)
    | Const String
    | Ref TypeName
    | OneOf (List SchemaType)
    | Null
```

The ArrayType argument to the Array indicates if
the array is validated as a List <br>
The UniqueItems argument to the Array indicates if the
array is a Set. In this case the UniqueItems is set to True.
The ArrayType is given below:

```elm
type ArrayType
    = ListType SchemaType
    | TupleType (List SchemaType)
```