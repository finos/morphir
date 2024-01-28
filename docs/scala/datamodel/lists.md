---
id: lists
title: Lists
---
Given the following Scala:
```scala
val items = List("one", "two", "three")
```
and the equivalent Morphir/ELM lists:
```elm
items: List String
items = ["one", "two", "three"]
```

This data should be represented in the Morphir data-model as the following:
```scala
Data.List(
    values = List(Data.String("one"), Data.String("two"), Data.String("three")),
    shape = Concept.List(elementType = Concept.String)
)
```

List should be able to contain Records, Enums, or any other subtype of Data.
For example, the following data in Scala and Morphir/Elm:
```scala
// Scala
case class Person(name: String, age: Int)
val people = List(Person("Joe", 123), Person("Jim", 456))
```
```elm
-- Morphir/ELM
type alias Person = { name: String, age: Int }
people: List Person
people = [ {name = "Joe", age = 123}, {name = "Jim", age = 456} ]
```
should be represented in the Morphir data-model as the following:
```scala
Data.List(
  values = List(
    Data.Record(
      L("name") -> Data.String("Joe"), L("age") -> Data.Int32(123), 
    ),
    Data.Record(
      L("name") -> Data.String("Jim"), L("age") -> Data.Int32(456), 
    )
  ),
  shape = Concept.List(
    elementType = 
      Concept.Record(
        L("name") -> Concept.String, 
        L("age") -> Concept.Int32
      )
  )
)

```
