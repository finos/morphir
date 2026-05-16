# Operation

## Summary

An operation is a named unit of logic, typically defined within a
type class. Each operation has a **Required** or **Derived** marker, a
natural-language description of its semantics, and a
[Test cases](test-case.md) section giving full-coverage input/output
examples. Built-in operations have no implementation in the language
itself unless they are derived; their description and test cases serve
as the authoritative semantic reference. A derived operation has a
default definition expressed in terms of one or more required
operations and may be overridden by instancing types.

## Overview

An operation is a named unit of logic defined within a
[type class](type-class.md). Each operation in a type class module has its
own subsection containing:

- A [Required](#required) or [Derived](#derived) marker.
- A description of the operation's semantics.
- A [test cases](test-case.md) subsection providing full-coverage
  input/output examples. Operations require full coverage; the
  [Test Case](test-case.md) document defines the available forms
  (table or scenario) and how each is structured.

Heading depth is relative, not absolute. A test cases subsection must appear
under the heading of its operation, but additional grouping sections may
appear between any structural elements. The overall heading hierarchy of a
module is flexible provided that relative containment relationships are
preserved.

Built-in operations have no implementation in the language itself unless they
are [Derived](#derived). Their natural language description and test cases
together serve as the authoritative semantic reference. Derived operations
must reference the required operation(s) they are defined in terms of.

## Signature

Every operation has a **signature** consisting of an `Inputs` section and an
`Outputs` section. Both are required structural elements of an operation definition.

```markdown
### OperationName [Operation](operation.md)

Description of the operation.

#### Inputs
- `paramName`: [TypeName][anchor]

#### Outputs
- `result`: [TypeName][anchor]

#### [Test cases][tc]
| `paramName` | `result` |
| ----------- | -------- |
| …           | …        |
```

Each entry in `Inputs` and `Outputs` is a named parameter in backticks followed by
a colon and a type link. Test-case table column headers must be the parameter name
in backticks, matching exactly one entry in `Inputs` or `Outputs`.

For [type-class](type-class.md) operations, parameter types reference the
[Type Instance](type-class.md#type-instance) slot rather than a concrete type.

## Required

The operation must be implemented by any [type](datatype.md) that instances the
[type class](type-class.md). It cannot be derived from other operations in
the same type class.

## Derived

The operation has a default definition expressed in terms of one or more
[Required](#required) operations. A type instancing the type class inherits
this definition and does not need to implement it separately, though it may
override it.
