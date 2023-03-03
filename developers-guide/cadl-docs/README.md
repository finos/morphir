# [Morphir Type](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type) Mappings To [CADL Type System](https://microsoft.github.io/cadl/docs/language-basics/type-relations/)
### SDK Types to CADL

#### Basic Types
##### [Bool](https://package.elm-lang.org/packages/elm/core/latest/Basics#Bool) 
Boolean, a `true` or `false` value in morphir, maps directly to the `boolean` type in CADL. 
```
alias isValid = boolean
```
        
##### [Int](https://package.elm-lang.org/packages/elm/core/latest/Basics#Int)
In CADL, this maps to the subtype `integer`. The `integer` type assignment is valid CADL, but <br/>
<span style="color: red; font-style:italic;"> Things to note :: </span>
1. When dealing with emitters such as OpenApiSpec(OAS) it defaults to an object. To obtain an actual int value, specify a subtype `int64`.
```
alias Foo = integer;

// when dealing with emitters
alias Foo = int64;
                              |       }
```

##### [Float](https://package.elm-lang.org/packages/elm/core/latest/Basics#Float)
The `float` type in morphir, maps directly to subtype `float` in CADL. <span style="color: red; font-style:italic;">Same issues with `integer` type is applicable </span>
 
```
alias PI = float

// when dealing with emitters
alias Foo = float64;
                             |       }
```
##### [String](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-String)
The `string` type; a sequence of characters, in morphir maps directly to `string` type in CADL.
``` 
alias foo = string 
```
##### [Char](https://package.elm-lang.org/packages/elm/core/latest/Char)
The `char` type is a single character type in morphir and doesn't exist in CADL. An alternative mapping is the `string` type. 
```
alias Char = string
```

### Advanced Types
##### [Decimal](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-Decimal)
The `decimal` type in morphir defines a floating point number with accurate precision. This type is not supported directly in CADL and an alternative mapping is the `string` type.
```
alias Decimal = string
```
##### [LocalDate](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-LocalDate)
The `localDate` type in morphir defines as a gregorian date with no timezone information. This type maps directly to `plainDate` type in CADL. 
```
alias dateOfBirth = plainDate
```
##### [LocalTime](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-LocalTime)
The `localTime` type in morphir defines as basic time without a timezone and its equivalent mapping in CADL is `plainTime` type. 
```
alias LocaTime = plainTime
```
##### [Month](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-Month)
The morphir type `month` derived from a localDate was purposefully created to aid in business modeling. This concept of `month` type does not 
exist in CADL and the alternative mapping is the `string` type.
```
alias Month = string
```
##### [Optional Values(Maybe)](https://package.elm-lang.org/packages/elm/core/latest/Maybe)
The `maybe` type in morphir represents values that or may not exist. This is directly supported in CADL through `optional fields` of models or as alias.
```
Examples : 
    1. As an optional field of a model using the `?:` syntax. 
        model Foo {
            foo ?: string
        }
        
    2. As an alias with of type T and null.
        alias mayBe<T> = T | null
```

### Collections Types
##### [List](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-SDK-List)
The `list` type in morphir, is a collection of items of homogeneous type. Its equivalent mapping in CADL is the `array` type. 
Arrays in CADL are defined using the `T[] or Array<T>`syntax where T, is the type.
```
alias List<T> = T[];
        OR
alias List<T> = Array<T>;
```
        
##### [Set]()
The `set` type is a collection of items where every item or value is unique. This is not supported directly in CADL. 
An alternative mapping is the `array` type. 
```
alias Set<T> = Array<T>; 
```

##### [Dict](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-SDK-Dict)
A dict or dictionary is a collection of unique key-value pairs. In morphir, a dict key could be a simple type; such as `string`, or a complex type; `custom type`. 
This complex key type is not supported directly in CADL. To achieve such behaviour is to define the `dict` type as an` alias` template with the value as an array of tuples. 
```
alias Dict<K,V> = Array<[K,V]> ;
```

##### [Result](https://package.elm-lang.org/packages/elm/core/latest/Result)
The `result` type in morphir is used to manage errors of a computation that may fail. The morphir type `result` returns the second argument if successful else
it returns the first; which is the error. This concept is supported in CADL through the use of `template` alias whose values are tagged union types. 
```
alias Result<E,V> = ["Err", E] | ["Ok", V];
```      

