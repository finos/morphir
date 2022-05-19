# **Spark Backend/API Documentation**
This is the entry point for the Spark Backend.

# The Spark API
The Spark API defines types for working with Spark.
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
A literal returns a Scala.Value by apply a Scala.Ref type to a list of arguments.
```
dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"
```


_**column**_  <br>
This is a reference to a column in a Dataframe. This returns a Scala value by apply a reference to column
to a string literal representing the name of the column
```
dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"
```


_**when**_  <br>
This method takes condition and a then branch and returns a Scala value



**_andWhen_**  <br>
This method takes  three parameters: a condition, a then branch and sofar and return a new value


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




# Spark Backend

**mapDistribution**
This function takes a distribution and produces a Morphir FileMap 
which is a dictionary of file paths and their contents. The distribution is the internal repsentation of the IR


**mapFunctionDefinition**
This function takes a fully qualified name and returns a Scala Member Declaration
Result


**mapRelation**
This function take a Relational IR and returns S


**mapColumnExpression**
This function  takes a Morphir IR TypeValue (value with type information) and
returns a Scala value.


