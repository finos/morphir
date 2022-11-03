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
2. There can't be two `integer` types in a model, specify subtypes instead. 
```
alias Foo = integer;

// when dealing with emitters
alias Foo = int64;

// invalid in CADL              |       // valid CADL
model Bar {                     |       model Bar {
    x: integer,                 |           x: int64,
    y: integer                  |           y: int64,
}                               |       }
```

##### [Float](https://package.elm-lang.org/packages/elm/core/latest/Basics#Float)
The `float` type in morphir, maps directly to subtype `float` in CADL. <span style="color: red; font-style:italic;">Same issues with `integer` type is applicable </span>
 
```
alias PI = float

// when dealing with emitters
alias Foo = float64;

// invalid in CADL              |       // valid CADL
model Bar {                     |       model Bar {
    x: float,                   |           x: float64,
    y: float                    |           y: float64,
}                               |       }
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
The `result` type in morphir is used to manage errors of a computation that may fail. The morphir type `result` returns the first argument if successful else
it returns the second; the error. This concept is supported in CADL through the use of `template` alias. 
```
alias Result<T,E> = T | E;
```      

### Composite Types
#### [Tuples](https://package.elm-lang.org/packages/elm/core/latest/Tuple)
The `tuple` type in morphir is data structure that holds elements of the same or different types as a single value. CADL directly support `tuples` as a subtype of array
and hence uses the `[]`  syntax of array.
```
alias Tuple<T,E> = Array<[T,E]>;
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