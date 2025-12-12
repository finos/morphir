---
id: spark-optional-values
tile: Handling Optional Values
sidebar_position: 8
---

# Spark - Handling Optional Values

Optional values are handled differently in SQL and Morphir. In SQL every value can potentially be `NULL` and there are implicit rules about how each operator should behave when `NULL`s are passed to them. Spark follows the same approach as documented in the [NULL semantics](https://spark.apache.org/docs/latest/sql-ref-null-semantics.html) section. Morphir on the other hand requires the modeler to handle missing values explicitly. 

If the goal was simply to accurately map the Morphir code to Spark we could translate the `Maybe` API calls directly to `case` statements. While that would work it would generate unnecesarily complex logic when the default `NULL` semantics in Spark are already in-line with what the Morphir code expresses. For example, given the Elm code below:

```elm
joinedRelation 
    |> Maybe.map (\x -> x.aField == baseRelation.aField) 
    |> Maybe.withDefault False
```

The corresponding SQL can be much simpler since comparing anything to missing values will return `false` anyway: 

```sql
joinedRelation.a_field == baseRelation.a_field
```

TODO: Add more details