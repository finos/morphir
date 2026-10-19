# Bounded typed-value admission

`finos/morphir-conceptual/validation/admission` checks a candidate typed
value against a declared type under the versioned fixture profile
`morphir-contracts/0.1.0-draft.1` fixed by the C1 contract interfaces
(morphir-ukvn.7.10.1). Constructed fixtures are the inputs until production
integrations arrive; no native IR type is adopted here — U3 joins the native
representation later.

`admit(env, ty, value, limits~)` returns one `Outcome`:

| Outcome | Meaning |
| --- | --- |
| `Valid` | The value matches the type and every refinement on its path. |
| `Invalid(diagnostics)` | The value fails its type or a refinement, names an unknown constructor, breaks record shape, duplicates a set element or dict key, matches more than one union member (`contracts.ambiguous_value`), uses a raw value where an opaque construction is required, or reaches an alias cycle. Each diagnostic carries a `contracts.*` code and a JSON-pointer-style path. |
| `Unsupported(diagnostic)` | The check itself is outside the bounded profile: function or explicitly unsupported types, unknown type names, unbound type variables, unrecognized refinement names, an unsupported union member, or a foreign fixture profile. |
| `Exhausted(DepthLimit \| NodeLimit \| IntDigitLimit)` | A budget ran out. Exhaustion is an execution-error detail in the C1 outcome set and never reports `Valid`. |

Supported types: `Bool`, exact arbitrary-precision `Int` (decimal lexemes,
never routed through a machine or JS number), `String`, type variables,
named references, tuples of any arity, records, untagged unions, lists,
sets and dicts. Declarations are transparent aliases (structural, with an
optional refinement), opaque aliases (representation hidden; only a
constructed value for the same name is admitted, with any refinement
checked on the constructed payload) and custom types with finitely many
named constructors. Generic declarations instantiate at concrete argument
types. The budget record is the C1 admission-phase record: `Limits`
defaults to depth 64, 10,000 visited value nodes and 256 decimal digits
per exact integer, and using exactly a limit is allowed. Union trials
share the caller's value-node budget, so work spent on failed members
still counts. Capability (unsupported types, unknown names, unbound
variables, unknown refinements) is decided by a type inventory pass
before any value is admitted; that pass and generic substitution do
type work against their own counter bounded by the same node limit,
never against the value-node allowance.

Transparent recursion must pass through a value constructor, such as a list,
record or custom constructor, to be guarded. An unguarded alias cycle is
invalid even in an empty collection or an unused generic argument. Generic
arguments inherit guarding from the declaration body that uses them.
Type traversal also has an implementation depth cap of 128 and a cap of
256 simultaneously active checking calls across type and value moves.
Exceeding either safety cap reports `Exhausted(NodeLimit)` on every target.

Out of scope: predicate evaluation and contract sequencing (C3), raw
encoding validation (C6), native IR adoption and implementation bindings.
