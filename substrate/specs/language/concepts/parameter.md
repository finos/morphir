# Parameter

A parameter is a [type](type.md) supplied at instantiation time. A type that
declares one or more parameters is called a _parametric type_ (analogous to
generics). The parameter name acts as a placeholder for the concrete element
type used in the type's operations.

For example, [Collection](../expressions/collection.md) is parametric over an
element type `T`. Every operation that accepts or returns an element works
with `T` rather than a fixed type.
