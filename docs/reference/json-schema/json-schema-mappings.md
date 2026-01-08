---
id: json-schema-mappings
sidebar_position: 4
---

# Json Schema Mappings
This is a documentation of the mapping strategy from Morphir types to Json Schema. 
This document describes how Morphir Models maps to Json Schema.
Json Schema Reference can be found [here](http://json-schema.org/understanding-json-schema/reference/index.html)
\
Additional reading:
* [Sample Json Schema](json-schema-sample.md)
* [Testing Strategy](json-schema-backend-testplan.md)

## Overview

We will give a quick overview of the mapping in the table below:

Type | Elm sample | JSON sample | Comment
---- | ---------- | ----------- | -------
`Bool` | `True`, `False` | `true`, `false` | Exact mapping
`Int` | `123`, `-15` | `123`, `-15` | Ints map to JSON number
`Float` | `3.14`, `-53.2` | `3.14`, `-53.2` | Floats map to JSON number
`Char` | `'A'`, `'z'` | `"A"`, `"z"` | Chars map to JSON strings
`String` | `"Foo bar"`, `""` | `"Foo bar"`, `""` | Exact mapping
`Maybe a` | `Just 13`, `Nothing` | `13`, `null` | Maybe maps to nullable JSON value
`List a` | `[1, 2, 3]`, `[]` | `[1, 2, 3]`, `[]` | Lists map to JSON arrays
`tuples` | `( 13, False )` | `[13, false]` | Tuples map to arrays
`record types` | `{ foo = 13, bar = False }`  | `{ "foo": 13, "bar": false }` | Records map to objects
`custom types` | `FooBar "hello`, `MyEnum` | `["FooBar", "hello"]`, `"MyEnum"` | see details below
`unit` | `()` | `{}` | 

## How to Generate a Json Schema
Follow the two step s below to generate a Json Schema

* Step 1
Run the ```elm morphir-elm make ``` command to generate an IR
* Step 2
Run the ```elm morphir-elm gen -t JsonSchema``` to generate the Json Schema

**Note** - The generated schema is named `<package-name>.json` by default. But you can specify the filename
optionally for the schema using the -f flag.



\
Next, we will get into some specific cases that may need further explanation.

The rest of the explains how each Morphir type maps to the Json Schema Types.

1. ### [ SDK Types](#sdk-types) 
   #### [1.1. Basic types](#basic-types) 
      [1.1.1. Bool ](#bool)\
      [1.1.2. Int ](#int)\
      [1.1.3. Float ](#float)\
       [1.1.4. Char ](#char)\
      [1.1.5. String ](#string)\
   #### [1.2. Advanced types](#advanced-types) \
      [1.2.1. Decimal](#decimal)\
      [1.2.2. LocalDate ](#localdate)\
      [1.2.3. LocalTime](#localtime)\
      [1.2.4. Month](#month)\
   #### [1.3. Optional values](#optional-values)\
   #### [1.4. Collections](#collections)
    [1.4.1. List ](#list)\
    [1.4.2. Set ](#set) \
    [1.4.3. Dict](#dict) \
   ####  [1.4.5. Results](#result)

2. ### [Composite Types](#composite-types)
   ####  [2.1. Tuples](#tuples) \
   ####  [2.2. Record Types ](#records) \
   ####  [2.3. Custom Types](#custom-types) \
    [2.3.1. General Case ](#general-case) \
    [2.3.2. Special Cases](#special-cases) \
    [- No-arg Constructor](#) \
    [- Single Constructor](#) \





## 1. SDK Types 
###  1.1. Basic types
Basic types
####     1.1.1. Bool
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
which owould validate against
```json
true
```
####    1.1.2. Int
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
####   1.1.3. Float
Float types in Morphir all map to number type in Json Schema. An example is given below

```elm
type Score
    = Float
```
would generate the following schema:

```json
"Score" : {
  "type" : "number"
}
```
Will validate against:

```json
45.5
```

####    1.1.4. Char
```Char``` types in Morphir directly maps to ```string``` type in Json Schema since 
Json Schema does not have a native Char type
Therefore elm model:

```elm
type Grade
    = Char
```
would map to the following schema:

```json
"Grade" : {
  "type" : "string"
}
```
Will validate against:
```json
"A"
```
<h4 id="string">    1.1.5. String</h4>

```String``` types in Morphir directly map to ```string``` type in Json Schema.
Therefore, elm model:

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
Will validate against:
```json
"foo"
```

###  1.2. Advanced types
####    1.2.1. Decimal
Decimal values are would be mapped to string in the JSON schema. The ```elm pattern``` property is 
used to specified the precision.
####         1.2.2. LocalDate
LocalDate types in Morphir are mapped to strings in Json Schema.
The format attribute in the JSON schema is used to provide the format for the date.
####          1.2.3. LocalTime
LocalDate types in Morphir are mapped to strings in Json Schema.
The format attribute in the JSON schema is used to provide the format for the time.
####        1.2.4. Month
Month types in Morphir are mapped OneOf schema type with a enum list of all the month names

#### 1.3. Optional values (Maybe)
A Maybe type in Morphir refers to a value that may not exist. This means that it could either be a value or a null. There are two approaches to handling Maybes.\
1. Set the value of the type to an array of two strings: the type, and "null" \
2. Treat a Maybe as a [custom type](#custom-types) with two constructors: the type and null
Here, we adopt the second approach.
Therefore, the model
\

```elm
type alias Manager =
    Maybe String
```
would map to the schema
```json
"Types.Manager": {
   "oneOf": [
      {
      "type": "null"
      },
      {
      "type": "string"
      }
   ]
}
```

###      1.4. Collections
####        1.4.1. List

An array is  list of items.
Json schema specification supports array validation:
* **List Validation** - each item in the array matches the same schema
* **Tuple Validation** - each item in the array may have a different schema
  Union types in Morphir maps to arrays in Json Schema. Details are given below in the Custom Types sections.
#### Items
The array schema contains the ```items``` keyword. For list validation, this keyword is set to a single schema that would be
used to validate all items in the array
For tuple validation, when we want disallows extra items in the tuple, the 'items' keyword is set to false.

#### Prefix Items
This is a keyword that specifies an array used to hold the schemas for a tuple-validated array.
Each item in prefixItems is a schema that corresponds to each index of the document's array

####         1.4.2. Set
A set is used to define a collection of unique values. A Json Schema can ensure that
each of the items in the array is unique. To achieve this, we map a set to an array and set the ```uniqueItems```
keyword to true.
####      1.4.3. Dict
Since we have an approach for mapping Tuples, a Morphir Dict can be considered as a list of Tuples.
However, the challenge would be to enforce the unique key constraint.
So when we have the Morphir declaration

```elm
type alias acronyms =
    Dict String String
```

Can be represented as  list of list, like so:
```json
[[String, String]]
```

This is expected to validate the following Json document
```json
[["eg", "example"], ["ie", "that is"]]
```
The first item in each list represents the key in the dictionary and right now, we don't have a way to ensure uniqueness of this item

###   1.5. Result
A Result in Elm represents the result of a computation that may fail. Therefore, it can be considered as a custom type with
two constructors: Ok  and Err.
With this approach, we can map a result the same way we map Custom types.

The following declaration 
```elm
type alias Output
    = Result String Int
```
would be equivalent to the following json schema

```json
{
  "oneOf": [
    {
      "type": "array",
      "items": false,
      "prefixItems": [
        {
          "const": "Err"
        },
        {
          "type": "string"
        }
      ],
      "minItems": 2,
      "maxItems": 2
    },
    {
      "type": "array",
      "items": false,
      "prefixItems": [
        {
          "const": "Ok"
        },
        {
          "type": "integer"
        }
      ],
      "minItems": 2,
      "maxItems": 2
    }
  ]
}
```


## 2. Composite Types
Composite types are types composed of other types. The following composite 
types are covered below: Tuples, Records, Custom Types
### 2.1. Tuples
Since tuples represents a list of possibly different types, a Morphir tuple could
be mapped to a tuple-validated array.
For example  ```elm (String, Int)```
would result in:
```json
{
  "type": "array",
  "items": false,
  "prifixitems" : [
    {
      "type": "string"
    },
    {
      "type": "integer"
    }
  ],
  "minItems": 2,
  "maxItems": 2
}
```

### 2.2. Record Types
Record types in Morphir maps to objects in Json schema. The fields of the record maps to properties of the Json Schema object.
The properties of a JSON schema is a list of schemas. The only clarification we need to make is that field names
use a **camel case** naming convention

Example 1
```elm
sample1 =
    { fooBar = "hello"
    , fooBaz = 13
    }
```

Which maps to the following JSON:

```json
{
  "fooBar" : "hello",
  "fooBaz" : 13
}
```


Example 2
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
This validates against the json document:
```json
{
   "Country" : "United States",
   "State" : "Texas",
   "Street" : "25 Rain drive"
}
```

### 2.3. Custom Types 
Custom types in Morphir, are union types with one or more items in the union. These items are called tags or constructors.
Each item has zero or more arguments which are types.
Json Schema does not support custom types natively. So we use the following approach.
* a constructor with its arguments will map to a tuple-validated array where the constructor is the first item in the array
* the schema type for the constructor would be const (explained below)
* the union type itself would then be represented using the "anyOf" keyword

 Custom types are special union types where each subtype is marked with a special tag to make it easier to differentiate. Besides the tag each subtype can also have any number of arguments.
These tags are also called constructors since you can think of them as functions with different names and
arguments that create instances of the same type. 
 Here's an example:

```elm
type Foo 
    = FooBar String
    | FooBaz Int Bool 

sample1 =
    FooBar "hello"
    
sample2 =    
    FooBaz 13 False
```

Our JSON format needs to capture both the tag and the arguments and also connect them together. So we
decided to simply put all of them in an array starting with the tag as the first value:

```json
["FooBar", "hello"]
```

```json
["FooBaz", 13, false]
```

For the tags we use **upper camel case** (which is also called **PascalCase**).

#### 2.2.1. General Case
The following Morphir model:
```elm
type Person
    = Adult String
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
#### 2.3.2. Special Cases
  **No-arg Constructor** \
    As mentioned previously, when a constructor in a union type has zero arguments, then it maps to a ```const``` schema
The model:
```elm
type Currency
    = USD
```
would generate the schema:
```json
"Currency" : {
  "const" : "USD"
}
```

  **- Single Constructor \ **
  When a constructor doesn't have any arguments it behaves like an enum value. The format described
  above would dictate that we map those to single element arrays in JSON but for simplicity we will
  map them to just a string value:

```elm
sample3 =
    MyEnumValue
```

Maps to:

```json
"MyEnumValue"
```



## Null (null)
When a schema specifies a type of null, it has only one acceptable value: null.
In Json, null is equivalent to a value being absent.


## Ref
A schema can reference another schema using the $ref keyword. The valueof the $ref is the URI-reference that is resolved against the base URI.
For reference types in Morphir, the $ref keyword is used to refer to the target schema.
In the example below, the Address field of the Bank schema refers to the Address schema. So the $ref keyword is used:

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
The anyOf keyword is used to relate a schema 
with it's subschemas. 
