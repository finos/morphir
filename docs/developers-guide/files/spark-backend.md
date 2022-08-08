# **Spark Backend/API Documentation**
This is the entry point for the Spark Backend.

# The Spark API
The Spark API defines types for working with Spark.


## Values
The current Spark API defines the following values:

**_spark_** <br>
This is a variable maps to a Scala value

**_dataFrame_** <br>
A DataFrame maps to a Scala type and references org.apache.spark.sql.DataFrame.
A dataframe is an untyped view of a spark datase. A dataframe is a dataset of Rows


```
dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"
```

<br>

**_literal_**  <br>
A literal returns a Scala.Value by applying a Scala.Ref type to a list of arguments.
```
dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"
```


_**column**_  <br>
This is a reference to a column in a Dataframe. This returns a Scala value by applying a reference to column
to a string literal representing the name of the column
```
dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"
```


_**when**_  <br>
This method takes condition and a then branch and returns a Scala value



**_andWhen_**  <br>
This method takes  three parameters: a condition, a then branch and soFar and return a new value


**_otherwise_**  <br>
This method takes an elseBranch and a soFar and returns new Scala Value
```
dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"
```


_**alias**_  <br>
An alias is used to reference column name, typed column and data set.
```
dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"
```


**_select_**  <br>
Select is used to represent a projection in a relation. It takes a list of columns and returns
a Scala Value representing a dataset

```
select : List Scala.Value -> Scala.Value -> Scala.Value
select columns from =
    Scala.Apply
        (Scala.Select
            from
            "select"
        )
        (columns
            |> List.map (Scala.ArgValue Nothing)
        )
```

**_filter_**  <br>
This method is used to return a subset of the data items from a dataset

```
filter : Scala.Value -> Scala.Value -> Scala.Value
filter predicate from =
    Scala.Apply
        (Scala.Select
            from
            "filter"
        )
        [ Scala.ArgValue Nothing predicate
        ]
```


_**join**_  <br>
This function is used to represent a join operation between two or more relations.
```
filter : Scala.Value -> Scala.Value -> Scala.Value
filter predicate from =
    Scala.Apply
        (Scala.Select
            from
            "filter"
        )
        [ Scala.ArgValue Nothing predicate
        ]
```

_**case statements**_ <br>
Simple case statements of:
* a series of literals
* ends with a default case

Are translated into Spark as a chain of `when` expressions ending with an `otherwise`
i.e.
```
case a.age of                                                                           
    13 ->                                                                               
        True
    5->                                                                                 
        False                                                                           
    _ ->                                                                                
        False                                                                           
```
is translated to
```
org.apache.spark.sql.functions.when(
    (org.apache.spark.sql.functions.col("age")) === (13),
    true  
).when(         
    (org.apache.spark.sql.functions.col("age")) === (5),
    false
).otherwise(false)
```

_**List.member constructs**_ <br>
When List.member is used in conjunction with a List.filter function, such as in the following examples:
```
testEnumListMember : List { product : Product } -> List { product : Product }
testEnumListMember source =
    source
        |> List.filter
            (\a ->
                List.member a.product [ Knife, Plates ]
            )

testStringListMember : List { name : String } -> List { name : String }
testStringListMember source =
    source
        |> List.filter
            (\a ->
                List.member a.name [ "Upright Chair", "Small Table" ]
            )

testIntListMember : List { ageOfItem : Int } -> List { ageOfItem : Int }
testIntListMember source =
    source
        |> List.filter
            (\a ->
                List.member a.ageOfItem [ 19, 20, 21 ]
            )
```
The code is translated into a Spark 'Column.isin()' call. 
For example, the three Elm snippets above are translated into this Spark code:
```
  def testEnumListMember(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter(org.apache.spark.sql.functions.col("product").isin(
      "Knife",
      "Plates"
    ))
  
  def testStringListMember(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter(org.apache.spark.sql.functions.col("name").isin(
      "Upright Chair",
      "Small Table"
    ))
  
  def testIntListMember(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter(org.apache.spark.sql.functions.col("ageOfItem").isin(
      19,
      20,
      21
    ))
```

## Aggregations
The current Spark API recognizes the following patterns as aggregations:

```
source
    |> List.map mappingFunction
    |> (\a ->
        [{
            label = aggregationFunction a
        }]
    )
```
Where 'mappingFunction' could be a Lambda or a FieldFunction (e.g. '.fieldName').
And 'label' can be any alias for the returned column.
And 'aggregationFunction' is one of:
* List.minimum
* List.maximum
* List.sum
* List.length

Such code would generate Spark of the form
```
source.select(aggregationFunction(org.apache.spark.sql.col("fieldName")).alias("label"))
```


## Types
The current Spark API processes the following types:

_**Bool**_ <br>
Values translated form basic Elm Booleans are treated as basic Scala Booleans, i.e.
```
testBool : List { foo : Bool } -> List { foo : Bool }
testBool source =
    source
        |> List.filter
            (\a ->
                a.foo == False
            )
```
gets translated into
```
  def testBool(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter((org.apache.spark.sql.functions.col("foo")) === (false))
```

