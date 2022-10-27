# Json Schema Backend
This is a documentation a of the Json Schema backend for generating Json Schema. 
This document describes how Morphir Models maps to Json Schema.
Json Schema Reference can be found [here](http://json-schema.org/understanding-json-schema/reference/index.html)
<br>
Additional reading:
* [Sample Json Schema](json-schema-mappings.json)
* [Json Mapping](json-mapping.md)


The rest of the explains how each Morphir type maps to the Json Schema Types.

1. ### [ SDK Types](#sdk-types) <br>
   #### [1.1. Basic types](#basic-types) <br>
      [1.1.1. Bool ](#bool)<br>
      [1.1.2. Int ](#int)<br>
      [1.1.3. Float ](#float)<br>
       [1.1.4. Char ](#char)<br>
      [1.1.5. String ](#string)<br>
   #### [1.2. Advanced types (Unsupported)](#advanced-types) <br>
      [1.2.1. Decimal (Unsupported)](#decimal)<br>
      [1.2.2. LocalDate (Unsupported)](#localdate)<br>
      [1.2.3. LocalTime (Unsupported)](#localtime)<br>
      [1.2.4. Month (Unsupported)](#month)<br>
   #### [1.3. Optional values](#optional-values)<br>
   #### [1.4. Collections](#collections)
    [1.4.1. List ](#list)<br>
    [1.4.2. Set ](#set) <br>
    [1.4.3. Dict (Unsupported)](#dict) <br>
   ####  [1.4.5. Results (Unsupported)](#result)

2. ### [Composite Types](#composite-types)
   ####  [2.1. Tuples (Unsupported)](#tuples) <br>
   ####  [2.2. Record Types ](#records) <br>
   #### & [2.3. Custom Types](#custom-types) <br>
    [2.3.1. General Case ](#general-case) <br>
    [2.3.2. Special Cases](#special-cases) <br>
    [- No-arg Constructor](#) <br>
    [- Single Constructor](#) <br>





<h2 id="sdk-types">1. SDK Types </h2>
<h3 id="basic-types">   1.1. Basic types</h3>
Basic types
<h4 id="bool">     1.1.1. Bool </h4>
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
<h4 id="int">     1.1.2. Int</h4>
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
<h4 id="float">    1.1.3. Float</h4>
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

<h4 id="char">     1.1.4. Char</h4>
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

<h3 id="advanced-types">  1.2. Advanced types</h3>
<h4 id="decimal">      1.2.1. Decimal </h4>
<h4 id="localdate">       1.2.2. LocalDate</h4>
<h4 id="localtime">        1.2.3. LocalTime</h4>
<h4 id="month">        1.2.4. Month</h4>
<h3 id="optional-values">   1.3. Optional values (Maybe)</h3>
<p> A Maybe type in Morphir refers to a value that may not exist. This means that it could either be a value or a null. There are two approaches to handling Maybes.<br>
1. Set the value of the type to an array of two strings: the type, and "null" <br>
2. Treat a Maybe as a [custom type](#custom-types) with two constructors: the type and null
Here, we adopt the second approach.
Therefore, the model
<br>

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

<h3 id="collections">   1.4. Collections</h3>
<h4 id="list">     1.4.1. List</h4>

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

<h4 id="set">      1.4.2. Set </h4>
A set is used to define a collection of unique values. A Json Schema can ensure that
each of the items in the array is unique. To achieve this, we map a set to an array and set the ```uniqueItems```
keyword to true.
<h4 id="dict">      1.4.3. Dict </h4>
<h3 id="result">   1.5. Result</h3>

<h2 id="composite-types">2. Composite Types </h2>
Composite types are types composed of other types. The following composite 
types are covered below: Tuples, Records, Custom Types
<h3 id="tuples">2.1. Tuples</h3>
<h3 id="record-types">2.2. Record Types </h3>
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
This validates against the json document:
```json
{
   "Country" : "United States",
   "State" : "Texas",
   "Street" : "25 Rain drive"
}
```

<h3 id="custom-types">2.3. Custom Types</h3> <br>
Custom types in Morphir, are union types with one or more items in the union. These items are called tags or constructors.
Each item has zero or more arguments which are types.
Json Schema does not support custom types natively. So we use the following approach.
* a constructor with its arguments will map to a tuple-validated array where the constructor is the first item in the array
* the schema type for the constructor would be const (explained below)
* the union type itself would then be represented using the "anyOf" keyword

<h4 id="general-case">2.2.1. General Case</h4>
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
<h4 id="special-cases">2.3.2. Special Cases </h4>
  **- No-arg Constructor <br>**
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

  **- Single Constructor <br>**



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
The anyOf keyword is used to relate a schema with it's subschemas. 
