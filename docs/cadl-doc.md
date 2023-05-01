# Morphir-Cadl Mapping
## [Morphir](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type) to [Cadl Type](https://microsoft.github.io/cadl/docs/language-basics/type-relations/) Mappings
This is a documentation of the mapping strategy from Morphir types to Cadl types. This document describes how types in Morphir Models are represented in Cadl. 
Below is a quick overview of the mapping in the table:



|                                                       | Type                                | Cadl Type                                | Comment                                             |
|-------------------------------------------------------|-------------------------------------|------------------------------------------|-----------------------------------------------------|
| [Basic Types](#basic-types)                           |                                     |                                          |                                                     |
|                                                       | `Bool`                              | `boolean`                                |                                                     |
|                                                       | `Int`                               | `int64`                                  |                                                     |
|                                                       | `Float`                             | `float64`                                |                                                     |
|                                                       | `String`                            | `string`                                 |                                                     |
|                                                       | `Char`                              | `string`                                 | Not supported. Mapped to string                     |
| [Advanced Types](#advance-types)                      |                                     |                                          |                                                     |
|                                                       | `Decimal`                           | `string`                                 | Not supported. Mapped to string                     |
|                                                       | `LocalDate`                         | `plainDate`                              |                                                     |
|                                                       | `LocalTime`                         | `plainTime`                              |                                                     |
|                                                       | `Month`                             | `string`                                 |                                                     |
| [Optional Types](#advance-types)                      |                                     |                                          |                                                     |
|                                                       | `Maybe a`                           | `a` &#124; `null`                        |                                                     |
|                                                       | `{ foo: Maybe Float, bar: String }` | `{ foo ?: float64, bar: string }`        | Optional Fields are expressed using the `?:` syntax |
| [Collection Types](#collection-types)                 |                                     |                                          |                                                     |
|                                                       | `List A`                            | `Array<A>`                               |                                                     |
|                                                       | `Set B`                             | `Array<B>`                               | Not Supported. Mapped to Array                      |
|                                                       | `Dict A B`                          | `Array<[A,B]>`                           | Not Supported. Mapped to Array                      |
| [Composite Types](#composite-types)                   |                                     |                                          |                                                     |
| - [Tuple](#tuples)                                    | `(Int, String)`                     | `[int64, string]`                        |                                                     |
| - [Result](#result)                                   | `Result e v`                        | `["Err", e]` &#124; `["Ok", v]`          | Expressed as tagged unions                          |
| - [Record](#record-types)                             | `{ foo: Int, bar: String }`         | `{ foo: int64, bar: string }`            |                                                     |
| - [Union Types](#custom-types)                        | `Foo Int` &#124; `Bar String`       | `["Foo", int64]` &#124; `["Bar, string]` |                                                     |
| - [No Constructor Args (Special Case)](#custom-types) | `Foo` &#124; `Bar` &#124; `Baz`     | `Foo` &#124; `Bar` &#124; `Baz`          | Represented as Enum                                 |


### Basic Types
##### [Bool](https://package.elm-lang.org/packages/elm/core/latest/Basics#Bool)
Boolean, a `true` or `false` value in morphir, maps directly to the `boolean` type in CADL.

Elm:
```elm
type alias IsApplicable = 
    Bool
```
Cadl
```
alias IsApplicable = boolean;
```


##### [Int](https://package.elm-lang.org/packages/elm/core/latest/Basics#Int)
The `Int` type in morphir is a set of natural numbers(positive and negative) without a fraction component, maps directly to the `integer` type in cadl.

Elm:
```elm
type alias Foo = 
    Int
```
Cadl:
```cadl
alias Foo = int64;
```
<span style="color: red; font-style:italic;"> Note: </span>

The `integer` type assignment is valid in Cadl but would default to **object** when dealing with the **OAS emitters**.

##### [Float](https://package.elm-lang.org/packages/elm/core/latest/Basics#Float)
The `Float` type; floating point number, in morphir maps directly to the `float` type in CADL.

Elm:
```elm
type alias Pi = 
    Float
```
Cadl:
```cadl
alias Pi = float64;
```
<span style="color: red; font-style:italic;">Note: </span>

The `float` type assignment is valid in Cadl but would default to **object** when dealing with the **OAS emitters**.

##### [String](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-String)
The `String` type; a sequence of characters, in morphir maps directly to `string` type in CADL.

Elm:
``` elm
type alias Address = 
    String
```
Cadl:
```cadl
alias Address = string ;
```

##### [Char](https://package.elm-lang.org/packages/elm/core/latest/Char)
The `char` type is a single character type in morphir and doesn't exist in Cadl. An alternative mapping is the `string` type.

Elm:
``` elm
type alias AccountGroup = 
    Char
```
Cadl:
```cadl
alias AccountGroup = string;
```

### Advance Types
##### [Decimal](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-Decimal)
The `decimal` type in morphir defines a floating point number with accurate precision. This type is not supported directly in CADL and an alternative mapping is the `string` type.

Elm:
```elm
import Morphir.SDK.Decimal exposing (Decimal)

type alias Price = 
    Decimal
```
Cadl:
```cadl
alias Price = string
```
##### [LocalDate](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-LocalDate)
The `localDate` type in morphir defines as a gregorian date with no timezone information. This type maps directly to `plainDate` type in CADL.

Elm:
```elm
import Morphir.SDK.LocalDate exposing (LocalDate)

type alias DateOfBirth = 
    LocalDate
```
Cadl:
```cadl
alias dateOfBirth = plainDate;
```
##### [LocalTime](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-LocalTime)
The `localTime` type in morphir defines as basic time without a timezone and its equivalent mapping in CADL is `plainTime` type.

Elm:
```elm
import Morphir.SDK.LocalTime exposing (LocalTime)

type alias CurrentTime =
    LocalTime
```
Cadl:
```cadl
alias currentTime = plainTime;
```

##### [Month](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-Month)
The morphir type `month` derived from a localDate was purposefully created to aid in business modeling. This concept of `month` type does not
exist in CADL and the alternative mapping is the `string` type.

Elm:
```elm
import Morphir.SDK.Month exposing (Month)

type alias CurrentMonth =
    Month
```
Cadl:
```cadl
alias purchaseMonth = string;
```

##### [Optional Values(Maybe)](https://package.elm-lang.org/packages/elm/core/latest/Maybe)
The `maybe` type in morphir represents a type that may or may not exist. The type could exist as a standalone type or a field type in a record and both scenarios are supported directly in Cadl. 

1. `maybe` as a standalone type, is presented in cadl as a union of the type or null using the pipe `|` syntax.

   Elm:
    ```elm
    type alias Foo = 
        Maybe Int
   ```
   Cadl:
    ```cadl
   alias Foo = int64 | null
    ```
   
2. `maybe` as a field type in a record, is represented as `optional field` in a model in cadl using `optional field` `?:` syntax.

   Elm:
    ```elm
    type alias FooBarBaz = 
        { foo: Int
        , bar: Float
        , baz: Maybe String
        }
    ```
   Cadl:
    ```cadl
    model FooBarBaz {
        foo : int64;
        bar : float;
        baz ?: string
    }
   ``` 

3. In a Scenario where a field type is `maybe` of another `maybe` type, it is represented as an `optional field` of the `union` type. 

   Elm:
    ```elm
    type alias FooBarBaz = 
        { foo: Int
        , bar: Float
        , baz: Maybe (Maybe String)
        }
    ```
   Cadl:
    ```cadl
    model FooBarBaz {
        foo : int64;
        bar : float;
        baz ?: string | null
    }
   ```
   _<span style="color:red">Note:</span>_ \
   _In the scenario of multiple `maybe` type for a field in a model, it shall be represented as just the type or null_

### Collection Types
##### [List](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-List)
The `list` type in morphir, is a collection of items of homogeneous type. Its equivalent mapping in CADL is the `array` type and is defined using the `Array<T>` syntax where T, is the type.

Elm:
```elm
type alias Foo = 
    List Int
    
type alias Bar a = 
    List a
```
Cadl:
```cadl
alias Foo = Array<int64>;

alias Bar<A> = Array<A>;
```

##### [Set](https://package.elm-lang.org/packages/elm/core/latest/Set)
The `set` type is a collection of items where every item or value is unique. This is not supported directly in CADL hence its alternative mapping is to use the `array` type.

Elm:
```elm
type alias  Foo = 
    Set Int
    
type  alias Bar a =
    Set a
```
Cadl:
```cadl
alias Foo = Array<int64>;

alias Bar<A> = Array<A>; 
```

##### [Dict](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-SDK-Dict)
A dict or dictionary is a collection of unique key-value pairs. In morphir, a dict key could be a simple type such as `string`, or a complex type such as a `custom type`.
This complex key type is not supported directly in CADL. To achieve such behaviour is to define the `dict` type as an` alias` template with the value as an array of tuples.

Elm:
```elm
type alias Foo = 
    Dict String Int
    
type alias Bar a b = 
    Dict a b
```
Cadl
```cadl
alias Foo = Array<[string,int64]>;

alias Bar<A,B> = Array<[A,B]> ;
```

##### [Result](https://package.elm-lang.org/packages/elm/core/latest/Result)
The `result` type in morphir is used to manage errors of a computation that may fail. The morphir type `result` returns the second argument if successful else
it returns the first; which is the error. This concept is supported in CADL through the use of `template` alias with tagged union types.

Elm:
```elm
type alias Foo e v= 
    Result e v
```
Cadl:
```cadl
alias Foo<E,V> = ["Err", E] | ["Ok", V];
```      

### Composite Types
#### [Tuples](https://package.elm-lang.org/packages/elm/core/latest/Tuple)
The `tuple` type in morphir is data structure that holds elements of the same or different types as a single value. CADL directly support `tuples` using the `[]`  syntax.

Elm:
```elm
type alias Foo = 
    ( String, Int )
    
type alias Bar a b = 
    ( a, b )
```
Cadl:
```cadl
alias Foo = [string, int64];

alias Bar<A,B> = [A, B];
```
##### [Record Types](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Value#record)
Morphir `record` represents a dictionary of fields where the keys are the field names, and the values are the field values. This maps to `model` type in CADL.
Models are structures with fields called properties and used to represent data schemas.

Elm:
```elm
type  alias FooBarBaz = 
   { foo: Int
     , bar: String
     , baz: Float
   }
```
Cadl:
```cadl
model FooBarBaz {
    foo: integer,
    bar: string,
    baz: float, 
}
```    

### [Custom Types](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type)
##### [General Case](#)
A `custom` type in morphir is a user defined type used to represent a business term or type. This concept is not directly supported in CADL but can be achieved
as tagged `union` of Tuples, where the first element represents type name in string, followed by its arguments.

Elm:
```elm
type FooBarBaz 
    = Foo Int
    | Baz String
    | Bar 
```

Cadl:
```cadl
alias FooBarBaz =  ["Foo", int64] | ["Bar", string] | "Baz";   
``` 
##### [Special Case](#)
A `custom` type in morphir whose constructors have no arguments would be represented in CADL as an `enum` type.

Elm:
```elm
type Currency 
    = USD
    | GBP 
    | GHS
```
Cadl:
```
enum Currency {
    USD,
    GBP,
    GHS,
}
``` 


# Mapping [Cadl feature concepts](https://microsoft.github.io/cadl/language-basics/overview) to [Morphir](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type)

---

| <div style="width:100px"></div>                                                              | CADL Type <div style="width:450px"></div>                                                                                                                                                                                                                                                                                                                                                | Morphir Type<div style="width: 350px"></div>                                                                                                               | Comment <div style="width:350px"></div>                                                                                                                                                                                                                                                       |
|----------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [Namespaces](https://microsoft.github.io/cadl/language-basics/namespaces)                    | `namespace Petstore`                                                                                                                                                                                                                                                                                                                                                                     | `module PetStore exposing (...)`                                                                                                                           | Namespaces in CADL map to [Modules](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Module) in Morphir                                                                                                                                                     |      
| [Models](https://microsoft.github.io/cadl/language-basics/models)                            | `model Dog { name: string;  age: number}`                                                                                                                                                                                                                                                                                                                                                | `type alias Dog = { name: string, age: int}`                                                                                                               | Models in CADL map to [Records](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Value#record) in Morphir                                                                                                                                                            |
| [Enums](https://microsoft.github.io/cadl/language-basics/enums)                              | `enum Direction {East; West; North; South}`                                                                                                                                                                                                                                                                                                                                              | `type Direction `<br/> `= East` &#124; `West` &#124; `North` &#124; `South`                                                                                | Enums in CADL map to [Union Types](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type) in Mophir                                                                                                                                                                  |
| [Union Type](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type) |||
|                                                                                              | -<span style="color: grey; font-style: italic;" > Unnamed Union </span> <br /> `alias Breed = Breagle` &#124; `GermanShepherd` &#124; `GoldenRetriever` <br /> <span style="color: grey; font-style: italic;" >- Named Union </span> <br /> `union Breed {`<br /> &ensp; `beagle: Beagle,` <br /> &ensp; `shepherd: GermanShepherd.` <br /> &ensp; `retiever: GoldenRetriever`<br /> `}` | `type Breed` <br /> &ensp; `= Beagle Beagle`<br /> &ensp; &ensp; &#124; `Shepherd GermanShepherd ` <br /> &ensp; &ensp; &#124; `Retriever GoldenRetriever` | Named unions in CADL maps to a Custom Type with  a `type parameter` in Morphir. Any other detail of the type is captured in Morphir's `Decorators(Custom Attributes).` <br /> <span style="color: red; font-style: italic;" >NB: unnamed Unions are currently not supported in morphir</span> |


## [Type Relations](https://microsoft.github.io/cadl/language-basics/type-relations)

##### Boolean
Boolean in CADL, maps to [`bool`](https://package.elm-lang.org/packages/elm/core/latest/Basics#Bool), a `true` or `false` value in Morphir.

##### Integer
In Morphir, this maps to the type [`int`.](https://package.elm-lang.org/packages/elm/core/latest/Basics#Int) The `integer` type assignment is valid CADL, but \
<span style="color: red; font-style:italic;"> Things to note :: </span>
1. When dealing with emitters such as OpenApiSpec(OAS) it defaults to an object. To obtain an actual int value, specify a subtype `int64`.

##### Float
The `float` type in CADL, maps directly to type [`float`](https://package.elm-lang.org/packages/elm/core/latest/Basics#Float) in Morphi. <span style="color: red; font-style:italic;">Same issues with `integer` type is applicable </span>

##### String
The `string` type, in CADL maps directly to [`string`](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-String) type in Morphir, a sequence of characters,

##### PlainDate
`PlainDate` type in CADL, maps to [`localDate`](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-LocalDate) type in morphir, defined as a gregorian date with no timezone information. 

##### PlainTime
The `PlainTime` in CADL map's to [`localTime`](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-LocalTime) type in morphir, defined as basic time without a timezone.