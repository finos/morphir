---
id: domain-modeling
title: Domain modeling
sidebar_position: 5
---

# Domain modeling

Morphir code expresses domain rules in types. At public APIs, domain boundaries,
and persistent state, prefer designs where invalid states cannot be represented.
Types should tell readers which values and transitions the domain permits.

## Represent states explicitly

Use algebraic data types, tagged unions, sealed variants, or type-state to model
distinct cases. Each case should carry only the data that is valid for that case.
Do not encode mutually exclusive states as combinations of boolean flags or
optional fields. Match every case exhaustively so that adding a state requires
callers to decide how to handle it.

Before adding primitive parameters, boolean state flags, or free-form strings,
inspect the existing domain vocabulary. Extend an established domain type when
the new concept belongs there. Tests should cover validation at system boundaries
and every allowed or rejected state transition.

## Give domain values distinct types

Avoid primitive obsession and stringly typed domain APIs. Two values that share
a machine representation can still mean different things. Represent those
distinctions with newtypes, opaque types, branded types, or validated wrappers.
A type alias can document a distinction, but it is insufficient when values remain
interchangeable and accidental interchange would violate a domain rule.

Put validation in smart constructors and keep unchecked construction private.
This makes the validated type evidence that its invariants hold. Do not wrap every
scalar, however. Introduce a domain type only when it captures a real distinction
or invariant.

Primitive representations are appropriate at I/O boundaries. Parse and validate
inputs that represent constrained domain concepts, then convert them to domain
types. Ordinary internal values may remain primitive when they carry no domain
distinction or invariant. Keep protocol and wire-format compatibility separate
from internal domain representation.

## Performance-sensitive internals

A performance-sensitive internal path may use a compact primitive representation
only when profiling or a reproducible benchmark demonstrates the need. Bit flags,
packed values, and indices are acceptable when that evidence shows a material
benefit. Prefer zero-cost typed abstractions when they provide the same result.

Keep an exceptional representation private and narrowly contained. Named helpers
must own its encoding and invariants. Conversion tests must prove the mapping
between compact and domain representations. Boundary tests may exercise those
conversions only if they cover every conversion path. Document the benchmark and
the representation contract near the implementation. The compact form must not
leak into public APIs.

Readability and maintainability remain mandatory. A packed representation that
readers cannot verify is not acceptable, and unrelated boolean flags do not become
a valid optimization merely because they occupy fewer bits.

## Review checklist

When reviewing domain code, check for:

- fields whose values can contradict each other;
- primitive parameters that are easy to confuse or swap;
- free-form strings where the domain has a constrained vocabulary;
- public constructors or mutation paths that bypass invariants;
- catch-all or default matches that hide non-exhaustive state handling;
- performance exceptions without profiling or reproducible benchmark evidence,
  narrow containment, named helpers, conversion tests, and a documented contract.
