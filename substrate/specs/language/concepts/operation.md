# Operation

An operation is a named unit of logic defined within a
[type class](type-class.md). Each operation in a type class module has its
own subsection containing:

- A [Required](#required) or [Derived](#derived) marker.
- A description of the operation's semantics.
- A test cases subsection with a table of inputs and expected outputs
  providing full-coverage test cases.

Heading depth is relative, not absolute. A test cases subsection must appear
under the heading of its operation, but additional grouping sections may
appear between any structural elements. The overall heading hierarchy of a
module is flexible provided that relative containment relationships are
preserved.

Built-in operations have no implementation in the language itself unless they
are [Derived](#derived). Their natural language description and test cases
together serve as the authoritative semantic reference. Derived operations
must reference the required operation(s) they are defined in terms of.

## Required

The operation must be implemented by any [type](type.md) that instances the
[type class](type-class.md). It cannot be derived from other operations in
the same type class.

## Derived

The operation has a default definition expressed in terms of one or more
[Required](#required) operations. A type instancing the type class inherits
this definition and does not need to implement it separately, though it may
override it.
