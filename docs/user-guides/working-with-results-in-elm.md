---
id: results-in-elm
title: Working With Results in Elm
sidebar_position: 11
---

# Working With Results in Elm - With Morphir Examples
This post explains the Result type in the Elm Programming Language and use cases in Morphir.

##Content
1. [Overview of the Result Type](#)
2. [Mapping Results (map)](#)
3. [Chaining Results (andThen)](#) 
4. [Result Error Handling](#) 
5. [Use Cases in Morphir](#) 


###1. [Overview of the Result Type](#) 
Result is a built-in type in Elm that accepts two arguments: error and value. It represents the result of a computation that has the possibility
of failure. The two types of constructors for the result type are given below:
```
type Result error value
    = Ok value
    | Err error
```

A result could be either: 
 - OK - which means the operation succeeded  
 - Err - which means that the operation failed \
So the Result type has two parameters: error and value. It also has two constructors: Ok and Err.



###2. [Mapping Results (map)](#) 
When a computation returns a Result, it is common to use the map function to further process
the Result. If the result is Ok (which means that it is successful), then the function is
applied  and a value is returned. If however, the result fails, then the error is propagated.
An example is given below taken from the [String.elm](#) file

**Example 1**
This example is taken from the String module 
```
evaluate "" value 
|> Result.map 
    (\val -> Value.Literal () (StringLiteral val))
```
In the snippet, the evaluate function is called which takes two string argumnents
(an empty string and a value) and returns a **Result Error String**. The output of the evaluate
function is transformed to a **Value Literal** using the map function.

**Example 2**
In the example below which is taken from the [List Module](#), we use the map function to
transform the result of the evaluate function (applied to an empty list []) to an empty 
**Value.List** type.

```
listItems 
    |> evaluate [] 
    |> Result.map (Value.List ())
```


**Example 3** \
This example is taken from the [CLI.elm module](#).

```
resultIR : Result Decode.Error IR
resultIR =
    distributionJson
        |> Decode.decodeValue DistributionCodec.decodeVersionedDistribution
        |> Result.map IR.fromDistribution
```
In the snippet, the **Decode.decodeValue** function takes a decoder and a value.
The value argument is the distributionJson returned from IR.fromDistribution 
while the decoder is returned from DistributionCodec.decodeVersionedDistribution function.
The Decode.decodeValue returns a Result. A successful result (which is a distribution) is
transformed into an IR using the map function applied to IR.fromDistribution.



### 3. [Chaining Results (andThen)](#) 
Sometimes we could have a sequence of operations where each of them have the possibility of failure.
The signature for the **andThen** function is given below:

```
andThen : (a -> Result e b) -> Result e a -> Result e b
andThen callback result =
    case result of
      Ok value -> callback value
      Err msg -> Err msg
```
In the code snippet above, the andThen function takes two arguments: 
* **the callback** - this is the function that gets called on the value when the result is OK
* **result** = this is Result type returned by a prior computation



###4. [Result Error Handling](#)
In the previous examples, we covered how to handle successful results. Let's now examine
how to handle errors.
Elm provides the following function that could be used for handling errors with the result type

```
withDefault: a -> Result x a -> a
```
This function returns a specified default value when the result is Err 

```
toMaybe: Result x a -> Maybe a
```
This function returns a specified default value when the result is Err 

```
fromMaybe: x -> Maybe a -> Result x a
```
This function converts a Maybe to a Result 

```
mapError: (x -> y) -> Result x a -> Result y a
```
Just like the map function mentioned earlier, the mapError function allows you to apply a function
to a result if it is an error


###5. [Use Cases in Morphir](#) 
To understand the result type more clearly, we would look at a number of use cases from
the Morphir codebase.

**Returning a Result Type** \
In a computatation that contains the possibility of failure, it would be necessary to 
return a Result type. For example, the code snippet below taken from the JSONBackend.elm 
file contains a function that returns the encoder reference for a given type:

```
genEncodeReference : Type () -> Result Error Scala.Value
genEncodeReference tpe =
    case tpe of
        Type.Variable _ varName ->
            Ok (Scala.Variable ("encode" :: varName |> Name.toCamelCase))
            ...
            ...
```

In the snippet, the genEncoderReference function would have the possibility of failure and
so the return type is **Result Error Scala.Value**. This means that if no failure occurs, 
then a **Scala.Value** type is returned but if failure occurs, then Error is returned.
For **Type.Variable**, the operation produces a **Scala.Variable** type which is then wrapped
into a Result type using the Ok constructor.
This could also achieved by piping the output into Result.Ok.

**Handling Result Using mapError** \
The snippet below shows the use of mapError in handling Error from the Result type. It is
taken from [Incremental Frontend](#) module

```
{-| Converts an elm source into a ParsedModule.
-}
parseSource : ( FilePath.Path, String ) -> Result Error ParsedModule
parseSource ( path, content ) =
    Elm.Parser.parse content
        |> Result.mapError (ParseError path)
        |> Result.map ParsedModule.parsedModule
```
In the example, the parseSource function returns a **Result** type but the **Elm.Parser.parse**
function returns a **Result (List Deadend) RawFile**. This means that we need to transform
both the two parameters of the Result.
The **mapError** transforms the **(List Deadend)** into **Error** while the *map* transforms
the *RawFile* into *ParsedModule* 

**Chaining Result Example**
The example below  shows the use of Result chaining taken from [Spark Backend](#) module.

```
mapFunctionBody : TypedValue -> Result Error Scala.Value
mapFunctionBody body =
    body
        |> RelationalBackend.mapFunctionBody
        |> Result.mapError RelationalBackendError
        |> Result.andThen mapRelation

```

In the *mapFunctionBody* example, **Result.mapError** and **Result.andThen** is used.
First, the **mapFunctionBody** returns a **Result Error Scala.Value**. As explained earlier,
the **mapError** is used to transform the Error using the *RelationalBackendError*. 
The *andThen* is used to chain the result with *mapRelation* (which also returns a Result)
