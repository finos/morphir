---
id: morphir-spark
title: Mapping Morphir to Spark
---

# Spark - Morphir to Spark mapping

To understand how the Morphir to Apache Spark mapping works let's begin with an example Morphir domain model and business logic that we might want to transpile to Spark. We present the Morphir logic using Elm syntax to make it easy to read:

```elm
type alias RecordA =
    { number1 : Int
    , number2 : Int
    }

type alias RecordB =
    { sum : Int
    , product : Int
    , ratio : Float
    }


job : List RecordA -> List RecordB
job input =
    input
        |> List.filter (\a -> a.field2 < 100)
        |> List.map
            (\a ->
                { sum = a.number1 + a.number2
                , product = a.number1 * a.number2
                , ratio = a.number1 / a.number2
                }
            )
```

The above is a representative example of the base functionality. There are a few constraints that we put on the Elm code to make it possible to translate to Spark initially (later on we might gradually lift those constraints by automatically transforming the logic behind the scenes). Here are the initial restrictions:

- Functions need to get a list of records as input and return a list of records, so that we can directly map to Spark jobs taking a DataSet and returning a DataSet
- The record types in the input and output need to be completely flat and use only built-in SDK types or be enumerations (custom types with only no-argument constructors)
- The input value in the function can only be passed through the following collection operations:
  - [List.filter](https://package.elm-lang.org/packages/elm/core/latest/List#filter) to filter the data set (corresponds to a WHERE clause in SQL)
  - [List.map](https://package.elm-lang.org/packages/elm/core/latest/List#map) to trasform each input row to an output row (corresponds to the SELECT clause in SQL)
- Field expressions can:
  - use any combination of operations from the [Morphir SDK](https://package.elm-lang.org/packages/elm/core/latest/) as long as every intermediary result within the expression is a simple type
  - include `if-then-else` expressions

## Supported Field Types

- [Int](https://package.elm-lang.org/packages/elm/core/latest/Basics#Int)
- [Float](https://package.elm-lang.org/packages/elm/core/latest/Basics#Float)
- [Bool](https://package.elm-lang.org/packages/elm/core/latest/Basics#Bool)
- [String](https://package.elm-lang.org/packages/elm/core/latest/String#String)
- [Maybe](https://package.elm-lang.org/packages/elm/core/latest/Maybe#Maybe)

## Supported Field Operations

- [Basics](https://package.elm-lang.org/packages/elm/core/latest/Basics):
  - All number operations
  - All comparison operations
  - All boolean operations
- [String](https://package.elm-lang.org/packages/elm/core/latest/String)
  - All operations

## Supported DataSet Operations

- [List.filter](https://package.elm-lang.org/packages/elm/core/latest/List#filter)
- [List.map](https://package.elm-lang.org/packages/elm/core/latest/List#map)
