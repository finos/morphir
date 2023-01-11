# Mapping [Cadl feature concepts](https://microsoft.github.io/cadl/language-basics/overview) in [Morphir](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type)

---

## 1. Namespaces.
[Namespaces](https://microsoft.github.io/cadl/language-basics/namespaces) in CADL map to [Modules](https://package.elm-lang.org/packages/Morgan-Stanley/morphir-elm/latest/Morphir-IR-Module) in Moprhir.
### Example:
```
CADL:
    namespace PetStore;
```
## 2. Models.
[Models](https://microsoft.github.io/cadl/language-basics/models) in CADL, map to [Records](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Value#record) in Morphir.
### Example:
```
CADL:
    model Dog {
    name: string;
    age: number;
    }
```
## 3. Unions.
[Union](https://microsoft.github.io/cadl/language-basics/unions) in CADL, maps to [`Custom Types`](https://package.elm-lang.org/packages/finos/morphir-elm/18.1.0/Morphir-IR-Type) in Morphir. <br>
<span style="color: red; font-style: italic;" > NB: [Aliases](https://microsoft.github.io/cadl/language-basics/aliases) on CADL has some similarities  with Unnamed union.
### Example:
```
CADL:
    Unnamed union:
        alias Breed = Beagle | GermanShepherd | GoldenRetriever;
        
    Alias:
        alias Options = "one" | "two";
```

## 4. Enums.
[Enums](https://microsoft.github.io/cadl/language-basics/enums) in CADL. map's to a `Custom Types` with no constructor in Morphir.
### Example:
```
CADL:
    Enums:
        enum Direction {
             North,
             East,
             South,
             West,
        }
```
<span style="color: red; font-style: italic;" >NB: String Values of Enums is not supported on Morphir.

# 5. [Type Relations](https://microsoft.github.io/cadl/language-basics/type-relations)

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