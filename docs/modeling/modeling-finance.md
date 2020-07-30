# Modeling Financial Concepts

Functional Domain Modeling (FDM) is all about capturing business concepts in a precise, unambiguous, and processable manner.  Those coming from a coding background will be comfortable with its use of first class programming language.  There will be some differences from general purpose languages, and especially object-oriented languages, that are more focused on execution than capturing business concepts.  This tuturial reviews how we can capture common business concepts concisely and expressively with Morphir.  Morphir uses Elm as its main FDM language of choice, so we'll demonstrate the concepts with Elm examples.

## Using The Language Of The Business
FDM relies heavily on Domain Driven Design, which has the concept of the *ubiquitous language*: making sure that the business and technology stakeholders establish a consistent language to describe the business.  The best way to do this is to ensure that the code uses that language directly with no translation.  Morphir makes this easy by being very friendly for labeling data in the form of types.

We can use a standard trade as an example.  When the business talks about trading, they probably refer to the trade's quantity, price, and value as ```Trade Quantity``` and ```Trade Price```, and ```Trade Value```.  So we want to capture those concepts in our code.  As technologists, we know that these fields instances of integers and decimals.  While we might be tempted to declare them as such, it would be better if we could use the business language.  And this is how we want to approach modeling these concepts in Morphir.  Elm has the concept of type aliases, so we'll take advantage of that.

```elm
type alias TradeQuantity = Int

type alias TradePrice = Decimal

type alias TradeValue = Decimal
```

Now when we see these values in our code, we know they map directly to the business concepts that the users know them as.  For example:

```elm
value : TradeQuantity -> TradePrice -> TradeValue
value quantity price =
    (ToDecimal quantity) * price
```

This bit of Elm defines a function that takes a ```TradeQuantity``` and ```TradePrice``` and calculates the ```TradeValue```.  This simple act is incredibly effective in avoiding misunderstandings and mistakes.

## Keeping Incompatible Concepts Separate
In our trade example, we aliased ```TradePrice``` and ```TradeValue``` as aliases of Decimal.  That means that the compile considers them to be of the same Decimal type, so anything you can do with Decimals can be done with these two types.  That's useful in some ways, like applying functions like absolute value.  In other ways, we don't want to mix the two.  For example, what does it mean to do ```TradePrice + TradeValue```?  From a business perspective, this makes no sense, so we shouldn't be able to do it in code.  Morphir has the concept of *Units of Measure*, which you might have seen as a first class concept in F#.  In Elm it's implemented via a mechanism called *Phantom Types*.  So we probably want to implement some core types of ```Value``` and ```Price```.

```elm
type Price a = Price Decimal

type Quantity a = Quantity Int

type Value a = Value Decimal
```

This will ensure that we don't mix ```Price```, ```Quantity```, and ```Value``` in invalid ways.  There are a lot of concepts in finance that we might want to approach this way.  For example, we'd never want to accidentally use prices in different currencies without normalizing them.  The same goes for things like fixed rate versus variable rate loans.

## Categorizing Things
Categorizing stuff is one of the most common actions in enterprise development.  Finance is full of categorizing, like categorizing trades, accounts, and products into different sets.  This often gets very complex and categorization is usually highly contextual, meaning the same things might get categorized differently across different parts of the business.  This has historically been a major source of complexity in finance.  One of the main causes is the fact that categorization is usually approached up front, meaning the categories are decided first and then the things are created directly into those categories.  This limits later flexibility for different contexts and often creates incredibly complex graphs of categories.  In practice, we usually see this with object-oriented systems where the base classes or traits are decided first and then the specific things are specified with classes that extend them.  

Functional Domain Modeling takes a different approach to these challenges.  In FDM, the structure of things are defined first and only put into categories in contexts as needed.  This simplifies the modelers' jobs by alleviating the need to account for all possible use cases up front.  The tradeoff is that it requires mapping into categories later.

Let's look at an example.  A classic financial modeling exercise is to model various financial products. For this example, let's take a subset of a Treasury function since Treasury needs to work across asset classes.  The standard object-orient approach is to start with something like this:

```java
public interface Product {
    public String getISIN();
    public String getCusip();
    public String getSedol();
    // ...
}

public class Stock {
    private final String cusip;

    public Stock(String cusip) {
        this.cusip = cusip;
    }

    public String getISIN() {
        return null;
    }

    public String getCusip() {
        return this.cusip;
    }

    public String getSedol() {
        return null;
    }
}
```

