# Collection [Type](../concepts/type.md)

## Overview

A Collection is a parametric type over an element type `T` that holds zero or more elements. Collections are characterized by four attributes:

- **multiplicity** ([Collection Multiplicity][col-mult]) — governs whether duplicate elements are permitted.
- **iteration order** ([Collection Iteration Order][col-iter]) — governs the sequence in which elements are visited during iteration.
- **minimum cardinality** ([Integer][int]) — the minimum number of elements the collection must contain.
- **maximum cardinality** ([Integer][int], optional) — the maximum number of elements the collection may contain.

## [Parameters](../concepts/parameter.md)

| Name | Description                                  |
| ---- | -------------------------------------------- |
| `T`  | The type of elements held in the collection. |

## [Attributes](../concepts/attribute.md)

### Multiplicity

Type: [Collection Multiplicity][col-mult]. Governs whether duplicate elements are permitted. See [Collection Multiplicity][col-mult] for the full definition of each value.

### Iteration Order

Type: [Collection Iteration Order][col-iter]. Governs the sequence in which elements are visited during iteration. When the value is **key**, a [tie-breaking](collection-iteration-order.md#tie-breaking) sub-attribute further specifies the relative order of elements with equal keys. See [Collection Iteration Order][col-iter] for the full definition of each value.

### Minimum Cardinality

Type: [Integer][int]. The minimum number of elements the collection must contain. When the minimum cardinality is `1` or more, the collection is _non-empty_. Defaults to `0`.

### Maximum Cardinality

Type: [Integer][int], optional. The maximum number of elements the collection may contain. When unspecified, the collection is unbounded.

## Operations

### Size [Operation](../concepts/operation.md)

_[Required][req]._ Returns the number of elements in the collection.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| []         | 0      |
| [1]        | 1      |
| [1, 2, 3]  | 3      |
| [1, 1, 2]  | 3      |

### Is Empty [Operation](../concepts/operation.md)

_[Derived][der]._ Returns [Boolean][bool] `true` if the collection contains no elements. Defined as [Size](#size-operation) equal to zero.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| []         | true   |
| [1]        | false  |
| [1, 2, 3]  | false  |

### Contains [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: element type implements [Equality][eq]. Returns [Boolean][bool] `true` if any element in the collection compares [Equal][eq-equal] to the given value.

#### Test cases

| Collection | Value | Output |
| ---------- | ----- | ------ |
| [1, 2, 3]  | 2     | true   |
| [1, 2, 3]  | 4     | false  |
| []         | 1     | false  |
| [1, 1, 2]  | 1     | true   |

### Map [Operation](../concepts/operation.md)

_[Required][req]._ Returns a new collection of the same multiplicity and iteration order containing the result of applying a given function to each element. The output cardinality equals the input cardinality.

#### Test cases

| Collection | Function         | Output    |
| ---------- | ---------------- | --------- |
| [1, 2, 3]  | add 1 to element | [2, 3, 4] |
| []         | add 1 to element | []        |
| [2, 2, 3]  | add 1 to element | [3, 3, 4] |

### Filter [Operation](../concepts/operation.md)

_[Required][req]._ Returns a new collection containing only the elements for which a given predicate returns [Boolean][bool] `true`, preserving multiplicity and iteration order.

#### Test cases

| Collection | Predicate              | Output |
| ---------- | ---------------------- | ------ |
| [1, 2, 3]  | element greater than 1 | [2, 3] |
| [1, 2, 3]  | element greater than 5 | []     |
| []         | any element            | []     |
| [1, 1, 2]  | element less than 2    | [1, 1] |

### Distinct [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: element type implements [Equality][eq]. Returns a new collection with duplicates removed so that no two elements compare [Equal][eq-equal]. The resulting collection has multiplicity **unique**.

When iteration order is **insertion** or **key**, the first occurrence of each distinct value is retained and relative order is preserved (stable). When iteration order is **none**, the relative order of retained elements is unspecified.

#### Test cases

| Collection   | Output    |
| ------------ | --------- |
| [1, 2, 1, 3] | [1, 2, 3] |
| [1, 1, 1]    | [1]       |
| []           | []        |
| [3, 1, 2, 1] | [3, 1, 2] |

### Union [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: element type implements [Equality][eq]. Returns a collection containing all elements from either collection.

- For **unique** collections: each distinct element appears exactly once (set union).
- For **multi** collections: each element appears as many times as the sum of its occurrences across both collections (bag union).

#### Test cases

| Collection A | Collection B | Output (unique) |
| ------------ | ------------ | --------------- |
| [1, 2]       | [2, 3]       | [1, 2, 3]       |
| [1, 2]       | []           | [1, 2]          |
| []           | [3]          | [3]             |
| []           | []           | []              |

### Intersect [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: element type implements [Equality][eq]. Returns a collection containing only elements that appear in both collections.

- For **unique** collections: each distinct common element appears exactly once (set intersection).
- For **multi** collections: each element appears as many times as the minimum of its occurrences in each collection (bag intersection).

#### Test cases

| Collection A | Collection B | Output (unique) |
| ------------ | ------------ | --------------- |
| [1, 2, 3]    | [2, 3, 4]    | [2, 3]          |
| [1, 2]       | [3, 4]       | []              |
| []           | [1]          | []              |
| [1, 2]       | []           | []              |

### Difference [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: element type implements [Equality][eq]. Returns a collection containing elements from the first collection that do not appear in the second.

- For **unique** collections: each element of the first that is absent from the second appears exactly once (set difference).
- For **multi** collections: the occurrence count of each element is reduced by its occurrence count in the second collection, with a floor of zero (bag difference).

#### Test cases

| Collection A | Collection B | Output (unique) |
| ------------ | ------------ | --------------- |
| [1, 2, 3]    | [2, 3]       | [1]             |
| [1, 2]       | [3, 4]       | [1, 2]          |
| []           | [1]          | []              |
| [1, 2, 3]    | []           | [1, 2, 3]       |

### Sort By [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: a key function and a [Compare][compare] expression over the key type are provided. Returns a new collection with elements ordered by the key in ascending order. The resulting collection has iteration order **key**. Tie-breaking is stable: elements with equal keys retain their relative input order.

#### Test cases

| Collection     | Key function            | Output         |
| -------------- | ----------------------- | -------------- |
| [3, 1, 2]      | element itself          | [1, 2, 3]      |
| [2, 2, 1]      | element itself          | [1, 2, 2]      |
| []             | element itself          | []             |
| [(b,1), (a,2)] | first component of pair | [(a,2), (b,1)] |

### Then By [Operation](../concepts/operation.md)

_[Derived][der]._ Precondition: a preceding [Sort By](#sort-by-operation) or Then By has established a primary key ordering; a secondary key function and [Compare][compare] expression over the secondary key type are provided. Returns a new collection where elements with equal primary keys are further ordered by the secondary key. Tie-breaking on the secondary key is stable. Defined in terms of [Sort By](#sort-by-operation) applied to a composite key that lexicographically combines the primary and secondary keys.

#### Test cases

| Collection            | Primary key             | Secondary key            | Output                |
| --------------------- | ----------------------- | ------------------------ | --------------------- |
| [(a,2), (a,1), (b,1)] | first component of pair | second component of pair | [(a,1), (a,2), (b,1)] |
| [(b,2), (a,1), (a,2)] | first component of pair | second component of pair | [(a,1), (a,2), (b,2)] |

### Min [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: element type implements [Ordering][ord]; minimum cardinality ≥ 1. Returns the smallest element according to [Compare][compare]. If multiple elements are [Equal][or-equal], any one of them may be returned.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| [3, 1, 2]  | 1      |
| [5]        | 5      |
| [1, 1, 2]  | 1      |

### Max [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: element type implements [Ordering][ord]; minimum cardinality ≥ 1. Returns the largest element according to [Compare][compare]. If multiple elements are [Equal][or-equal], any one of them may be returned.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| [3, 1, 2]  | 3      |
| [5]        | 5      |
| [1, 2, 2]  | 2      |

### Min Or None [Operation](../concepts/operation.md)

_[Derived][der]._ Precondition: element type implements [Ordering][ord]. Returns the smallest element if the collection is non-empty, or an absent value otherwise. Defined in terms of [Is Empty](#is-empty-operation) and [Min](#min-operation).

#### Test cases

| Collection | Output |
| ---------- | ------ |
| [3, 1, 2]  | 1      |
| [5]        | 5      |
| []         | none   |

### Max Or None [Operation](../concepts/operation.md)

_[Derived][der]._ Precondition: element type implements [Ordering][ord]. Returns the largest element if the collection is non-empty, or an absent value otherwise. Defined in terms of [Is Empty](#is-empty-operation) and [Max](#max-operation).

#### Test cases

| Collection | Output |
| ---------- | ------ |
| [3, 1, 2]  | 3      |
| [5]        | 5      |
| []         | none   |

### Reduce [Operation](../concepts/operation.md)

_[Required][req]._ Precondition: minimum cardinality ≥ 1. Combines all elements using a binary associative function without an initial accumulator, returning a single value of the same type.

#### Test cases

| Collection | Function          | Output |
| ---------- | ----------------- | ------ |
| [1, 2, 3]  | sum of two values | 6      |
| [5]        | sum of two values | 5      |
| [2, 3, 4]  | max of two values | 4      |

### Reduce Or None [Operation](../concepts/operation.md)

_[Derived][der]._ Like [Reduce](#reduce-operation) but returns an absent value when the collection is empty. Defined in terms of [Is Empty](#is-empty-operation) and [Reduce](#reduce-operation).

#### Test cases

| Collection | Function          | Output |
| ---------- | ----------------- | ------ |
| [1, 2, 3]  | sum of two values | 6      |
| [5]        | sum of two values | 5      |
| []         | sum of two values | none   |

### Sum [Operation](../concepts/operation.md)

_[Derived][der]._ Precondition: element type implements [Number][num]. Returns the total of all elements. Defined as [Reduce](#reduce-operation) with [Addition](number.md#addition-operation) when the collection is non-empty, and zero otherwise.

#### Test cases

| Collection | Output |
| ---------- | ------ |
| [1, 2, 3]  | 6      |
| [5]        | 5      |
| []         | 0      |
| [2, 2, 2]  | 6      |

### Average [Operation](../concepts/operation.md)

_[Derived][der]._ Precondition: element type implements [Number][num]; minimum cardinality ≥ 1. Returns the arithmetic mean of all elements. Defined as [Sum](#sum-operation) divided by [Size](#size-operation).

#### Test cases

| Collection | Output |
| ---------- | ------ |
| [1, 2, 3]  | 2      |
| [2, 4]     | 3      |
| [5]        | 5      |

## [Type Class Instances](../concepts/type.md#type-class-instances)

Collection does not itself implement a [type class](../concepts/type-class.md). The applicability of individual operations depends on the element type's type class instances and the collection's [attribute](../concepts/attribute.md) values, as stated in each operation's preconditions.

[bool]: boolean.md
[col-iter]: collection-iteration-order.md
[col-mult]: collection-multiplicity.md
[compare]: ordering.md#compare-operation
[der]: ../concepts/operation.md#derived
[eq]: equality.md
[eq-equal]: equality.md#equal-operation
[int]: integer.md
[num]: number.md
[or-equal]: ordering-relation.md#equal
[ord]: ordering.md
[req]: ../concepts/operation.md#required
