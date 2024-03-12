---
id: snowpark-backend-value-mappings
title: Snowpark backend value mappings
---

# Value mappings for DataFrame operations

This document contains a description of how different kinds of **Morphir-IR** elements are generated to Scala with the Snowpark API.

## Literals

*Source*

```elm
10
"Hello"
True
```

*Target*

```Scala
com.snowflake.snowpark.functions.lit(10)
com.snowflake.snowpark.functions.lit("Hello")
com.snowflake.snowpark.functions.lit(true)
```

## Field access values

Field access expressions like `a.b` are converted depending on the value that is being accessed. For example the following function contains an access to the `lastName` field of the `Employee` record:

*Source* 

```elm
checkLastName : String -> Employee -> Bool
checkLastName name employee =
   if employee.lastName == name then
      True
   else
      False
```

*Target* 

```scala
  def checkLastName(
    name: com.snowflake.snowpark.Column
  )(
    employee: myModel.Basic.Employee
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      (employee.lastName) === (name),
      com.snowflake.snowpark.functions.lit(true)
    ).otherwise(com.snowflake.snowpark.functions.lit(false))
```

As presented above the `employee.lastName` expression in Elm was generated as `employee.lastName`.

## Variable values

Variable access like `myValue` are almost always converted to  variable accesses in Scala. There are few exceptions like access to global elements where identifiers are generated fully qualified.

## Constructor call values

Constructor invocations are generated depending of the current strategy being used by the backend.  Some cases include:

### Custom type without parameters

*Source*

```elm
type CardinalDirection 
    = North
    | South
    | East
    | West

myFunc : CardinalDirection
myFunc =
    let 
        direction = North
    in
    direction
```

*Target*

```scala
object CardinalDirection{

  def East: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("East")
  
  def North: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("North")
  
  def South: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("South")
  
  def West: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("West")

}

def myFunc: com.snowflake.snowpark.Column = {
  val direction = myModel.Basic.CardinalDirection.North
  
  direction
}
```

Notice that the call to construct `North` was replaced by an access to the helper object `CardinalDirection` .

### Custom type with parameters

In this case the convention is use a JSON object to represent values. For example:

*Source*

```elm
type TimeRange =
   Zero
   | Seconds Int
   | MinutesAndSeconds Int Int

createMinutesAndSecs : Int -> Int -> TimeRange
createMinutesAndSecs min sec =
   MinutesAndSeconds min sec
```

*Target*

```scala
  def createMinutesAndSecs(
    min: com.snowflake.snowpark.Column
  )(
    sec: com.snowflake.snowpark.Column
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.object_construct(
      com.snowflake.snowpark.functions.lit("__tag"),
      com.snowflake.snowpark.functions.lit("MinutesAndSeconds"),
      com.snowflake.snowpark.functions.lit("field0"),
      min,
      com.snowflake.snowpark.functions.lit("field1"),
      sec
    )
```

### Returning records from functions

