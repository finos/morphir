# Type

A type describes a set of values and the operations that apply to them. Each
type is defined in its own module under [Expressions](../expressions/).

A type may carry [attributes](attribute.md) that configure an instance and
[parameters](parameter.md) that make it generic over other types.

## Member Values

Every type enumerates or characterises the values it contains. For small,
fixed sets the members are listed explicitly (e.g.,
[Boolean](../expressions/boolean.md) has `true` and `false`). For open sets
the membership rule is stated instead (e.g., [Integer](../expressions/integer.md)
contains every whole number within a representable range).

## Type Class Instances

A type may implement one or more [type classes](type-class.md). The
**Type Class Instances** section of a type module lists the type classes it
implements, each as a link to the corresponding type class definition.
