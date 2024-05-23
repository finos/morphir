# Join support in Snowpark

Integrating data from disparate sources is a common necessity, often arising from the need to establish relationships between datasets originating from different sources. In the dynamic landscape of data analysis, the process of merging information plays a pivotal role in gaining comprehensive insights.

If you wish to achieve this functionality in Morphir, you would implement something similar to the following example:

```elm
simpleInnerJoin : List TypeA -> List TypeB -> List {idA: Int, idB: Int}
simpleInnerJoin dataSetA dataSetB =
     dataSetA
        |> innerJoin dataSetB
            ( \a b -> a.id == b.id )
        |> List.map (\ (x, y) -> 
            { idA = x.id
            , idB = y.id
            })
```

The `simpleInnerJoin` example illustrates how to perform an *inner join* operation between two datasets, dataSetA and dataSetB, represented as lists of types TypeA and TypeB respectively. In this case, the join is based on a specific condition: equality between the `id` properties of elements in dataSetA and dataSetB.

The `innerJoin` function (provided for the [Morphir.SDK](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-SDK-List#innerJoin)) facilitates this join, taking the equality condition provided in the lambda function `(\a b -> a.id == b.id)`.

Subsequently, the List.map function is used to project the results of the join. The lambda function `(\(x, y) -> { idA = x.id, idB = y.id })` maps each pair of results (x, y) to a new data type `{ idA : Int, idB : Int }`, where `idA` represents the `id` value in dataSetA and `idB` represents the `id` value in dataSetB.

This example demonstrates how Morphir in Elm can be used concisely and expressively to perform join and projection operations, providing a solid foundation for efficient data manipulation.

## Joins in Snowpark

In Snowpark, support is provided for specific scenarios that follow the join pattern. You can visit the [documentation](https://docs.snowflake.com/en/developer-guide/snowpark/scala/working-with-dataframes#joining-dataframes) here.

### Inner Join

If you have this code in Elm using the `innerJoin` function:

```elm
simpleInnerJoin : List TypeA -> List TypeB -> List {idA: Int, idB: Int}
simpleInnerJoin dataSetA dataSetB =
     dataSetA
        |> innerJoin dataSetB
            ( \a b -> a.id == b.id )
        |> List.map (\ (x, y) -> 
            { idA = x.id
            , idB = y.id
            })
```

The transformation to Snowpark will be:

```Scala
    def simpleInnerJoin
        (dataSetA: com.snowflake.snowpark.DataFrame)
        (dataSetB: com.snowflake.snowpark.DataFrame)
        (implicit sfSession: com.snowflake.snowpark.Session): com.snowflake.snowpark.DataFrame = {
    val dataSetAColumns: deparments.Joins.TypeA = new deparments.Joins.TypeAWrapper(dataSetA)    
    val dataSetBColumns: deparments.Joins.TypeB = new deparments.Joins.TypeBWrapper(dataSetB)
    
    dataSetA.join(
      dataSetB,
      (dataSetAColumns.id) === (dataSetBColumns.id),
      "inner"
    ).select(
      dataSetAColumns.id.alias("idA"),
      dataSetBColumns.id.alias("idB")
    )
  }
```

You can notice that `innerJoin` function from **Morphir.SDK** is transform to `join` function of **Snowpark** passing the argument `inner` to choose the join type.

The projection is changed to a **Snowpark select** to return a dataframe with the selected columns.

### Left Join

The `leftJoin` function is similar to `innerJoin`. You can find the documentation of *Morphir.SDK* [here](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-SDK-List#leftJoin). The difference is that the `leftJoin` returns a `List ( a, Maybe b)` instead, so in the projection you must to return a maybe value:

```elm
simpleLeftJoin : List TypeA -> List TypeB -> List {x: Int, y: Maybe Int}
simpleLeftJoin dataSetA dataSetB =
     dataSetA
        |> leftJoin dataSetB
            ( \a b -> a.id == b.id )
        |> List.map (\ (x, y) ->
        { x = x.id
        , y = Maybe.map (\t -> t.id) y
        })
```

The transformation to Snowpark will be:

```Scala
def simpleLeftJoin
    (dataSetA: com.snowflake.snowpark.DataFrame)
    (dataSetB: com.snowflake.snowpark.DataFrame)
    (implicit sfSession: com.snowflake.snowpark.Session): com.snowflake.snowpark.DataFrame = {
    val dataSetAColumns: deparments.Joins.TypeA = new deparments.Joins.TypeAWrapper(dataSetA)
    val dataSetBColumns: deparments.Joins.TypeB = new deparments.Joins.TypeBWrapper(dataSetB)
    
    dataSetA.join(
      dataSetB,
      (dataSetAColumns.id) === (dataSetBColumns.id),
      "left"
    ).select(
      dataSetAColumns.id.alias("x"),
      dataSetBColumns.id.alias("y")
    )
  }
```

In Snowpark, when employing a join operation, it is important to note that columns with `null` values may be encountered when performing a join operation. Consequently, you might observe that the `select` projection simply yields a basic column that could potentially include `null` values. For more information about Snowpark and `Joins` you can see [this link](https://docs.snowflake.com/en/developer-guide/snowpark/scala/working-with-dataframes#joining-dataframes).

### Multiple Joins

In Morphir, you have the flexibility to use two consecutive joins to combine data from three different sources. To achieve this, you can employ one join after another and craft a projection to obtain the desired data. This approach allows you to seamlessly integrate information from multiple datasets, enhancing the versatility of your data manipulation operations, for example:

```elm
multipleJoin : List TypeA -> List TypeB -> List TypeC -> List {idA: Int, idB: Int, idC: Int}
multipleJoin dataSetA dataSetB dataSetC = 
    dataSetA 
        |> innerJoin dataSetB (\a b -> a.id ==  b.id ) 
        |> innerJoin dataSetC  (\(x, y) z -> x.id == z.id )
    |> List.map (\ ((a, b), c) ->
        { idA = a.id
        , idB = b.id
        , idC = c.id
        })
```

The transformation to Snowpark will be:

```Scala
 def multipleJoin(
    dataSetA: com.snowflake.snowpark.DataFrame
  )(
    dataSetB: com.snowflake.snowpark.DataFrame
  )(
    dataSetC: com.snowflake.snowpark.DataFrame
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.DataFrame = {
    val dataSetAColumns: deparments.Joins.TypeA = new deparments.Joins.TypeAWrapper(dataSetA)
    
    val dataSetBColumns: deparments.Joins.TypeB = new deparments.Joins.TypeBWrapper(dataSetB)
    
    val dataSetCColumns: deparments.Joins.TypeC = new deparments.Joins.TypeCWrapper(dataSetC)
    
    dataSetA.join(
      dataSetB,
      (dataSetAColumns.id) === (dataSetBColumns.id),
      "inner"
    ).join(
      dataSetC,
      (dataSetAColumns.id) === (dataSetCColumns.id),
      "inner"
    ).select(
      dataSetAColumns.id.alias("idA"),
      dataSetBColumns.id.alias("idB"),
      dataSetCColumns.id.alias("idC")
    )
  }
```

In Snowpark, you can perform the union of two or more join functions, enabling support for multiple joins within a single query. In the final part of the query, a projection is generated using a select statement, which selects the desired columns to be included in the resulting DataFrame.

### Requirements 

It is essential to note that for these patterns to be transformed, they must meet certain requirements:

1. Return a Projection as a List of a Record:
    
- The join pattern should result in a projection that is a list of a record.

2. Function Parameters Representing a Table:
    
- The parameters of the function must be a list of records representing a table. For more information, refer to the Snowpark backend types section. For more information related to the `types` you can see [this link](snowpark-backend-types.md).

3. Supported Join Functions:
    
- Currently, the Snowpark backend supports the innerJoin and leftJoin functions from [Morphir.SDK](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-SDK-List#leftJoin).