In the case that a function returns a record, an [array](https://docs.snowflake.com/en/sql-reference/data-types-semistructured#array) is created to store the data.

*Source*

```elm
type alias EmpRes = 
   { code : Int
   , name : String
   }

applyProcToEmployee : Employee -> Maybe EmpRes
applyProcToEmployee  employee = 
   if  employee.lastName == "Solo" then
     Just <| EmpRes 1010 employee.firstName
   else
     Nothing 
```

*Target*

```scala
  def applyProcToEmployee(
    employee: myModel.Basic.Employee
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      (employee.lastName) === (com.snowflake.snowpark.functions.lit("Solo")),
      com.snowflake.snowpark.functions.array_construct(
        com.snowflake.snowpark.functions.lit(1010),
        employee.firstName
      )
    ).otherwise(com.snowflake.snowpark.functions.lit(null))
```

## List literal values

Literal lists are converted a Scala [Seq](https://www.scala-lang.org/api/2.12.x/scala/collection/Seq.html) .

*Source*

```elm
someNames : List String
someNames = [ "Solo", "Jones" ]
```

*Target*

```scala
  def someNames: Seq[com.snowflake.snowpark.Column] =
    Seq(
      com.snowflake.snowpark.functions.lit("Solo"),
      com.snowflake.snowpark.functions.lit("Jones")
    )
```

Sometimes that mapping function for an specific builtin function like `List.member` maybe change the conversion of literal lists.

## Case/of values

[Case/of](https://guide.elm-lang.org/types/pattern_matching) expressions are converted to a series of [when/otherwise](https://docs.snowflake.com/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/CaseExpr.html#when(condition:com.snowflake.snowpark.Column,value:com.snowflake.snowpark.Column):com.snowflake.snowpark.CaseExpr) expressions.

*Source*
 
```elm
type CardinalDirection 
    = North
    | South
    | East
    | West

toSpString : CardinalDirection -> String
toSpString direction =
   case direction of
      North -> 
         "Norte"
      South ->
         "Sur"
      East ->
         "Este"
      West ->
         "Oeste"
```

*Target*

```scala
  def toSpString(
    direction: com.snowflake.snowpark.Column
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      (direction) === (myModel.Basic.CardinalDirection.West),
      com.snowflake.snowpark.functions.lit("Oeste")
    ).when(
      (direction) === (myModel.Basic.CardinalDirection.East),
      com.snowflake.snowpark.functions.lit("Este")
    ).when(
      (direction) === (myModel.Basic.CardinalDirection.South),
      com.snowflake.snowpark.functions.lit("Sur")
    ).when(
      (direction) === (myModel.Basic.CardinalDirection.North),
      com.snowflake.snowpark.functions.lit("Norte")
    )
```

## If/then/else values

`If/then/else` expressions are converted to a series of [when/otherwise](https://docs.snowflake.com/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/CaseExpr.html#when(condition:com.snowflake.snowpark.Column,value:com.snowflake.snowpark.Column):com.snowflake.snowpark.CaseExpr) expressions.

*Source*

```elm
if employee.lastName == name then
  True
else
  False
```

*Target*

```scala
  def checkLastName(
    name: com.snowflake.snowpark.Column
  )(
    employee: myModel.Basic.Employee
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      (employee.lastName) === (name),
      com.snowflake.snowpark.functions.lit(true)
    ).otherwise(com.snowflake.snowpark.functions.lit(false))
```

## Let definition values

`Let` expressions are converted to a sequence of Scala `val` declarations:

*Source*

```elm
myFunc2: Int -> Int
myFunc2 x =
   let 
       y = x + 1
       z = y + 1
   in 
   x + y + z
```

*Target*

```scala
  def myFunc2(
    x: com.snowflake.snowpark.Column
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column = {
    val y = (x) + (com.snowflake.snowpark.functions.lit(1))
    
    val z = (y) + (com.snowflake.snowpark.functions.lit(1))
    
    ((x) + (y)) + (z)
  }
```

## Tuple values

Tuples are treated as Snowflake  [arrays](https://docs.snowflake.com/en/sql-reference/data-types-semistructured#array) . For example:

*Source*

```elm
let 
    y = x + 1
    z = y + 1
in 
(x, y, z)
```

*Target*

```scala
{
  val y = (x) + (com.snowflake.snowpark.functions.lit(1))

  val z = (y) + (com.snowflake.snowpark.functions.lit(1))

  com.snowflake.snowpark.functions.array_construct(
    x,
    y,
    z
  )
}
```

## Record values

Record creation is generated depending of the context where the mapping occurs. 

For example, a sequence of arguments to `DataFrame.select` is created for a record is created as part of a `List.map` operation.

```elm
trades
    |> List.map
        (\t ->
            { product = t.productID
            , qty = t.quantity
            }
        )
```

This generates:

```scala
trades.select(
  tradesColumns.productID.as("product"),
  tradesColumns.quantity.as("qty")
)
```

## User defined function invocation values

User defined functions are generated as Scala methods . This backend define the functions using [multiple parameter lists](https://docs.scala-lang.org/tour/multiple-parameter-lists.html) . 

```elm
aValue = addThreeNumbers 10 20 30

addThreeNumbers : Int -> Int -> Int -> Int 
addThreeNumbers x y z =
   x + y + z

addTwo : Int -> Int -> Int
addTwo = addThreeNumbers 2 
```

*Target*

```scala
  def aValue: TypeNotConverted =
    myModel.Basic.addThreeNumbers(com.snowflake.snowpark.functions.lit(10))(com.snowflake.snowpark.functions.lit(20))(com.snowflake.snowpark.functions.lit(30))
  
  def addThreeNumbers(
    x: com.snowflake.snowpark.Column
  )(
    y: com.snowflake.snowpark.Column
  )(
    z: com.snowflake.snowpark.Column
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    ((x) + (y)) + (z)
  
  def addTwo: com.snowflake.snowpark.Column => com.snowflake.snowpark.Column => com.snowflake.snowpark.Column =
    myModel.Basic.addThreeNumbers(com.snowflake.snowpark.functions.lit(2))
```

## Builtin function invocation values

Builtin functions are converted using different strategies depending on each case. The following document contains a description of this case.

# Value mappings for plain Scala operations

Although few operations are supported, there are support for converting functions classified as "complex" (functions that receive or return non-Dataframe compatible values).


