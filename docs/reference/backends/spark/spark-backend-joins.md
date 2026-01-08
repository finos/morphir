---
id: spark-backend-joins
title: Backend Joins
sidebar_position: 7
---

# Spark - Backend Joins
Let's start by defining an example model that does some joins:

```elm
baseRelation
    |> List.leftJoin joinedRelationA
        (\base joinedA ->
            base.id == joinedA.baseId
        )
    |> List.innerJoin joinedRelationB
        (\( base, maybeJoinedA ) joinedB ->
            base.id == joinedB.baseId
        )
    |> List.leftJoin joinedRelationC
        (\( ( base, maybeJoinedA ), joinedB ) joinedC ->
            base.id == joinedC.baseId
        )
    |> List.map    
        (\( ( ( base, maybeJoinedA ), joinedB ), maybeJoinedC ) ->
            { baseId = base.id
            , foo = maybeJoinedA |> Maybe.map .foo
            , bar = joinedB.bar
            , baz = maybeJoinedC |> Maybe.map .baz
            }
        )
```

Which would translate into the following SQL:

```sql
SELECT
    base.id AS base_id,
    joined_a.foo AS foo,
    joined_b.bar AS bar,
    joined_c.baz AS baz
FROM base_relation as base
LEFT JOIN joined_relation_a AS joined_a 
    ON base.id = joined_a.base_id
JOIN joined_relation_b AS joined_b 
    ON base.id = joined_b.base_id
LEFT JOIN joined_relation_c AS joined_c 
    ON base.id = joined_c.base_id
```

In order to figure out how to map the Morphir logic to SQL we should first try to identify the main differences between the two snippets ignoring the trivial syntax differences. Here are some of the differences that we will have to deal with:

- Variable name vs object name
  - In SQL we use the same object name to refer to a certain object throughout the whole query.
  - In the Elm code each `join` and `map` operation defines its own scope so names are not guaranteed to be consistent
    - The actual object being referred to can be inferred from the position of the tuple element that represents it because each join adds a new element at the end of a nested tuple structure
- Field / object optionality
  - In SQL any column could potentially be nullable and optionality is not handled explicitly in the syntax
    - Behind the scenes optional values are handled using implicit rules about how to handle NULL values
  - In the Elm code optional values are handled explicitly
    - As a result even if two snippets do the same thing their syntax may be different based on whether they are dealing with optional or required values


## Implementation Details

### Adding a JOIN operator

The Spark backend models relational operators using the `ObjectExpression` type that currently only supports the `FROM`, `WHERE` and `SELECT` clauses. We should start by adding a `JOIN` operator.

```elm
{-| ...

  - **Join**
      - Represents a `df.join(...)` transformation.
      - The four arguments are:
          - The type of join to apply (inner or left-outer). Corresponds to the last string argument in the Spark API.
          - The base relation as an ObjectExpression.
          - The relation to join as an ObjectExpression.
          - The "on" clause of the join. This is a boolean expression that should compare fields of the base and the
            joined relation.

-}
type ObjectExpression
    = From ObjectName
    | Filter Expression ObjectExpression
    | Select NamedExpressions ObjectExpression
    -- New addition
    | Join JoinType ObjectExpression ObjectExpression Expression


{-| Specifies which type of join to use. For now we only support inner and left-outer joins since that covers the
majority of real-world use-cases and we want to minimize complexity.

  - **Inner**
      - Represents an inner join.
  - **Left**
      - Represents a left-outer join.

-}
type JoinType
    = Inner
    | Left
```

### Variable name to object name mapping

As mentioned above the names used in the Morphir model are not necessarily aligned with the relation names since in Morphir the relations are represented with a tuple structure where the modeler names members in each lambda that represents an `on` clause and in the `map` function as well. Here's an intentionally obfuscated version of the original example to highlight the issue:

```elm
baseRelation
    |> List.leftJoin joinedRelationA
        (\a b ->
            a.id == b.baseId
        )
    |> List.innerJoin joinedRelationB
        (\( c, _ ) d ->
            c.id == d.baseId
        )
    |> List.leftJoin joinedRelationC
        (\( ( e, _ ), _ ) f ->
            e.id == f.baseId
        )
    |> List.map    
        (\( ( ( g, h ), i ), j ) ->
            { baseId = g.id
            , foo = h |> Maybe.map .foo
            , bar = i.bar
            , baz = j |> Maybe.map .baz
            }
        )
```

This is easy to resolve in the backend but it does require some extra processing. Essentially, we need to replace the variable names the modeler assigned to names that align with the object names in every lambda in the above logic including the `on` clause in each join and the `map` function. This involves two steps:
- Get the variable name to object name mapping.
- Rewrite all occurences of the variable name to the object name in the lambda.

The most difficult part of this is getting the variable name to object name mapping. While the Elm code implicitly retains the structure of joins through the use of tuples the Spark backend does not do that automatically. Therefore we need to explicitly keep track of the name of each object as they relate to joins in a binary tree structure so that we can later align it to the tuple structure in Morphir and correlate object names with variable names.

### Handling optional values

While optional values clearly show up in these examples the issue is not related to joins at all so we will handle them separately. See [Handling optional values in Spark](spark-backend-optional-values.md) 