### Composite Types
#### [Tuples](https://package.elm-lang.org/packages/elm/core/latest/Tuple)
The `tuple` type in morphir is data structure that holds elements of the same or different types as a single value. CADL directly support `tuples` as a subtype of array
and hence uses the `[]`  syntax.
```
alias Tuple<T,E> = [T,E];
```
##### [Record Types](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Value#record)
Morphir `record` represents a dictionary of fields where the keys are the field names, and the values are the field values. This maps to `model` type in CADL. 
Models are structures with fields called properties and used to represent data schemas.
```
model FooBarBaz {
    foo: Foo,
    bar: string,
    baz: int, 
}
```    
        
### [Custom Types](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type)
##### General
A `custom` type in morphir is a user defined type used to represent a business term or type. This concept is supported in CADL through aliasing. 
```
// As `alias` of list of Tuples, where the first element represents type name in string followed by its args
alias FooBarBaz 
    = ["Foo", int]
    | ["Bar", string]
    | "Baz" // tuple with 1 item equals the same item.
    
    OR 
// Another representation is alias all tuples.      
alias Foo = ["Foo", int];
alias Bar = ["Bar", string];
alias Baz = "Baz";

alias FooBarBax 
    = Foo 
    | Bar
    | Baz
    
``` 
##### [Special Cases]()
A `custom` type in morphir with all no argument constructors is represented in CADL as an `enum` type.
```
enum Currency {
    USD,
    GBP,
    GHS,
    ...
}
``` 


# Mapping [Cadl feature concepts](https://microsoft.github.io/cadl/language-basics/overview) to [Morphir](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type)

---

| <div style="width:100px"></div>                                                              | CADL Type <div style="width:450px"></div>                                                                                                                                                                                                                                                                                                                  | Morphir Type<div style="width: 350px"></div>                                | Comment <div style="width:350px"></div>                                                                                                                                                                                                                                              |
|----------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [Namespaces](https://microsoft.github.io/cadl/language-basics/namespaces)                    | `namespace Petstore`                                                                                                                                                                                                                                                                                                                                       | `module PetStore exposing (...)`                                            | Namespaces in CADL map to [Modules](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Module) in Morphir                                                                                                                                            |      
| [Models](https://microsoft.github.io/cadl/language-basics/models)                            | `model Dog { name: string;  age: number}`                                                                                                                                                                                                                                                                                                                  | `type alias Dog = { name: string, age: int}`                                | Models in CADL map to [Records](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Value#record) in Morphir                                                                                                                                                   |
| [Enums](https://microsoft.github.io/cadl/language-basics/enums)                              | `enum Direction {East; West; North; South}`                                                                                                                                                                                                                                                                                                                | `type Direction `<br/> `= East` &#124; `West` &#124; `North` &#124; `South` | Enums in CADL map to [Union Types](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type) in Mophir                                                                                                                                                         |
| [Union Type](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type) |||
|                                                                                              | -<span style="color: grey; font-style: italic;" > Unnamed Union <br> `alias Breed = Breagle` &#124; `GermanShepherd` &#124; `GoldenRetriever` <br> <span style="color: grey; font-style: italic;" >- Named Union <br> `union Breed {`<br> &ensp; `beagle: Beagle,` <br> &ensp; `shepherd: GermanShepherd.` <br> &ensp; `retiever: GoldenRetriever`<br> `}` |`type Breed` <br> &ensp; `= Beagle Beagle`<br> &ensp; &ensp; &#124; `Shepherd GermanShepherd ` <br> &ensp; &ensp; &#124; `Retriever GoldenRetriever`| Named unions in CADL maps to a Custom Type with  a `type parameter` in Morphir. Any other detail of the type is captured in Morphir's `Decorators(Custom Attributes).` <br> <span style="color: red; font-style: italic;" >NB: unnamed Unions are currently not supported in morphir |


## [Type Relations](https://microsoft.github.io/cadl/language-basics/type-relations)

##### Boolean
Boolean in CADL, maps to [`bool`](https://package.elm-lang.org/packages/elm/core/latest/Basics#Bool), a `true` or `false` value in Morphir.

##### Integer
In Morphir, this maps to the type [`int`.](https://package.elm-lang.org/packages/elm/core/latest/Basics#Int) The `integer` type assignment is valid CADL, but <br/>
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