TODO...

## Data sets
As we model data we come across a few established patterns, which we'll discuss below.  These are general guideliness that should be balanced with the context of the project.

## Infrequently changing limited values
This category describes a finite set of infrequently changing data.  Some good examples of this type are days of the week, months of the year, ISO country codes, and currency codes.  Often, programmers will want to refer to these directly without the possibility of mistakes.  The standard approach to specifying these values is to use an enum.  The functional way tends to focus on discriminated union types.  In Elm, this looks like:

```elm
type DayOfWeek = Sunday | Monday | Tuesday | Wednesday | Thursday | Friday | Saturday

isWeekend : DayOfWeek -> Bool
isWeekend day =
    day == Saturday || day == Sunday
```

## Frequently changing limited values
This category describes a finite set of frequently changing data. A good example of this might something like pizza toppings, where there's a core set of common toppings and frequent changes based on market conditions.  In theory, the frequency of change shouldn't affect how we model. It would be great to model these as enums as well and rely on continuous delivery to get that into production. In practice, many environments are not agile enough so rely on the database.  So the common approach is to define these as such:

```elm
type alias PizzaTopping = String
```

```elm
type Topping 
    = Cheese
    | Pepperoni
    | Mushrooms
    | Ricotta
    | Sausage
    | Other String


isVegetarian topping =
    not (topping == Pepperoni || topping == Sausage)


toppingToString : Topping -> String
toppingToString topping =
    case topping of
        Cheese -> "Cheese"
        Pepperoni -> "Pepperoni"
        Mushrooms -> "Mushrooms"
        Ricotta -> "Ricotta"
        Sausage -> "Sausage"
        Other s -> s
```

## Unlimited values
This category describes a set of data that is unbounded for all practical purposes.  The most common approach to these is simply to define a type alias:

```elm
type alias Name = String
```

A more type-safe approach is to define it with a type to prevent accidental use across unrelated fields:

```elm
type Name = Name String


hi : Name -> String
hi (Name name) =
    "Hi " ++ name
```

# Custom Types

When you have something in your domain that you can describe as a list of alternatives (X can either be A or B or C or ...) 
you probably want to model it as a [custom type](https://guide.elm-lang.org/types/custom_types.html). A simple special case
of this is enumerations. For example a Trade's Status can either be Open or Closed:

```elm
type TradeStatus
    = Open
    | Closed
```

Custom types are more flexible than enumertaion though because they allow you specify different structures for each case.
For example an Order's Price can either be Market or Limit:

```elm
type OrderPrice
    = Market
    | Limit Price
```

Notice that a market price doesn't have a specific value associated with it since it moves with the market but a limit price
would have a specific price limit. In order to take full advantage of this flexibility you should use a pattern match to 
branch out on the various cases. 

## Special case: enumerations

As mentioned above a special case of custom types is enumerations where each case is just a constructor with no type assigned:

```elm
type RAG
    = Red
    | Amber
    | Green
```

### Encoding enums

in many cases enums have well known n-letter codes that are used to store and transfer the values more efficiently. While this
is not strictly part of the business logic this happens so frequently that it usually makes sense to include them in your model.
Here's how you would do that for the `RAG` type above:

```elm
toCode : RAG -> String
toCode rag =
    case rag of
        Red -> 
            "R"

        Amber -> 
            "A"

        Green -> 
            "G"


fromCode : String -> Result String RAG
fromCode string =
    case string of
        "R" ->
            Ok Red

        "A" ->
            Ok Amber

        "G" ->
            Ok Green

        other ->
            Err other                        
```

Notice that `fromCode` returns a `Result`. This is a way to explicitly say that the operation may fail. Since you can pass in
any string to the function it should fail if it's not a valid code for your type.

## Special case: Wrapper types

An important special case of custom type is when you have a single case. With this approach you can wrap another type to hide
it from the rest of the model. For example you could wrap a String into a Cusip type to communicate the fact that you are
expecting a special kind of string:

```elm
type Cusip = Cusip String
```

You can still use any string as Cusip for testing but you have to explicitly wrap it which makes it safer to use:

```elm
doSomething (Cusip "123456789")
```
