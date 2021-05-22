# Modeling for database developers

## Introduction

As a database developer you will find it very easy and enjoyable to learn Elm
because it's basically an extended version of SQL. Being a functional programming
language, Elm is based on the same strong, mathematical foundations as relational 
algebra, and you get very similar declarative building blocks.

The syntax is different from SQL, but Elm is very lightweight and easy to pick up.
Probably the best way to start learning is to see a few examples. Let's start 
with a simple SQL query:

```sql
SELECT t.productID as product, t.quantity as qty
FROM Trades as t
WHERE t.buySell = 'S'
```

The SQL above translates to the following Elm code:

```elm
query1 =
    trades
        |> filter (\t -> t.buySell == "S")
        |> map
            (\t ->
                { product = t.productID
                , qty = t.quantity
                }
            )
```

There are a few things here that will look unfamiliar so let me explain:

* `trades` is the source collection, similar to a table in SQL.
* `|>` is the pipe operator. It's a way to chain transformations (operators in relational algebra).
* `filter` is selection. It corresponds to the `WHERE` clause in SQL.
* The `(\t -> ...)` syntax is a lambda. It's a way define a function inline. Some details about the syntax:
  * A lambda always starts with `\` which is followed by a list of argument names separated by spaces. This one has a single variable `t`.
  * After the argument names, there is an `->` to show that you are mapping the arguments to some other value.
  * You can specify any expressions after the arrow, and you can use the arguments as variables.
  * `t.buySell == "S"` this is very similar to how you would write this expression in SQL. 
    * The only difference is that we use double-equals for comparison because single-equals is used for assignment.
* `map` is projection. It corresponds to the `SELECT` clause in SQL.
  * `{ field1 = value1, field2 = value2 }` is the syntax to create a record.
    * This is slightly more involved than the SQL version, but it's also much more powerful. As you'll see later, Elm is
      not limited to flat record structures.

**Note**: At this point you might be thinking: hold on, this is actually doing the whole operation in-memory, that's completely different.
This is where Morphir comes into the picture. Elm compiles to JavaScript, so your assumption would be correct if we were just using Elm.
With Morphir we can transpile to various execution platforms, so this logic could turn into SQL, Spark SQL, or even straight Java. There's
a lot of options.

So far we have been trying to map a SQL query directly to Elm. Where it gets interesting is when you start to use the power of the language.
For example, you can move out filters to named functions:

```elm
isSell t =
    t.buySell == "S"


query1 =
    trades
        |> filter isSell
        |> map
            (\t ->
                { product = t.productID
                , qty = t.quantity
                }
            )
```

This does the same thing but reads better and also allows re-use across queries. This in itself gives you a lot of power as a developer,
but it doesn't stop there. With Elm, you get a whole set of new features compared to SQL:

## Schema

A database schema specifies the structure of the data stored in the database. In a programming language, a type-system does the same thing.
Elm's type-system is a superset of what a database schema provides. It has record types which makes it very easy to model relational objects
and offers a whole set of additional features that help you model your domain more accurately.

Let's start with a simple DDL:

```sql
CREATE TABLE Trade (
    product_id CHAR(9) NOT NULL,
    quantity NUMBER(20, 0) NOT NULL,
    buy_sell CHAR(1) NOT NULL,
    comment VARCHAR(100) NULL
)
```

As mentioned above, Elm has record types which makes it easy to define the same structure in the type-system:

```elm
type alias Trade =
    { productID : String
    , quantity : Int
    , buySell : String
    , comment : Maybe String
    }
```

Let's go through the type definition to understand what it means:

* The overall structure is very similar to the DDL:
  * Just like a table, a type has a name and a structure.
  * The structure is a list of field names and types.
* There are some differences too:
  * The field types are less granular than the DDL. This is just to avoid getting too deep too soon. We will 
  make these very granular later on.
  * Nullability is expressed through the types: we simply prefix the type of nullable fields with `Maybe`.

As mentioned, we did lose some granularity in this definition. One of the main goals of modeling is to very accurately model
your domain, so we need to address this. Fortunately Elm makes this easy. As a first step let's define `buySell` as an enumeration.

```elm
type alias Trade =
    { productID : String
    , quantity : Int
    , buySell : BuySell -- changed from String
    , comment : Maybe String
    }

-- this type captures the fact that there are only 2 valid values here
type BuySell 
    = Buy 
    | Sell
```

Elm allows you to define types as a choice between different values. The simplest way to use these is to
define enums. The definition above is pretty self-explanatory: the type `BuySell` can either be a `Buy` or a `Sell`.

The type in the DDL is less accurate because it allows any single character strings as values. This makes 
it easy to overload the field, which tends to happen in systems a lot. This definition makes it impossible 
to overload the value while also makes it easy to add new values if needed. The big difference is that you
are forced to at least document the valid values.

An enum like this can be mapped to the DDL in many ways depending on the database product or team best-practices.
The bottom line is that when you are modeling your data, you don't need to deal with that. You can leave that to 
the physical mapping layer.

The other thing we lost here is the lengths of some of the remaining columns. We can easily address that too:

```elm
type alias Trade =
    { productID : Cusip -- changed from String
    , quantity : Int
    , buySell : BuySell
    , comment : Maybe Comment -- changed from Maybe String
    }


type BuySell 
    = Buy 
    | Sell


type Cusip = 
    Cusip String

cusip =
    String.ofLength 9 Cusip


type Comment = 
    Comment String

comment =
    String.ofMaxLength 100 Comment
```

## Branching out

_Coming soon_


## More relational operators

_Coming soon_

[Home](/index) | [Posts](posts) | [Examples](https://github.com/finos/morphir-examples/)