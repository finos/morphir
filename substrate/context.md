# Equality [Type Class](#type-class)

## Overview

The Equality [type class](#type-class) defines operations for comparing values to determine if they are equal or not equal. It applies to [types](#type) where equality is meaningful.

## Operations

All operations return a [Boolean](#boolean-type) value.

### Equal [Operation](#operation)

*[Required](#required).* Returns true if both values are the same. Must be implemented by any type that instances this type class.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | false  |
| false   | true    | false  |
| false   | false   | true   |

### Not Equal [Operation](#operation)

*[Derived](#derived).* Returns true if values are different. Defined as [NOT](#not-operation)`(a == b)`; does not need to be separately implemented.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | false  |
| true    | false   | true   |
| false   | true    | true   |
| false   | false   | false  |

# Ordering Relation [Type](#type)

## Overview

The Ordering Relation type represents the outcome of a comparison between two ordered values. It has three distinct member values.

## [Member Values](#member-values-6)

### Less

The first value is smaller than the second.

### Equal

Both values are the same.

### Greater

The first value is larger than the second.

## [Type Class Instances](#type-class-instances-5)

Ordering Relation implements [Equality](#equality-type-class): two Ordering Relation values are equal when they are the same member.

# Ordering [Type Class](#type-class)

## Overview

The Ordering [type class](#type-class) defines operations for comparing values to determine their relative order. It extends [Equality][eq]: any [type](#type) with an ordering also supports equality comparison.

## Operations

Relational operations return a [Boolean][bool] value.

### Compare [Operation](#operation)

*[Required][req].* Returns an [Ordering Relation][or] representing the relationship between the first and second value. All other ordering operations are derived from this.

#### Test cases

| Input A | Input B | Output                |
| ------- | ------- | --------------------- |
| 1       | 2       | [Less][or-less]       |
| 2       | 2       | [Equal][or-equal]     |
| 3       | 2       | [Greater][or-greater] |

### Less Than [Operation](#operation)

*[Derived][der].* Returns true when `compare(a, b)` is [Less][or-less].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | true   |
| 2       | 2       | false  |
| 3       | 2       | false  |

### Greater Than [Operation](#operation)

*[Derived][der].* Returns true when `compare(a, b)` is [Greater][or-greater].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | false  |
| 2       | 2       | false  |
| 3       | 2       | true   |

### Less Than or Equal [Operation](#operation)

*[Derived][der].* Returns true when `compare(a, b)` is not [Greater][or-greater].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | true   |
| 2       | 2       | true   |
| 3       | 2       | false  |

### Greater Than or Equal [Operation](#operation)

*[Derived][der].* Returns true when `compare(a, b)` is not [Less][or-less].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | false  |
| 2       | 2       | true   |
| 3       | 2       | true   |

[bool]: #boolean-type

[der]: #derived

[eq]: #equality-type-class

[or]: #ordering-relation-type

[or-equal]: #equal

[or-greater]: #greater

[or-less]: #less

[req]: #required

# Type Class

A type class defines a shared interface: a set of operations that any
[type](#type) may implement. It is analogous to an interface or trait in
other languages. A type that implements a type class is said to *instance*
that type class.

## Operations

Each type class declares one or more operations. Every operation is marked as
either [Required](#required) or
[Derived](#derived).

* A **required** operation must be implemented by every type that instances
  the type class.
* A **derived** operation has a default definition expressed in terms of
  required operations. Types inherit derived operations automatically but may
  override them.

## Extension

A type class may extend one or more other type classes. When type class *B*
extends type class *A*, any type that instances *B* must also instance *A*.
Extended type classes are listed in the **Extended Type Classes** section of
the module. For example, [Ordering](#ordering-type-class) extends
[Equality](#equality-type-class).

## Type Class Members

Some type class modules list their known member types in a **Type Class
Members** section. This is the inverse of a type's
[Type Class Instances](#type-class-instances-5) section and serves as a
quick reference for which types implement the class.

# Operation

An operation is a named unit of logic defined within a
[type class](#type-class). Each operation in a type class module has its
own subsection containing:

* A [Required](#required) or [Derived](#derived) marker.
* A description of the operation's semantics.
* A test cases subsection with a table of inputs and expected outputs
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

The operation must be implemented by any [type](#type) that instances the
[type class](#type-class). It cannot be derived from other operations in
the same type class.

## Derived

The operation has a default definition expressed in terms of one or more
[Required](#required) operations. A type instancing the type class inherits
this definition and does not need to implement it separately, though it may
override it.

# Boolean [Type](#type)

## Overview

The Boolean type represents a fundamental data type with two distinct member values: **true** and **false**. It is used to express binary logic, decision making, and control flow within specifications and executable models.

## [Member Values](#member-values-6)

* **true**: Represents affirmation, presence, or logical truth.
* **false**: Represents negation, absence, or logical falsehood.

## Operations

### NOT [Operation](#operation)

Inverts the value of a Boolean.

#### Test cases

| Input | Output |
| ----- | ------ |
| true  | false  |
| false | true   |

### AND [Operation](#operation)

Returns true if and only if both inputs are true.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | false  |
| false   | true    | false  |
| false   | false   | false  |

### OR [Operation](#operation)

Returns true if at least one input is true.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | true   |
| false   | true    | true   |
| false   | false   | false  |

### XOR [Operation](#operation)

Returns true if exactly one input is true.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | false  |
| true    | false   | true   |
| false   | true    | true   |
| false   | false   | false  |

### IMPLIES [Operation](#operation)

Returns false only when the antecedent is true and the consequent is false.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | false  |
| false   | true    | true   |
| false   | false   | true   |

### If-Then-Else [Operation](#operation)

Evaluates to the then-value when the condition is `true`, and to the else-value when the condition is `false`. The condition must be a Boolean.

#### Test cases

| Condition | Then | Else | Output |
| --------- | ---- | ---- | ------ |
| true      | 1    | 2    | 1      |
| false     | 1    | 2    | 2      |

## [Type Class Instances](#type-class-instances-5)

Boolean implements [Equality](#equality-type-class): two Boolean values are equal when they are the same member.

# Number [Type Class](#type-class)

## Overview

The Number [type class](#type-class) defines operations for numeric [types](#type), supporting arithmetic and related transformations. It extends [Equality](#equality-type-class) and [Ordering](#ordering-type-class): numeric values can be compared for equality and relative order.

## Operations

### Addition [Operation](#operation)

Returns the sum of two numbers.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | 3      |
| -1      | 1       | 0      |
| 0       | 0       | 0      |

### Subtraction [Operation](#operation)

Returns the difference of two numbers.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 3       | 2       | 1      |
| 1       | 1       | 0      |
| 0       | 3       | -3     |

### Multiplication [Operation](#operation)

Returns the product of two numbers.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 3       | 2       | 6      |
| -2      | 3       | -6     |
| 0       | 5       | 0      |

### Division [Operation](#operation)

Returns the quotient of two numbers. Precondition: divisor must not be zero; the result is undefined otherwise.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 6       | 2       | 3      |
| 7       | 2       | 3.5    |
| 0       | 5       | 0      |

### Negation [Operation](#operation)

Returns the additive inverse of a number such that `a + negate(a) == 0`.

#### Test cases

| Input | Output |
| ----- | ------ |
| 3     | -3     |
| -3    | 3      |
| 0     | 0      |

### Absolute Value [Operation](#operation)

Returns the non-negative magnitude of a number. Equal to the number itself when non-negative, and its [negation](#negation-operation) otherwise.

#### Test cases

| Input | Output |
| ----- | ------ |
| 3     | 3      |
| -3    | 3      |
| 0     | 0      |

### Modulus [Operation](#operation)

Returns the remainder after dividing the first number by the second. Precondition: divisor must not be zero.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 7       | 3       | 1      |
| 6       | 3       | 0      |
| 2       | 5       | 2      |

# Integer

## Overview

Represents whole numbers, optionally with fixed precision and signedness. Used for counting, indexing, and discrete arithmetic.

### Attributes

* **size in bits** (optional): If set, restricts the integer to a fixed bit width (e.g., 8, 16, 32, 64). If unset, the integer is arbitrary precision.
* **signed** ([Boolean](#boolean-type)): If `true`, the integer can represent negative numbers; if `false`, only non-negative numbers.

## [Member Values](#member-values-6)

* Any whole number within the representable range determined by `size in bits` and `signed`.

## [Type Class Instances](#type-class-instances-5)

* [Number](#number-type-class)
* [Equality](#equality-type-class)
* [Ordering](#ordering-type-class)

## Integer-Specific Operations

### Integer Division (Required) [Operation](#operation)

Divides one integer by another, discarding any remainder. The result is the greatest integer less than or equal to the exact quotient (floor division).

**Precondition:** Divisor must be non-zero.

#### Test Cases

| Dividend | Divisor | Result |
| -------- | ------- | ------ |
| 7        | 2       | 3      |
| -7       | 2       | -4     |
| 7        | -2      | -4     |
| -7       | -2      | 3      |
| 5        | 5       | 1      |
| 0        | 3       | 0      |

### Remainder (Required) [Operation](#operation)

Returns the remainder after integer division.

**Precondition:** Divisor must be non-zero.

#### Test Cases

| Dividend | Divisor | Result |
| -------- | ------- | ------ |
| 7        | 2       | 1      |
| -7       | 2       | 1      |
| 7        | -2      | 1      |
| -7       | -2      | 1      |
| 5        | 5       | 0      |
| 0        | 3       | 0      |

# Attribute

An attribute is a value that configures a [type](#type) instance.
Attributes are fixed at the point where the type is used; they are not types
themselves.

## Attribute Types

An attribute's type may be:

* A primitive type already defined in the language (e.g.,
  [Boolean](#boolean-type),
  [Integer](#integer)).
* A dedicated attribute type defined in its own module, named after the type
  and attribute it belongs to (e.g., `Collection Multiplicity`). Such
  attribute types appear in the [Expressions](../expressions/) section and
  follow the same module conventions as any other type.

When an attribute type has only a small, fixed set of named values, it is
described as an enumerated type with one member value per option.

# Collection Multiplicity [Type](#type)

## Overview

An attribute type that governs whether duplicate elements are permitted in a
[Collection](#collection-type). Two elements are considered duplicates when they
compare [Equal](#equal-operation) under the element type's
[Equality](#equality-type-class) instance.

## [Member Values](#member-values-6)

* **unique** — no two elements in the collection may be equal. Adding a
  duplicate element leaves the collection unchanged.
* **multi** — duplicate elements are permitted; the same value may appear more
  than once.

# Collection Iteration Order [Type](#type)

## Overview

An attribute type that governs the sequence in which elements are visited
during iteration of a [Collection](#collection-type).

## [Member Values](#member-values-6)

* **none** — no iteration order is guaranteed.
* **insertion** — elements are visited in the order they were added.
* **key** — elements are visited in ascending order defined by a
  [Compare](#compare-operation) expression over a key derived from each
  element, equivalent to SQL `ORDER BY`.

## Attributes

### Tie-Breaking

Applies only when the iteration order is **key**. Governs how elements with
equal keys are ordered relative to each other:

* **stable** — elements with equal keys retain their relative insertion order.
* **unstable** — the relative order of elements with equal keys is unspecified.

# Collection [Type](#type)

## Overview

A Collection is a parametric type over an element type `T` that holds zero or more elements. Collections are characterized by four attributes:

* **multiplicity** ([Collection Multiplicity][col-mult]) — governs whether duplicate elements are permitted.
* **iteration order** ([Collection Iteration Order][col-iter]) — governs the sequence in which elements are visited during iteration.
* **minimum cardinality** ([Integer][int]) — the minimum number of elements the collection must contain.
* **maximum cardinality** ([Integer][int], optional) — the maximum number of elements the collection may contain.

## [Parameters](#parameter)

| Name | Description                                  |
| ---- | -------------------------------------------- |
| `T`  | The type of elements held in the collection. |

## [Attributes](#attribute)

### Multiplicity

Type: [Collection Multiplicity][col-mult]. Governs whether duplicate elements are permitted. See [Collection Multiplicity][col-mult] for the full definition of each value.

### Iteration Order

Type: [Collection Iteration Order][col-iter]. Governs the sequence in which elements are visited during iteration. When the value is **key**, a [tie-breaking](#tie-breaking) sub-attribute further specifies the relative order of elements with equal keys. See [Collection Iteration Order][col-iter] for the full definition of each value.

### Minimum Cardinality

Type: [Integer][int]. The minimum number of elements the collection must contain. When the minimum cardinality is `1` or more, the collection is *non-empty*. Defaults to `0`.

### Maximum Cardinality

Type: [Integer][int], optional. The maximum number of elements the collection may contain. When unspecified, the collection is unbounded.

## Operations

### Size [Operation](#operation)

*[Required][req].* Returns the number of elements in the collection.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[]        | 0      |
| \[1]       | 1      |
| \[1, 2, 3] | 3      |
| \[1, 1, 2] | 3      |

### Is Empty [Operation](#operation)

*[Derived][der].* Returns [Boolean][bool] `true` if the collection contains no elements. Defined as [Size](#size-operation) equal to zero.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[]        | true   |
| \[1]       | false  |
| \[1, 2, 3] | false  |

### Contains [Operation](#operation)

*[Required][req].* Precondition: element type implements [Equality][eq]. Returns [Boolean][bool] `true` if any element in the collection compares [Equal][eq-equal] to the given value.

#### Test cases

| Collection | Value | Output |
| ---------- | ----- | ------ |
| \[1, 2, 3] | 2     | true   |
| \[1, 2, 3] | 4     | false  |
| \[]        | 1     | false  |
| \[1, 1, 2] | 1     | true   |

### Map [Operation](#operation)

*[Required][req].* Returns a new collection of the same multiplicity and iteration order containing the result of applying a given function to each element. The output cardinality equals the input cardinality.

#### Test cases

| Collection | Function         | Output     |
| ---------- | ---------------- | ---------- |
| \[1, 2, 3] | add 1 to element | \[2, 3, 4] |
| \[]        | add 1 to element | \[]        |
| \[2, 2, 3] | add 1 to element | \[3, 3, 4] |

### Filter [Operation](#operation)

*[Required][req].* Returns a new collection containing only the elements for which a given predicate returns [Boolean][bool] `true`, preserving multiplicity and iteration order.

#### Test cases

| Collection | Predicate              | Output  |
| ---------- | ---------------------- | ------- |
| \[1, 2, 3] | element greater than 1 | \[2, 3] |
| \[1, 2, 3] | element greater than 5 | \[]     |
| \[]        | any element            | \[]     |
| \[1, 1, 2] | element less than 2    | \[1, 1] |

### Distinct [Operation](#operation)

*[Required][req].* Precondition: element type implements [Equality][eq]. Returns a new collection with duplicates removed so that no two elements compare [Equal][eq-equal]. The resulting collection has multiplicity **unique**.

When iteration order is **insertion** or **key**, the first occurrence of each distinct value is retained and relative order is preserved (stable). When iteration order is **none**, the relative order of retained elements is unspecified.

#### Test cases

| Collection    | Output     |
| ------------- | ---------- |
| \[1, 2, 1, 3] | \[1, 2, 3] |
| \[1, 1, 1]    | \[1]       |
| \[]           | \[]        |
| \[3, 1, 2, 1] | \[3, 1, 2] |

### Union [Operation](#operation)

*[Required][req].* Precondition: element type implements [Equality][eq]. Returns a collection containing all elements from either collection.

* For **unique** collections: each distinct element appears exactly once (set union).
* For **multi** collections: each element appears as many times as the sum of its occurrences across both collections (bag union).

#### Test cases

| Collection A | Collection B | Output (unique) |
| ------------ | ------------ | --------------- |
| \[1, 2]      | \[2, 3]      | \[1, 2, 3]      |
| \[1, 2]      | \[]          | \[1, 2]         |
| \[]          | \[3]         | \[3]            |
| \[]          | \[]          | \[]             |

### Intersect [Operation](#operation)

*[Required][req].* Precondition: element type implements [Equality][eq]. Returns a collection containing only elements that appear in both collections.

* For **unique** collections: each distinct common element appears exactly once (set intersection).
* For **multi** collections: each element appears as many times as the minimum of its occurrences in each collection (bag intersection).

#### Test cases

| Collection A | Collection B | Output (unique) |
| ------------ | ------------ | --------------- |
| \[1, 2, 3]   | \[2, 3, 4]   | \[2, 3]         |
| \[1, 2]      | \[3, 4]      | \[]             |
| \[]          | \[1]         | \[]             |
| \[1, 2]      | \[]          | \[]             |

### Difference [Operation](#operation)

*[Required][req].* Precondition: element type implements [Equality][eq]. Returns a collection containing elements from the first collection that do not appear in the second.

* For **unique** collections: each element of the first that is absent from the second appears exactly once (set difference).
* For **multi** collections: the occurrence count of each element is reduced by its occurrence count in the second collection, with a floor of zero (bag difference).

#### Test cases

| Collection A | Collection B | Output (unique) |
| ------------ | ------------ | --------------- |
| \[1, 2, 3]   | \[2, 3]      | \[1]            |
| \[1, 2]      | \[3, 4]      | \[1, 2]         |
| \[]          | \[1]         | \[]             |
| \[1, 2, 3]   | \[]          | \[1, 2, 3]      |

### Sort By [Operation](#operation)

*[Required][req].* Precondition: a key function and a [Compare][compare] expression over the key type are provided. Returns a new collection with elements ordered by the key in ascending order. The resulting collection has iteration order **key**. Tie-breaking is stable: elements with equal keys retain their relative input order.

#### Test cases

| Collection      | Key function            | Output          |
| --------------- | ----------------------- | --------------- |
| \[3, 1, 2]      | element itself          | \[1, 2, 3]      |
| \[2, 2, 1]      | element itself          | \[1, 2, 2]      |
| \[]             | element itself          | \[]             |
| \[(b,1), (a,2)] | first component of pair | \[(a,2), (b,1)] |

### Then By [Operation](#operation)

*[Derived][der].* Precondition: a preceding [Sort By](#sort-by-operation) or Then By has established a primary key ordering; a secondary key function and [Compare][compare] expression over the secondary key type are provided. Returns a new collection where elements with equal primary keys are further ordered by the secondary key. Tie-breaking on the secondary key is stable. Defined in terms of [Sort By](#sort-by-operation) applied to a composite key that lexicographically combines the primary and secondary keys.

#### Test cases

| Collection             | Primary key             | Secondary key            | Output                 |
| ---------------------- | ----------------------- | ------------------------ | ---------------------- |
| \[(a,2), (a,1), (b,1)] | first component of pair | second component of pair | \[(a,1), (a,2), (b,1)] |
| \[(b,2), (a,1), (a,2)] | first component of pair | second component of pair | \[(a,1), (a,2), (b,2)] |

### Min [Operation](#operation)

*[Required][req].* Precondition: element type implements [Ordering][ord]; minimum cardinality ≥ 1. Returns the smallest element according to [Compare][compare]. If multiple elements are [Equal][or-equal], any one of them may be returned.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[3, 1, 2] | 1      |
| \[5]       | 5      |
| \[1, 1, 2] | 1      |

### Max [Operation](#operation)

*[Required][req].* Precondition: element type implements [Ordering][ord]; minimum cardinality ≥ 1. Returns the largest element according to [Compare][compare]. If multiple elements are [Equal][or-equal], any one of them may be returned.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[3, 1, 2] | 3      |
| \[5]       | 5      |
| \[1, 2, 2] | 2      |

### Min Or None [Operation](#operation)

*[Derived][der].* Precondition: element type implements [Ordering][ord]. Returns the smallest element if the collection is non-empty, or an absent value otherwise. Defined in terms of [Is Empty](#is-empty-operation) and [Min](#min-operation).

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[3, 1, 2] | 1      |
| \[5]       | 5      |
| \[]        | none   |

### Max Or None [Operation](#operation)

*[Derived][der].* Precondition: element type implements [Ordering][ord]. Returns the largest element if the collection is non-empty, or an absent value otherwise. Defined in terms of [Is Empty](#is-empty-operation) and [Max](#max-operation).

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[3, 1, 2] | 3      |
| \[5]       | 5      |
| \[]        | none   |

### Reduce [Operation](#operation)

*[Required][req].* Precondition: minimum cardinality ≥ 1. Combines all elements using a binary associative function without an initial accumulator, returning a single value of the same type.

#### Test cases

| Collection | Function          | Output |
| ---------- | ----------------- | ------ |
| \[1, 2, 3] | sum of two values | 6      |
| \[5]       | sum of two values | 5      |
| \[2, 3, 4] | max of two values | 4      |

### Reduce Or None [Operation](#operation)

*[Derived][der].* Like [Reduce](#reduce-operation) but returns an absent value when the collection is empty. Defined in terms of [Is Empty](#is-empty-operation) and [Reduce](#reduce-operation).

#### Test cases

| Collection | Function          | Output |
| ---------- | ----------------- | ------ |
| \[1, 2, 3] | sum of two values | 6      |
| \[5]       | sum of two values | 5      |
| \[]        | sum of two values | none   |

### Sum [Operation](#operation)

*[Derived][der].* Precondition: element type implements [Number][num]. Returns the total of all elements. Defined as [Reduce](#reduce-operation) with [Addition](#addition-operation) when the collection is non-empty, and zero otherwise.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[1, 2, 3] | 6      |
| \[5]       | 5      |
| \[]        | 0      |
| \[2, 2, 2] | 6      |

### Average [Operation](#operation)

*[Derived][der].* Precondition: element type implements [Number][num]; minimum cardinality ≥ 1. Returns the arithmetic mean of all elements. Defined as [Sum](#sum-operation) divided by [Size](#size-operation).

#### Test cases

| Collection | Output |
| ---------- | ------ |
| \[1, 2, 3] | 2      |
| \[2, 4]    | 3      |
| \[5]       | 5      |

## [Type Class Instances](#type-class-instances-5)

Collection does not itself implement a [type class](#type-class). The applicability of individual operations depends on the element type's type class instances and the collection's [attribute](#attribute) values, as stated in each operation's preconditions.

[bool]: #boolean-type

[col-iter]: #collection-iteration-order-type

[col-mult]: #collection-multiplicity-type

[compare]: #compare-operation

[der]: #derived

[eq]: #equality-type-class

[eq-equal]: #equal-operation

[int]: #integer

[num]: #number-type-class

[or-equal]: #equal

[ord]: #ordering-type-class

[req]: #required

# Parameter

A parameter is a [type](#type) supplied at instantiation time. A type that
declares one or more parameters is called a *parametric type* (analogous to
generics). The parameter name acts as a placeholder for the concrete element
type used in the type's operations.

For example, [Collection](#collection-type) is parametric over an
element type `T`. Every operation that accepts or returns an element works
with `T` rather than a fixed type.

# Type

A type describes a set of values and the operations that apply to them. Each
type is defined in its own module under [Expressions](../expressions/).

A type may carry [attributes](#attribute) that configure an instance and
[parameters](#parameter) that make it generic over other types.

## Member Values

Every type enumerates or characterises the values it contains. For small,
fixed sets the members are listed explicitly (e.g.,
[Boolean](#boolean-type) has `true` and `false`). For open sets
the membership rule is stated instead (e.g., [Integer](#integer)
contains every whole number within a representable range).

## Type Class Instances

A type may implement one or more [type classes](#type-class). The
**Type Class Instances** section of a type module lists the type classes it
implements, each as a link to the corresponding type class definition.

# Optionality

A property applied to a *slot* — a [parameter][param], an [attribute][attr],
a record field, or the result of an [operation][op] — indicating whether
the slot must carry a value or may be absent.

Optionality is a property of the slot itself, not a type constructor. A
slot of type [Integer][int] marked optional still has type [Integer][int];
what varies is whether a value is present. There is no wrapper type, no
`Maybe`, no `Option`. Operations consume and produce values of the declared
type directly.

## Rationale

Generic wrapper types (`Maybe a`, `Option<T>`, `Nullable<T>`) force every
downstream operation to either unwrap the value or be lifted over the
wrapper. Even simple arithmetic acquires plumbing. Substrate instead
attaches optionality to the binding site, so ordinary expressions read
naturally; absence handling surfaces only where it is semantically
relevant.

## States

A slot is in exactly one of two states:

* **Required** — a value must be supplied. Absence is an error detected at
  the point where the slot is bound.
* **Optional** — a value may be supplied. Absence is an acceptable state
  called *absent*.

Required is the default. A slot must be explicitly marked to become
optional.

## Absence

Absence is not a member of any [type][type]. It is a property of the slot:
the slot exists but carries no value. [Equality][eq], [ordering][ord], and
arithmetic are not defined between a value and absence. Two absent slots
are not considered equal to each other by [Equal][eq-equal]; presence must
be checked first.

## Where Optionality Applies

* **[Parameters][param]** of operations. An operation may declare any
  parameter optional.
* **[Attributes][attr]** of types. For example, the maximum cardinality
  attribute of [Collection][col] is optional; when unspecified, the
  collection is unbounded.
* **Fields of records.** Each field carries its own optionality marking.
* **Operation results.** An operation may declare that its result is
  optional, meaning the operation produces either a value of the declared
  type or absence. [Min Or None][min-or-none] is an example.

In each case, optionality is declared alongside the slot's declared type
and carries the semantics defined here.

## Absence Semantics in Operations

An [operation][op] applied to an absent input is undefined and must not be
evaluated. Callers must coalesce an optional value with
[Default](#default-operation) before passing it to an operation whose
parameter is required.

This rule is uniform: operations are not implicitly lifted over absence, do
not silently skip absent inputs, and do not propagate absence to their
result. Any behaviour that depends on absence must be expressed explicitly
in the user module using [Is Present](#is-present-operation) or
[Default](#default-operation).

Operations that *produce* an optional result declare so explicitly and
describe the conditions under which the result is absent.

## Operations on Optional Slots

Two operations are universally available for reasoning about absence,
regardless of the slot's declared type.

### Is Present [Operation][op]

*[Required][req].* Returns [Boolean][bool] `true` when the slot carries a
value, `false` when the slot is absent.

#### Test cases

| Slot value | Output |
| ---------- | ------ |
| `42`       | true   |
| absent     | false  |

### Default [Operation][op]

*[Required][req].* Returns the slot's value when present, or the supplied
fallback value when absent. The fallback must have the slot's declared
type.

#### Test cases

| Slot value | Fallback | Output |
| ---------- | -------- | ------ |
| `42`       | `0`      | 42     |
| absent     | `0`      | 0      |
| `-1`       | `0`      | -1     |

## Interaction with Types and Type Classes

Optionality is orthogonal to [Type][type]. Declared type determines which
[type class][tc] instances and operations apply; optionality determines
whether the slot must be occupied. Marking a slot optional does not change
its type and does not remove or add type class instances.

[attr]: #attribute

[bool]: #boolean-type

[col]: #collection-type

[eq]: #equality-type-class

[eq-equal]: #equal-operation

[int]: #integer

[min-or-none]: #min-or-none-operation

[op]: #operation

[ord]: #ordering-type-class

[param]: #parameter

[req]: #required

[tc]: #type-class

[type]: #type

# Choice

A Choice is a [type](#type) whose members are partitioned into a fixed
set of named **variants**. Every value of a Choice type is exactly one
variant. A variant may carry zero or more typed fields; the fields of
different variants are independent.

A Choice with zero-field variants only is an enumeration: its values are
effectively named constants. [Boolean](#boolean-type) and
[Collection Multiplicity](#collection-multiplicity-type) are
built-in examples. Choices with data-carrying variants express cases like
"a maturity bucket is either *Open*, a day *Range*, or *Beyond* a
threshold."

A choice type may be declared anywhere in the specification corpus. A
declaration is identified by a heading whose text links to this concept
page:

```markdown
### Maturity Bucket [Choice](choice.md)
```

## Variants

A Choice type declares its variants in a **Variants** section as a
bulleted list. Each entry supplies:

* A **variant name**, unique within the Choice type.
* A short description of the variant's meaning.
* Zero or more **fields**, each nested as a sub-bullet. Each field
  supplies a name, a declared [type](#type) linked to its definition,
  an [optionality](#optionality) marking, and a short description.

For example:

```markdown
#### Variants

- **Open** — no contractual maturity.
- **Range** — a contiguous range of days.
  - `from_days` — [Integer](../expressions/integer.md), required.
    Lower bound, inclusive.
  - `to_days` — [Integer](../expressions/integer.md), required.
    Upper bound, inclusive.
- **Beyond** — longer than a threshold.
  - `from_days` — [Integer](../expressions/integer.md), required.
    Lower bound, exclusive.
```

Variant names are unique within a Choice type. Field names are unique
within a variant but may repeat across variants with unrelated meanings.
The order of variant declaration is canonical for presentation; it does
not by itself imply ordering semantics.

## Operations

The following meta-operations are available on every Choice type. They
reference variant and field names declared by the specific Choice type
in scope.

### Construct [Operation](#operation)

*[Required](#required).* Returns a new value of the Choice
type by selecting a named variant and supplying a value for each of that
variant's fields. Required fields must be supplied; optional fields may
be supplied as absent.

#### Test cases

| Choice type       | Variant  | Field values               | Output        |
| ----------------- | -------- | -------------------------- | ------------- |
| `Maturity Bucket` | `Open`   | —                          | `Open`        |
| `Maturity Bucket` | `Range`  | `from_days: 2, to_days: 7` | `Range(2, 7)` |
| `Maturity Bucket` | `Beyond` | `from_days: 365`           | `Beyond(365)` |

### Is Variant [Operation](#operation)

*[Required](#required).* Returns [Boolean][bool] `true` when
the value is the named variant, `false` otherwise.

#### Test cases

| Value         | Variant | Output |
| ------------- | ------- | ------ |
| `Open`        | `Open`  | true   |
| `Open`        | `Range` | false  |
| `Range(2, 7)` | `Range` | true   |

### Match [Operation](#operation)

*[Required](#required).* Branches on which variant a value
is. For each variant of the Choice type, Match takes an expression to
evaluate when the value is that variant. The expression may refer to
the variant's fields by name. The result is the value of the expression
for the variant that matched.

Every variant of the Choice type must be covered: Match is exhaustive.
All branch expressions must produce values of the same type; that type
is the type of the Match result.

#### Test cases

For a Choice type `Signed Integer` with variants `Positive` (field
`value`), `Zero` (no fields), and `Negative` (field `value`), Match is
used to compute the absolute value:

| Value         | Positive branch | Zero branch | Negative branch | Output |
| ------------- | --------------- | ----------- | --------------- | ------ |
| `Positive(5)` | `value`         | `0`         | `value`         | 5      |
| `Zero`        | `value`         | `0`         | `value`         | 0      |
| `Negative(3)` | `value`         | `0`         | `value`         | 3      |

## Type Class Instances

* **[Equality](#equality-type-class)** is implemented automatically
  when every field type across every variant implements Equality. Two
  values are equal when they are the same variant and, for each field,
  the two values are equal under that field's type's Equality. When a
  variant has no fields, comparing two values of that variant is
  equality on variant name alone. This makes pure-enumeration Choices
  (zero-field variants) equal exactly when their variants match, which
  matches [Boolean](#boolean-type)'s behaviour.

* **[Ordering](#ordering-type-class)** is not implemented by
  default. A specific Choice may declare an Ordering instance in its
  own declaration and state the comparison rule — for example, maturity
  buckets ordered by the day ranges their variants represent.

[bool]: #boolean-type

# String [Type](#type)

## Overview

The String type represents finite sequences of Unicode code points. It is
used for textual data such as names, identifiers, codes, and free-form
descriptions.

A String value is always fully present; the empty string `""` is a
distinguished member value, not to be confused with an absent
[optional](#optionality) slot.

## [Member Values](#member-values-6)

Every finite sequence of Unicode code points, including the empty
sequence, is a member of String. Individual characters are not a separate
type; operations that address characters do so by position within the
string.

Length and positional operations count Unicode code points. Grapheme-cluster
or byte-level semantics, when needed, are expressed by dedicated operations
rather than by the primitive operations defined here.

## Operations

### Length [Operation](#operation)

*[Required](#required).* Returns the number of
Unicode code points in the string as an [Integer][int].

#### Test cases

| Input   | Output |
| ------- | ------ |
| `""`    | 0      |
| `"a"`   | 1      |
| `"abc"` | 3      |

### Concatenate [Operation](#operation)

*[Required](#required).* Returns a new string
containing the code points of the first input followed by the code points
of the second.

#### Test cases

| Input A | Input B | Output   |
| ------- | ------- | -------- |
| `""`    | `""`    | `""`     |
| `"ab"`  | `""`    | `"ab"`   |
| `""`    | `"cd"`  | `"cd"`   |
| `"ab"`  | `"cd"`  | `"abcd"` |

### Is Empty [Operation](#operation)

*[Derived](#derived).* Returns [Boolean][bool]
`true` when the string contains no code points. Defined as
[Length](#length-operation) equal to zero.

#### Test cases

| Input   | Output |
| ------- | ------ |
| `""`    | true   |
| `"a"`   | false  |
| `"abc"` | false  |

### Contains [Operation](#operation)

*[Required](#required).* Returns [Boolean][bool]
`true` when the second input appears as a contiguous subsequence of code
points within the first. Every string contains the empty string.

#### Test cases

| Input    | Substring | Output |
| -------- | --------- | ------ |
| `"abcd"` | `"bc"`    | true   |
| `"abcd"` | `"ce"`    | false  |
| `"abcd"` | `""`      | true   |
| `""`     | `""`      | true   |
| `""`     | `"a"`     | false  |

## [Type Class Instances](#type-class-instances-5)

* **[Equality][eq]** — two strings are equal when they contain the same
  sequence of code points.
* **[Ordering][ord]** — strings are compared lexicographically by code
  point. The empty string precedes every non-empty string.

[bool]: #boolean-type

[eq]: #equality-type-class

[int]: #integer

[ord]: #ordering-type-class

# Record

A Record is a composite [type](#type) with a fixed set of named fields.
Each field has a declared [type](#type) and an [optionality](#optionality)
marking. The identity of a record type is its name: two record types with
the same fields but different names are distinct.

A record type may be declared anywhere in the specification corpus —
inside a dedicated module, as a subsection of a larger document, or
alongside the logic that consumes it. A declaration is identified by a
heading whose text links to this concept page, following the same pattern
that [operations](#operation) use to link to their concept:

```markdown
### Customer [Record](record.md)
```

Field names are unique within a record type.

## Fields

A record type declares its fields in a **Fields** section. Each entry
supplies:

* A **name** by which the field is accessed.
* A declared [type](#type) linked to its definition.
* An [optionality](#optionality) marking — *required* or *optional*.
  Required is the default.
* A short description of the field's meaning.

Fields are listed in declaration order. Declaration order is canonical
for presentation and serialisation but not semantically significant for
access: fields are always addressed by name, never by position.

The fields are typically presented as a table:

| Name    | Type                   | Optionality | Description                  |
| ------- | ---------------------- | ----------- | ---------------------------- |
| `name`  | [String](#string-type) | required    | The customer's display name. |
| `email` | [String](#string-type) | optional    | Contact email, if supplied.  |

## Operations

The following meta-operations are available on every record type. They
reference field names declared by the specific record type in scope.

### Get Field [Operation](#operation)

*[Required](#required).* Returns the value of the named field
from a record. If the field is declared [optional](#optionality) and no
value is present, the result is absent; see [Optionality](#optionality)
for absence semantics.

#### Test cases

| Record                           | Field   | Output |
| -------------------------------- | ------- | ------ |
| `{ name: "Ada", email: "a@x" }`  | `name`  | "Ada"  |
| `{ name: "Ada", email: "a@x" }`  | `email` | "a\@x" |
| `{ name: "Ada", email: absent }` | `email` | absent |

### With Field [Operation](#operation)

*[Required](#required).* Returns a new record of the same
type with the named field replaced by the supplied value. All other
fields retain their current values. The supplied value must match the
field's declared type; its presence or absence must be compatible with
the field's optionality.

#### Test cases

| Record                          | Field   | Value  | Output                           |
| ------------------------------- | ------- | ------ | -------------------------------- |
| `{ name: "Ada", email: "a@x" }` | `name`  | "Bea"  | `{ name: "Bea", email: "a@x" }`  |
| `{ name: "Ada", email: "a@x" }` | `email` | absent | `{ name: "Ada", email: absent }` |

### Construct [Operation](#operation)

*[Required](#required).* Returns a new record of the
specified type given a value for each field. Required fields must be
supplied; optional fields may be supplied as absent.

#### Test cases

| Record type | Field values                 | Output                           |
| ----------- | ---------------------------- | -------------------------------- |
| `Customer`  | `name: "Ada", email: "a@x"`  | `{ name: "Ada", email: "a@x" }`  |
| `Customer`  | `name: "Ada", email: absent` | `{ name: "Ada", email: absent }` |

## Type Class Instances

Record does not itself implement a [type class](#type-class). A specific
record type may declare type class instances in its own declaration when
useful — for example, an [Equality](#equality-type-class) instance
defined field-by-field. Such declarations are made per record type, not
derived automatically, because the treatment of absent fields in equality
and ordering is a design decision of the specific type.

# Decision Table

A Decision Table is a tabular representation of a conditional: a set of
rules, evaluated top to bottom, where the first rule whose conditions all
match determines the result. It is the tabular counterpart to nested
[If-Then-Else](#if-then-else-operation) and
complements the decision-tree style of branching with a data-style form
that reads as a single artifact.

Decision Tables are well suited to regulatory material, rate sheets,
classification rules, and any logic whose authoritative reference is
itself a table. The rendered markdown table is the authoritative
specification; no separate machine form is required.

A decision table may be declared anywhere in the specification corpus.
A declaration is identified by a heading whose text links to this concept
page:

```markdown
### Retail Outflow Rate [Decision Table](decision-table.md)
```

## Structure

A decision table declaration has three parts:

* **[Inputs](#inputs)** — the named values the table reads, each with its
  declared [type](#type).
* **[Outputs](#outputs)** — the named values the table produces, each with
  its declared [type](#type).
* **[Rules](#rules)** — a markdown table where each row is a rule. Column
  headers name an input or output; headers prefixed with `→` name outputs,
  all other headers name inputs.

### Inputs

A bulleted list declaring each input with its name and type. Input order
is not semantically significant; inputs are addressed by name.

```markdown
#### Inputs

- `counterparty` — [Counterparty](counterparty.md)
- `insured` — [Boolean](../expressions/boolean.md)
- `account_type` — [Account Type](account-type.md)
```

### Outputs

A bulleted list declaring each output with its name and type.

```markdown
#### Outputs

- `outflow_rate` — [Decimal](../expressions/decimal.md)
```

### Rules

A markdown table. The header row names inputs and outputs; `→` marks
output columns. Each subsequent row is a rule.

A row matches when every condition cell matches. A matching row's output
cells determine the result. Rows are evaluated in document order and the
first matching row wins.

## Condition Cells

A condition cell takes one of the following forms:

* **Literal value.** A bare value matches when the input is
  [Equal](#equal-operation) to the value under
  the input type's Equality instance.
* **Comparison.** One of `=`, `≠`, `>`, `≥`, `<`, `≤` followed by a
  literal value. ASCII equivalents `==`, `!=`, `>=`, `<=` are also
  accepted. Comparisons require the input type to implement
  [Ordering](#ordering-type-class); `=` and `≠` require only
  [Equality](#equality-type-class).
* **Blank (don't care).** An empty cell matches any input value.

The table form is intentionally limited to literals and simple
comparisons so that each rule remains readable as data. Arbitrary
predicates beyond these forms are expressed by introducing a derived
input: define the predicate as a named value upstream of the decision
table and reference that name as an ordinary input column. This keeps
the table readable while preserving full expressiveness.

## Result Cells

A result cell contains a literal value of the output column's declared
type. Expressions, function calls, and references to other values are
not permitted in result cells; computations that depend on a decision's
result are performed downstream by operations that consume the table's
outputs.

## Otherwise Row

A rule whose first cell is the literal word `otherwise` is a catch-all:
it matches any input and must appear as the last row. Its condition
cells beyond the first are ignored; its output cells supply the result
when no earlier rule matched.

## Completeness

A decision table must account for every possible input. Completeness is
satisfied when any of the following holds:

* An `otherwise` row is present.
* Every input column is a [Choice](#choice) used only with literal
  cells, and the rules collectively cover every combination of variants.

If neither condition holds, an input that matches no rule is a runtime
error detected at evaluation time.

## Evaluation

Given values for every input:

1. Consider each row in document order.
2. For each row, evaluate every condition cell against the corresponding
   input. A row matches when all its condition cells match.
3. On the first matching row, produce each output as the value in the
   corresponding result cell.
4. If no row matches and no `otherwise` row is present, evaluation is
   undefined.

## Invocation

A decision table is invoked from a user module exactly like an
[operation](#operation): the table's heading link is the parent item
of a nested list, and each child item supplies one of the table's
inputs in the same order they are declared. The result is the table's
output. When a table declares a single output, the invocation yields
that output directly; when it declares multiple outputs, the invocation
yields a record whose fields are the declared output names.

For example, given the table declared below, the retail outflow rate
for a classified deposit row is obtained as:

```markdown
- [Retail Outflow Rate](retail-outflow-rate.md)
  - `row.counterparty`
  - `row.insured`
  - `row.account_type`
  - `row.relationship`
```

This reads the same as any other operation call and is composable with
arithmetic and collection operations — for example, multiplying the
returned rate by an amount, or mapping the table over a collection of
rows.

## Relationship to If-Then-Else

A decision table with two rules and one output is semantically equivalent
to a single [If-Then-Else](#if-then-else-operation)
applied to the conjunction of the first row's conditions. A table with
N rules is equivalent to a cascade of nested If-Then-Else. Authors choose
the form that best communicates intent: If-Then-Else for one-off
branches; Decision Table when the same condition columns determine
multiple related results and the rules form an authoritative table.

## Example

```markdown
### Retail Outflow Rate [Decision Table](decision-table.md)

#### Inputs

- `counterparty` — [Counterparty](counterparty.md)
- `insured` — [Boolean](../expressions/boolean.md)
- `account_type` — [Account Type](account-type.md)
- `relationship` — [Relationship](relationship.md)

#### Outputs

- `outflow_rate` — [Decimal](../expressions/decimal.md)

#### Rules

| counterparty | insured | account_type      | relationship | → outflow_rate |
| ------------ | ------- | ----------------- | ------------ | -------------- |
| Retail       | true    | Transactional     |              | 0.03           |
| Retail       | true    | Non-Transactional | Established  | 0.03           |
| Retail       | true    | Non-Transactional | None         | 0.10           |
| Retail       | false   |                   |              | 0.40           |
| otherwise    |         |                   |              | 0.40           |
```

# Vision Document: An LLM-Native Executable Specification Language

## 1. Executive Summary

This project envisions a new kind of programming language: an
**LLM-native executable specification language** designed for
spec-driven development.

The language is:

* Generated and refined by LLMs
* Structurally analyzable and verifiable
* Debuggable by humans --- including non-technical stakeholders
* Explicitly designed around traceability and dataflow semantics

It is not merely a programming language, but a **formal substrate for
building verifiable systems from natural-language specifications**.

***

## 2. Core Design Principles

### 2.1 Semantics Over Syntax

The language prioritizes meaning over form. Structure emerges from semantic
intent --- what something means matters more than how it is written. There is
no rigid grammar or formal syntax; the canonical representation is markdown
enriched with natural language.

The language uses native markdown syntax wherever possible. Extended syntax
is permitted only when it is broadly supported by major rendering tools,
with GitHub-flavored Markdown as the primary compatibility target. This
keeps the specification approachable: any contributor --- human or
machine --- can read, edit, and render it with standard tooling.

Alternative intermediate formats are permitted when markdown alone is
insufficient for precision or conciseness. They may appear as code blocks
embedded in a module or as separate artifact files. In either case, every
alternative-format fragment must carry a provenance reference identifying the
specification section or operation it belongs to.

### 2.2 Spec-First, Not Code-First

The primary artifact is the *executable specification*.\
Implementation emerges from structured specification --- not the other
way around.

### 2.3 LLM-Native by Design

The language must support:

* Natural language → structured semantics extraction
* Structured semantics → natural language regeneration
* Partial subtree regeneration
* Semantic (structure-aware) diffing
* Deterministic regeneration under refinement

Markdown is the primary representation. Alternative formats may be embedded
as code blocks or referenced as separate artifacts, always with provenance
back to the originating specification fragment.

### 2.4 Structured + Human-Readable Hybrid

Natural language is preserved where appropriate, but embedded inside a
structured substrate that enables:

* Semantic validation
* Consistency checking
* Dependency validation
* Tooling support

The markdown documents serve as an all-encompassing semantic context for
human and machine contributors. Links are the primary enrichment
mechanism: they associate types, operations, and provenance with terms and
structures that would otherwise be plain text. All available markdown
features --- headings, tables, lists, links, footnotes --- are used to
carry semantic information within the document.

The markdown format is intentionally permissive. Structure is defined by
relative heading depth (e.g., a test cases section must appear under its
operation's heading) rather than by absolute heading levels. Additional
grouping sections are allowed between any structural elements.

***

## 3. Semantic Model

### 3.1 Executable Specification Graph

The program is a **typed dataflow graph** where:

* Nodes represent transformations or decisions
* Edges represent explicit data contracts
* Inputs and outputs are first-class
* Execution order is derived from data dependencies

Timing dependencies are not primary --- dataflow is.

### 3.2 Markdown as Source of Truth

The markdown specification is the canonical artifact:

* It is the primary human-readable and LLM-readable form
* It enables structural validation via relative heading relationships
* It supports automated tooling without prescribing rigid formatting
* It carries provenance metadata linking logic back to natural language

Alternative formats (embedded code blocks or separate files) are projections
of the markdown source and must maintain bidirectional traceability. Structured
representations such as YAML may be derived from the markdown, but they are
not the source of truth.

### 3.3 Source-Map-Like Provenance

Every structured node may carry metadata linking back to:

* Original natural language fragments
* Specification paragraphs
* Semantic anchors

This enables:

* Auditable traceability
* Explainable rule behavior
* Regeneration without losing intent mapping

***

## 4. Verification Model

### 4.1 Static Verification

The system should support:

* Structural validation
* Schema consistency
* Type compatibility
* Dependency completeness
* Detection of unreachable or orphan nodes

### 4.2 Dynamic Verification

At runtime, the system supports:

* Example-driven testing (BDD-style)
* Property validation
* Data contract enforcement
* Invariant checking

Verification is layered and granular --- not monolithic.

***

## 5. Human Debuggability

The language must be understandable beyond engineering teams.

This requires:

* Clear rule identifiers
* Plain-language descriptions bound to logic
* Visualizable execution graphs
* Deterministic execution traces
* Error messages that reference specification fragments

Failures must be explainable in business terms, not just technical stack
traces.

***

## 6. Productionization Path

The language should enable transformation from:

Exploratory code → Structured spec → Verified executable → Language projection → Production system

This includes:

* Extraction of inputs/outputs
* Formalization of transformations
* Embedding of example datasets
* Automatic generation of validation tests
* Documentation derived from the spec itself
* Derivation of target-language implementations via AI agents

The executable specification becomes the single source of truth across
environments.

***

## 7. Architectural Characteristics

The envisioned language is:

* Semantics-first
* Declarative
* Dataflow-oriented
* Metadata-rich
* Deterministic
* Extensible via embedded DSLs
* Projection-friendly
* Designed for LLM collaboration

It unifies documentation, testing, orchestration, and execution into a
single semantic substrate.

***

## 8. Long-Term Ambition

To establish a new paradigm:

> Systems are built from structured, verifiable specifications that are
> co-developed with LLMs and remain explainable to humans.

The executable specification becomes:

* The documentation
* The contract
* The test harness
* The runtime blueprint
* The source for automatic derivation of target-language implementations

All in one artifact.

***

## 9. Language Projections

A core goal of the language is **automatic derivation of implementations in
target programming languages** by AI agents.

A projection transforms a specification into a runnable implementation in a
target language (e.g., TypeScript, Python, SQL). The specification's natural
language descriptions and test cases serve as the authoritative semantic
reference. Built-in operations have no implementation in the language itself
unless they are derived from other operations --- the natural language
description and test cases together **are** the definition.

Projections must:

* Preserve the semantics defined by the specification
* Pass all test cases defined in the source module
* Maintain provenance links to the originating specification fragments

A projection is validated by running the test cases from the specification
against the generated implementation. The specification, not the projection,
is the source of truth.

***

## 10. Type Inference and Document Enrichment

A dedicated tool performs **type inference and type checking** across the
specification corpus. Its two responsibilities are distinct:

**Type checking** validates that every operation's inputs, outputs, and
derived relationships are consistent with the declared types across all
modules. Errors and warnings are reported against the originating
specification fragment.

**Document enrichment** augments the existing markdown source files with
type information derived from inference. Enrichment is non-destructive: it
does not alter the authored prose or table content. Instead, it attaches
inferred type annotations as **reference-style footnotes** supported by
GitHub-flavored Markdown (e.g., `[^type-price]` at the annotated term,
with `[^type-price]: inferred type: Decimal` at the end of the file).
Footnotes keep type information co-located with the content they describe
while remaining visually unobtrusive in rendered output.

This approach preserves full round-trip fidelity: the enriched document
remains valid, human-readable markdown, and the footnotes serve as
machine-readable type metadata that further tooling --- including LLMs ---
can consume during subsequent inference or projection passes.

***

## 11. Live Data Binding and Specification Debugging

A specification can be **bound to a live data source** --- a production
database, a query result set, or a data file --- and executed against real
inputs while the operator observes the rendered markdown document.

This creates a **markdown-native debugger** aimed at non-technical
stakeholders. Rather than presenting stack frames or variable watches, the
debugger drives a rendered view of the specification itself. As execution
steps through an operation, the current input values and intermediate
results are overlaid directly on the relevant section of the markdown
document: table cells are annotated with live values, rule conditions light
up as they are evaluated, and the active step is highlighted within the
prose.

The interaction model mirrors a conventional step-debugger:

* **Bind** — attach a data source (database connection, file, or in-memory
  dataset) to a specification module.
* **Step** --- advance execution one operation or one row at a time,
  observing how values flow through the defined logic.
* **Inspect** --- hover or select any term in the rendered document to see
  the current bound value and its provenance in the data source.
* **Replay** --- re-run the same inputs after editing the specification to
  observe the effect of the change immediately.

Because the visualization is driven by the markdown document rather than a
separate debugger UI, the experience is identical whether the viewer is an
engineer or a domain expert. The specification is the debugger interface.

***

## 12. Immediate Impact Analysis

When a specification is edited, the tool can re-execute the entire
specification against the current bound data source and **highlight the
differences in output** relative to the previous run. This gives the author
immediate, evidence-based feedback on the consequences of a change.

The diff is presented in the rendered markdown view:

* Outputs that changed value are annotated inline, showing both the old and
  new result.
* Rows or cases that newly pass or fail a condition are marked visually.
* Aggregates and derived values that are transitively affected by the change
  are surfaced, even if the edited operation is not the direct producer.

This transforms specification editing from a write-and-guess workflow into
a **tight feedback loop**: edit a rule, observe the ripple effect across all
data immediately, and confirm or revert the change before it propagates
further. The impact analysis operates on the same markdown-native interface
as the live debugger, requiring no additional tooling or context switch.

***

## 13. Versioning

Specification corpora evolve over time as the regulations or domains they
codify are amended or superseded. Substrate treats this as an ordinary
software versioning problem rather than a temporal modelling problem:
corpora are versioned using the same mechanisms used for source code and
library packages --- git tags, semantic version identifiers, package-manager
releases. A given corpus at a given version is the authoritative
specification for the regulatory version it codifies; historical reporting
is served by checking out the appropriate corpus version.

This keeps the specification language itself free of effective-date
machinery. Date-sensitive behaviour within a single corpus version, when it
occurs, is expressed using the ordinary constructs --- for example, a
[Decision Table](#decision-table) with a reporting-date
column --- rather than through a dedicated versioning construct.

# Provenance

A Provenance section records the authoritative sources from which a
specification artifact derives. Any artifact — a [Record](#record)
type, a [Choice](#choice), a [Decision Table](#decision-table), an
[Operation](#operation), or a whole module — that encodes material
from an external document should declare its sources in a Provenance
section.

Provenance exists to make traceability explicit and machine-readable.
The rendered markdown remains the specification; the Provenance section
attaches the citations that turn it into an auditable artifact.

A provenance section is identified by a heading whose text is a link to
this concept page:

```markdown
### [Provenance](../concepts/provenance.md)
```

Its scope is the enclosing heading: a provenance section placed under a
specific declaration documents that declaration; one at module level
documents the module as a whole. Multiple provenance sections may appear
in the same document at different scopes.

## Contents

A Provenance section is free-form markdown. The following conventions
apply.

### Sources

At least one link to an authoritative source document is required.
Sources are listed as a bulleted list. Each entry links to the most
specific stable address available — for codified regulations, a deep
link to the cited section; for published rules, a deep link to the
Federal Register or equivalent; for PDFs, a link to the published PDF
with the citation marker (page, section) in the link text.

```markdown
- [12 CFR §249.32(a)(1)](https://www.ecfr.gov/current/title-12/chapter-II/subchapter-A/part-249/subpart-D/section-249.32#p-249.32(a)(1))
- [Federal Register, Vol. 79, No. 197, pp. 61440–61541 (Oct 10, 2014)](https://www.federalregister.gov/documents/2014/10/10/2014-22520)
```

Multiple sources are allowed and expected: a single rule may derive from
a statute, a codified regulation, an international framework, and
supervisory guidance. Each should be cited distinctly.

### Quoted Passages

When the specification encodes specific normative text, the passage
should be quoted directly using a markdown blockquote, immediately
following the source it is drawn from. A leading reference to the
source identifier makes the quote self-contained.

```markdown
- [12 CFR §249.32(a)(1)](https://www.ecfr.gov/current/title-12/chapter-II/subchapter-A/part-249/subpart-D/section-249.32#p-249.32(a)(1))

  > A covered company shall apply a 3 percent outflow rate to the
  > amount of FDIC-insured stable retail deposits held by a natural
  > person...
```

Quoted passages are optional but strongly encouraged when the artifact
encodes a specific rate, threshold, classification, or verbatim
obligation. A quote pinned to an artifact protects the spec against
silent upstream drift: a later edit that contradicts the quoted passage
is an observable inconsistency.

### Identifier

When the source is cited by a conventional identifier (a CFR section,
a paragraph number, a Basel paragraph), the identifier should appear in
the link text itself. Readers should not need to dereference the link
to know what is being cited.

## Relationship to Internal Provenance

The [vision document](#vision-document-an-llm-native-executable-specification-language) describes source-map-like
provenance between structured nodes and the natural-language fragments
they were derived from within the specification. That internal
provenance is a metadata mechanism carried on nodes.

A Provenance section, by contrast, documents **external** sources of
authority — regulations, standards, statutes, published guidance. Both
mechanisms are traceability tools; they operate on different axes and
do not replace each other.

## Example

```markdown
### Retail Outflow Rate [Decision Table](decision-table.md)

#### [Provenance](../concepts/provenance.md)

- [12 CFR §249.32(a)](https://www.ecfr.gov/current/title-12/chapter-II/subchapter-A/part-249/subpart-D/section-249.32#p-249.32(a))

  > Outflow amounts resulting from retail funding.

- [Federal Register, Vol. 79, No. 197, p. 61490 (Oct 10, 2014)](https://www.federalregister.gov/documents/2014/10/10/2014-22520)

  > The agencies are adopting a 3 percent outflow rate for stable
  > retail deposits, a 10 percent outflow rate for other retail
  > deposits, and higher rates for brokered deposits reflecting their
  > reduced stability during periods of liquidity stress.

#### Rules

...
```

# Account Type [Choice](#choice)

The Account Type classifies whether a deposit is held in a transactional
account. The distinction is material for LCR: transactional accounts are
presumed to be operational and receive a lower outflow rate.

## [Provenance](#provenance)

* [FR 2052a instructions, Product classifications for §O.D Outflows — Deposits][fr2052a-form]

  > The distinction between transactional and non-transactional accounts
  > follows Regulation D. Transactional accounts are deposits from which
  > the depositor is permitted to make transfers or withdrawals by
  > negotiable instrument, payment order, debit card, or similar means.

* [12 CFR §249.3 — Transactional account definition][cfr-3]

  > For purposes of this part, a transactional account has the meaning
  > given to "transaction account" in Regulation D (12 CFR part 204),
  > §204.2(e).

## Variants

* **Transactional** — a deposit account from which withdrawals or
  transfers may be made by negotiable instrument, payment order, debit
  card, or similar means (per Regulation D §204.2(e)).
* **Non-Transactional** — a deposit account from which such withdrawals
  are limited or not permitted (savings accounts, time deposits, etc.).

## Type Class Instances

* **[Equality](#equality-type-class)** —
  inherited automatically from the [Choice][choice] concept.

[choice]: #choice

[cfr-3]: https://www.ecfr.gov/current/title-12/part-249/section-249.3

[fr2052a-form]: https://www.federalreserve.gov/reportforms/forms/FR_2052a20220429_f.pdf
