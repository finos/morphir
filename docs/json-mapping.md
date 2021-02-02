# JSON mapping

This document describes how Morphir maps data to JSON.

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
tuples | `( 13, False )` | `[13, false]` | Tuples map to arrays
record types | `{ foo = 13, bar = False }`  | `{ "foo": 13, "bar": false }` | Records map to objects
custom types | `FooBar "hello`, `MyEnum` | `["FooBar", "hello"]`, `"MyEnum"` | see details below

Next, we will get into some specific cases that may need further explanation.

## Record types

Records in Morphir map directly to objects in JSON. The only clarification we need to make is that field names
use a **camel case** naming convention. Given the below record:

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

## Custom types

Since JSON does not directly support this data type we had to come up with our own encoding. Custom types
are special union types where each subtype is marked with a special tag to make it easier to differentiate
(they are also called tagged unions). Besides the tag each subtype can also have any number of arguments.
These tags are also called constructors since you can think of them as functions with different names and
arguments that create instances of the same type. Here's an example:

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

### Special case: enum values

When a constructor doesn't have ny arguments it behaves like an enum value. The format described 
above would dictate that we map those to single element arrays in JSON but for simplicity w will
map them to just a string value:

```elm
sample3 =
    MyEnumValue
```

Maps to:

```json
"MyEnumValue"
```