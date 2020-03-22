# What makes a good domain model?

We all strive to build high-quality software and that begins with a clean and well-defined 
domain model. But what do we mean when we say "clean" or "well-defined"? Without specific 
measures it is difficult to agree whether a change in the domain model makes it better or 
worse which stands in the way of continuous improvement. In this post we'll dive into how 
we can measure and improve the quality of our domain models.

[Making illegal state unrepresentable](https://fsharpforfunandprofit.com/posts/designing-with-types-making-illegal-states-unrepresentable/) 
is a well-known principle in the functional-programming community which refers to avoiding 
ambiguity that leaves the model open to more than one interpretation. A simple example of this 
is when a model uses strings instead of enums. Strings are ambiguous because they leave the 
interpretation to the consumer completely while enums limit the possible values significantly.

Is there a way to measure the ambugity? One approximation we can use is the cardinality of types.
Taking the above example a String has an infinite cardinality while an enum is always finite and
usually has less than a 100 values. So a String is infinitely more ambiguous than an enum.

Stepping up a level we can derive a few more useful metrics by looking at type cardinalities 
in the context of functions:

## Domain-to-Range Cardinality Ratio

Take a simple example of `String -> Enum` function. This takes an ambiguous value and truns it
into a less ambiguous one which is great since it decreases ambiguity. Taking the opposite 
`Enum -> String` though turns a relatively unambiguous value to a completely ambiguous one which
decreases the quality of the output model. So clearly, you want to avoid the latter.

## Domain Test Coverage

Adding test cases to the picture you can measure what percentage of possible inputs are covered 
by test cases. When the cardinality of the input type is finite it is possible to achieve full 
coverage which means you can be confident that the function works as expected.

More to come ...
