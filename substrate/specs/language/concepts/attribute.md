# Attribute

## Summary

An attribute is a value that configures a type instance. Attributes are
fixed at the point where the type is used; they are not types
themselves. An attribute's type is either a primitive type (e.g.
Boolean, Integer) or a dedicated attribute type defined in its own
module (e.g. `Collection Multiplicity`). When an attribute type has
only a small, fixed set of named values, it is described as an
enumerated type with one member value per option.

## Attribute Types

An attribute's type may be:

- A primitive type already defined in the language (e.g., Boolean,
  Integer).
- A dedicated attribute type defined in its own module, named after the
  type and attribute it belongs to (e.g., `Collection Multiplicity`).
  Such attribute types follow the same module conventions as any other
  type.

When an attribute type has only a small, fixed set of named values, it is
described as an enumerated type with one member value per option.
