# Type Class

## Summary

A type class defines a shared interface: a set of operations that any
type may implement. A type that implements a type class is said to
_instance_ it. Each operation is marked **Required** (every instancing
type must implement it) or **Derived** (default definition in terms of
required operations; may be overridden). A type class may extend other
type classes — an instance of the extending class must also instance
each extended class. Some type class modules also list known member
types in a **Type Class Members** section as a quick cross-reference.

## Overview

A type class defines a shared interface: a set of operations that any
[type](datatype.md) may implement. It is analogous to an interface or trait in
other languages. A type that implements a type class is said to _instance_
that type class.

## Operations

Each type class declares one or more operations. Every operation is marked as
either [Required](operation.md#required) or
[Derived](operation.md#derived).

- A **required** operation must be implemented by every type that instances
  the type class.
- A **derived** operation has a default definition expressed in terms of
  required operations. Types inherit derived operations automatically but may
  override them.

## Extension

A type class may extend one or more other type classes. When type class _B_
extends type class _A_, any type that instances _B_ must also instance _A_.
Extended type classes are listed in the **Extended Type Classes** section of
the module.

## Type Class Members

Some type class modules list their known member types in a **Type Class
Members** section. This is the inverse of a type's
[Type Class Instances](datatype.md#type-class-instances) section and serves as a
quick reference for which types implement the class.
