# Indexed-access scan controls

These small, independently authored controls advance task 8.1 of
[`add-bounded-model-access`](../../../openspec/changes/add-bounded-model-access/tasks.md).
They belong to the independent IDX-1 experiment. They do not extend the MCK kit,
its runner, the Orders corpus, or the contextual writer policy fixtures.

`queries.json` and `expected.json` were written before the scan implementation.
The expected sets were enumerated by reading the two physical documents:

| Query | Expected uses |
| --- | --- |
| `int` | A's output type, A's first list expression, B's output type |
| `add` | A's second list expression, B's body |
| `unused` | None. Alias `u` is declared but has no typed use. |
| `literal-only` | None. Its spelling occurs only inside a document literal. |

The document literal deliberately contains a `Reference` with an alias, a
`Type.Reference` with a fully spelled name, an undeclared `$name`, and an
`ExpressionBody.outputType`. Its JSON must stay opaque. A string literal also
contains the unused alias's full spelling. A shape search or recursive string
search would report false occurrences. B and A's `add` expression have no
corresponding table entry, defeating dictionary-only absence claims.

## Identity and supported scan scope

An occurrence identity is the ordered record
`{document, location, slot}`. Compare sets without depending on scan order.

* `document` is the exact case-sensitive, snapshot-relative physical path,
  including the extension, supplied by `controls.json`. It is not the fixture
  storage filename or a definition name. Identical locations in A and B stay
  distinct. Do not resolve this path through the current machine's filesystem.
* `location` is an RFC 6901 pointer relative to the unwrapped logical document.
  It names the enclosing type or value expression, independent of whether its
  reference is shorthand, explicit, or an alias. Object segments use escaped
  keys, never member ordinals. List segments use zero-based semantic indices.
* `slot` distinguishes `type-reference` and `value-reference`. FQName components
  are not separate occurrences. Definition names, table entries and literal
  contents are not reference uses.

Reordering JSON object members preserves identity. Reordering a list changes
logical locations. Parameter order must not be changed as an object-order test.
Neither source digests nor optimized byte ranges are part of semantic identity.
Task 8.2 must bind any offsets separately to exact source and context bytes.

The experiment's reusable typed walker is `tools/ir-reference-slots.ts`. It uses
the umbrella `check-ir-context` ordered JSON, alias-form and canonical spelling
API. The existing checker's recursive shape-based alias search cannot supply
this experiment's occurrences because it traverses opaque literals.
`tools/indexed-access-scan.ts` uses this typed walker for every query and reads
every complete source document. It supports only these v4 JSON value controls:
`ExpressionBody`, FQName reference types, reference expressions, lists, document
literals and string literals. Unsupported traversed node forms throw. It is
not a general reader, schema validator, bounded implementation, host, or MCK
checker. It makes no v3, YAML, general IR or resource qualification claim.
Context-last acceptance comes from retaining the complete small input, without
a streaming or bounded-memory claim.

## Replay and task 8.2

Run the light test from the umbrella root:

```powershell
bun test tools/indexed-access-scan.test.ts
```

Load each control's physical path/file pairs and every query. Compare each
observed set with the same `expected.json`, retaining typed slots and physical
identities. The four controls describe alternate revisions of the same physical
documents. Do not combine them into one snapshot. `contextual` and `expanded`
are the changed-encoding pair: their bytes differ while every semantic occurrence
is fixed. `context-last` and `reordered` also use the same expected sets.

Task 8.2 can consume these files directly for scan, dictionary-only and indexed
correctness observations. Do not regenerate expectations from any implementation.
Record exact bytes/digests per variant when testing stale offsets or recompaction.
A dictionary hit for `unused` and absence for fully spelled `add` are deliberately
insufficient evidence of occurrence sets. This baseline has no index, byte-range
optimization, resource benchmark, report format or performance result.
