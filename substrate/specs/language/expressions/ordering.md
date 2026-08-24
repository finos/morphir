# Ordering [Type Class](../concepts/type-class.md)

## Summary

The Ordering type class defines operations for comparing values to
determine their relative order. It extends Equality: any type with an
ordering also supports equality comparison. Operations: **Compare**
(required, returns an Ordering Relation; all other ordering operations
derive from it), and the derived **Less Than**, **Greater Than**,
**Less Than or Equal**, **Greater Than or Equal**. Relational
operations return Boolean.

## Operations

Relational operations return a [Boolean][bool] value.

### Compare [Operation](../concepts/operation.md)

_[Required][req]._ Returns an [Ordering Relation][or] representing the relationship between the first and second value. All other ordering operations are derived from this.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Ordering Relation][or]

### Less Than [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is [Less][or-less].

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Boolean][bool]

### Greater Than [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is [Greater][or-greater].

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Boolean][bool]

### Less Than or Equal [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is not [Greater][or-greater].

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Boolean][bool]

### Greater Than or Equal [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is not [Less][or-less].

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Boolean][bool]

Test cases for each instance live under the implementing type's
[Type Class Instances](../concepts/datatype.md#type-class-instances) section.

[bool]: boolean.md
[der]: ../concepts/operation.md#derived
[eq]: equality.md
[instance]: ../concepts/type-class.md#type-instance
[or]: ordering-relation.md
[or-equal]: ordering-relation.md#equal
[or-greater]: ordering-relation.md#greater
[or-less]: ordering-relation.md#less
[req]: ../concepts/operation.md#required
[tc]: ../concepts/test-case.md