_**Float**_ <br>
Values translated from basic Elm Floating-point numbers are treated as basic Scala Doubles.
They use `org.apache.spark.sql.types.DoubleType` and their literals do not have a trailing 'f', i.e. `1.23` not `1.23f`.
i.e.
```
testFloat : List { foo : Float } -> List { foo : Float }
testFloat source =
    source
        |> List.filter
            (\a ->
                a.foo == 9.99
            )
```
gets translated into
```
  def testFloat(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter((org.apache.spark.sql.functions.col("foo")) === (9.99))
```

_**Int**_ <br>
Values translated from basic Elm Integers are treated as basic Scala Integers, i.e.
```
testInt : List { foo : Int } -> List { foo : Int }
testInt source =
    source
        |> List.filter
            (\a ->
                a.foo == 13
            )
```
gets translated into
```
  def testInt(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter((org.apache.spark.sql.functions.col("foo")) === (13))
```

_**String**_ <br>
Values translated from basic Elm Strings are treated as basic Scala Strings, i.e.
```
testString : List { foo : String } -> List { foo : String }
testString source =
    source
        |> List.filter
            (\a ->
                a.foo == "bar"
            )
```
gets translated into
```
  def testString(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter((org.apache.spark.sql.functions.col("foo")) === ("bar"))
```

_**Enum**_ <br>
Elm Union types with no arguments (or Constructors in Morphir IR), are translated into String Literals.
For instance:
```
testEnum : List { product : Product } -> List { product : Product }
testEnum source =
    source
        |> List.filter
            (\a ->
                a.product == Plates
            )
```
gets translated into
```
  def testEnum(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter((org.apache.spark.sql.functions.col("product")) === ("Plates"))
```

Currently the implementation doesn't check that the Constructor has no arguments. 
Nor does the current implementation check whether a Constructor has Public access, and only consider those to be Enums.

_**Maybe**_ <br>
Maybes are how Elm makes it possible to return a value or Nothing, equivalent to null in other languages.
In Spark, all pure Spark functions and operators handle null gracefully
(usually returning null itself if any operand is null).

**Just** <br>
In Elm, comparison against Maybes must be explicitly against `Just <Value>`.
In Spark, no special treatment is needed to compare against a value that may be null.
Therefore, elm code that looks like:
```
testMaybeBoolConditional : List { foo: Maybe Bool } -> List { foo : Maybe Bool }
testMaybeBoolConditional source =
    source
        |> List.filter
            (\a ->
                a.foo == Just True
            )
```
gets translated in Spark to
```
  def testMaybeBoolConditional(
    source: org.apache.spark.sql.DataFrame
  ): org.apache.spark.sql.DataFrame =
    source.filter((org.apache.spark.sql.functions.col("foo")) === (true))
```

**Nothing** <br>
Where Elm code compares against Nothing, Morphir will translate this into a comparison to null in Spark.

For example, to take a list of records and filter out null records in Elm, we would do:
```
testMaybeBoolConditionalNull : List { foo : Maybe Bool } -> List { foo : Maybe Bool }
testMaybeBoolConditionalNull source =
    source
        |> List.filter
            (\a ->
                a.foo == Nothing
            )
```

In Spark, this would be:
```
def testMaybeBoolConditional(
  source: org.apache.spark.sql.DataFrame
): org.apache.spark.sql.DataFrame =
  source.filter(org.apache.spark.sql.functions.isnull(org.apache.spark.sql.functions.col("foo")))
```

**Maybe.map** <br>

Elm has `Maybe.map` and `Maybe.defaultValue` to take a Maybe and execute one branch of code if the Maybe isn't Nothing,
and another branch if it is.

The equivalent in Spark is to use `where` to execute one branch of code if the value isn't null, and `otherwise` for
the default case.
For example:
```
testMaybeMapDefault : List { foo : Maybe Bool } -> List { foo : Maybe Bool }
testMaybeMapDefault source =
    source
        |> List.filter
            (\item ->
                item.foo
                    |> Maybe.map
                        (\a ->
                            if a == False then
                                True
                            else
                                False
                        )
                    |> Maybe.withDefault False
            )
```

In Spark, this would be:
```
def testMaybeMapDefault(
  source: org.apache.spark.sql.DataFrame
): org.apache.spark.sql.DataFrame =
  source.filter(org.apache.spark.sql.functions.when(
    org.apache.spark.sql.functions.not(org.apache.spark.sql.functions.isnull(org.apache.spark.sql.functions.col("foo"))),
    org.apache.spark.sql.functions.when(
      (org.apache.spark.sql.functions.col("foo")) === (false),
      true
    ).otherwise(false)
  ).otherwise(false))
```

# Spark Backend

**mapDistribution**
This function takes a distribution and produces a Morphir FileMap
which is a dictionary of file paths and their contents. The distribution is the internal repsentation of the IR


**mapFunctionDefinition**
This function takes a fully qualified name and returns a Scala Member Declaration
Result


**mapRelation**
This function takes a Relational IR and returns S


**mapColumnExpression**
This function  takes a Morphir IR TypeValue (value with type information) and
returns a Scala value.


