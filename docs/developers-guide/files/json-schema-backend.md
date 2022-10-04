# Json Schema Backend
This is a documentation a of the Json Schema backend for generating Json Schema. 
This document describes how Morphir Models maps to Json Schema.
Json Schema Reference can be found [here](http://json-schema.org/understanding-json-schema/reference/index.html)
<br>
Additional reading:
* [Sample Json Schema](mappings.json)
* [Json Mapping](json-mapping.md)


## Supported Types
Based on the Json Schema specification, the following types are supported.
* string
* Numeric types
* object
* array
* boolean
* null

The rest of the explains how each Morphir type maps to the Json Schema Types.

## Strings (string)
```String``` types in Morphir directly map to ```string``` type in Json Schema.
Therefore elm model:
```elm
type LastName
    = String
```
would map to the following schema:
```json
"Lastname" : {
  "type" : "string"
}
```


## Numeric Types (number)
Decimal, Ints and Float types in Morphir all map to ```number``` type in Json Schema. An example is given below
Morphir model:
```elm
type Age
    = Int
type Amount 
    = Decimal
```
Json Schema
```json
"Age" : {
  "type" : "number"
}
"Amount" : {
  "type" : "number"
}
```

## Booleans (boolean)
Boolean type in Morphir maps to boolean in Json Schema as shown in the example:
```elm
type Overtime
    = Boolean
```
Json Schema
```json
"Overtime" : {
  "type" : "boolean"
}
```

## Objects (object)
Record types in Morphir maps to objects in Json schema. The fields of the record maps to properties of the Json Schema object.
The properties of a JSON schema is a list of schemas. An example is given below
```elm
type alias Address =
    { country : String
    , state : String
    , street : String
    }
```

Equivalent Json schema
```json
"Records.Address": {
    "type": "object",
    "properties": {
        "Country": {
            "type": "string"
        },
        "State": {
            "type": "string"
        },
        "Street": {
            "type": "string"
        }
    }
}
```
## Arrays (array)
An array is  list of items. 
Json schema specification supports array validation:
* **List Validation** - each item in the array matches the same schema
* **Tuple Validation** - each item in the array may have a different schema
Union types in Morphir maps to arrays in Json Schema. Details are given below in the Custom Types sections.
### Items
The array schema contains the ```items``` keyword. For list validation, this keyword is set to a single schema that would be
used to validate all items in the array
For tuple validation, when we want disallows extra items in the tuple, the items keyword is set to false.

### Prefix Items
This is a keyword that specifies an array used to hold the schemas for a tuple-validated array.
Each item in prefixItems is a schema that corresponds to each index of the document's array


## Morphir Custom Types 
Custom types in Morphir, are union types with one or more items in the union. These items are called tags or constructors.
Each item has zero or more arguments which are types.
Json Schema does not support custom types natively. So we use the following approach.
* a constructor with its arguments will map to a tuple-validated array where the constructor is the first item in the array
* the schema type for the constructor would be const (explained below)
* the union type itself would then be represented using the "anyOf" keyword
The following Morphir model:
```elm
type Person
    = Person String
    | Child String Int
```
would map to the schema:
```json
"Person.Child": {
    "type": "array",
    "items": false,
    "prefixItems": [
        {
            "const": "Child"
        },
        {
            "type": "string"
        },
        {
            "type": "integer"
        }
    ]
}
```
The resulting "anyOf" schema would be as shown below:
```json
"Person": {
    "anyOf": [
        {
            "const": "Child"
        },
        {
            "const": "Person"
        }
    ]
}
```

## Null (null)
When a schema specifies a type of null, it has only one acceptable value: null.
In Json, null is equivalent to a value being absent.


## Const
As mentioned previosly, when a constructor in a union type has zero arguments, then it maps to a 'const" schema

## Ref
A schema can reference another schema using the $ref keyword. The valueof the $ref is the URI-reference that is resolved against the base URI.
For reference types in Morphir, the $ref keyword is used to refer to the target schema.
In the example below, the Address field of the Bank schema referes to the Address schema. So the $ref keyword is used:

Morphir model:

```elm
type alias Bank =
    { bankName : String
    , address : Address}

type alias Address =
    { country : String
    , state : String
    , street : String
    }
```
Json Schema:
```json
"Records.Bank": {
    "type": "object",
    "properties": {
        "Address": {
            "$ref": "#/defs/Address"
        },
        "BankName": {
            "type": "string"
        }
    }
}
```

## anyOf
The anyOf keyword is used to relate a schema with it's subschemas. 
