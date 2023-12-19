---
id: snowpark-backend-limitations
title: Snowpark backend limitations
---

# Limitations of the Snowpark backend

The goal of the Snowpark backend is to generate expressions that can take advantage of the **Snowpark** infrastructure. Because of this, there are several language practices that are valid in `Mophir-IR/Elm` that are not supported by this backend. When possible a warning is generated in the code or in the `GenerationReport.md` file.

Some of these limitations include:

## Recursive functions manipulating dataframe expressions

This backend tries to generate as many dataframe expressions as possible. That is why many functions are generated as Scala functions that generate dataframe expression (or [Column](https://docs.snowflake.com/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/Column.html) objects). For example:

For example:

```elm
double : Int -> Int
double x = 
   if x == 0 then
     0
   else 
     x * x
```

Is converted to:

```elm
  def double(
    x: com.snowflake.snowpark.Column
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      (x) === (com.snowflake.snowpark.functions.lit(0)),
      com.snowflake.snowpark.functions.lit(0)
    ).otherwise((x) * (x))
```

As shown above this function is going to return a `Column` instance. This object represents the actual expression tree that is processed by the **Snowpark** library. This transformation makes it impossible to convert functions that make recursive calls. For example:

```elm
factorial : Int -> Int
factorial n =
   if n == 0 then
      1
   else
      n * (factorial (n - 1))
```

The generated Scala code looks like this:

```scala
  def factorial(
    n: com.snowflake.snowpark.Column
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      (n) === (com.snowflake.snowpark.functions.lit(0)),
      com.snowflake.snowpark.functions.lit(1)
    ).otherwise((n) * (mymodel.Basic.factorial((n) - (com.snowflake.snowpark.functions.lit(1)))))
```

Since this code is composed only of nested function calls, there is nothing preventing the execution of the recursive call. This 

```bash
java.lang.StackOverflowError
  com.snowflake.snowpark.Column.$eq$eq$eq(Column.scala:269)
  mymodel.Basic$.factorial(Basic.scala:751)
  mymodel.Basic$.factorial(Basic.scala:753)
  mymodel.Basic$.factorial(Basic.scala:753)
  mymodel.Basic$.factorial(Basic.scala:753)
  mymodel.Basic$.factorial(Basic.scala:753)
  mymodel.Basic$.factorial(Basic.scala:753)
  mymodel.Basic$.factorial(Basic.scala:753)
  mymodel.Basic$.factorial(Basic.scala:753)
  ...
```

## Code that do not manipulate lists of table-like records

To take advantage of this backend, the code being processed has to manipulate lists of table-like records (ex. with fields of only basic). These structure are identified as [DataFrames](https://docs.snowflake.com/en/developer-guide/snowpark/scala/working-with-dataframes).  


## Code that do not follow the supported patterns

The backend assumes some conventions and patterns to determine how to interpret the code that is being processed. These patterns are described in [snowpark-backend-generation](snowpark-backend-generation.md).


## Unsupported elements

There may be situations when this backend cannot convert an element from the **Morphir-IR** . Depending on the scenario the backend generates default expressions or types to indicate that something was not converted. 

For example, given that there is no support for the `List.range` function we can try to convert the following snippet:

```elm
myFunc2: Int -> Int
myFunc2 x =
   let 
       y = x + 1
       z = y + 1
       r = List.range 10 20
   in 
   x + y + z
```

The resulting code is the following:

```scala
  def myFunc2(
    x: com.snowflake.snowpark.Column
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column = {
    val y = (x) + (com.snowflake.snowpark.functions.lit(1))
    
    val z = (y) + (com.snowflake.snowpark.functions.lit(1))
    
    val r = "Call not generated"
    
    ((x) + (y)) + (z)
  }
```

Notice that the `"Call not generated"` expression was generated. Also, the `GenerationReport.md` file is going to include an error message for this function:

```markdown
### MyModel:Basic:myFunc2

- Call to function not generated: Morphir.SDK:List:range
```