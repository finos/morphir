# Rich conceptual records

`finos/morphir-conceptual/model` reads and preserves the complete Ion graph for
`morphir-conceptual/0.1.0-draft.1`, including its optional
`morphir-traits/0.1.0-draft.1` extension. Record versions match `0.1.0-draft.1`
exactly. It uses the existing `moonrockz/ion` value model and reuses the validated
identity/revision types from `conceptual/intent`; the bounded intent model remains
unchanged.

`Graph::decode(IonValue)` creates private record views. Accessors expose sources,
entities, relationships, capabilities, trait definitions and applications. Entity
kinds, resolved/unresolved references, trait targets, interpretation requirements,
multiplicity and provenance origins have distinct variants. `Record::field`,
`Entity::content`, `Entity::concern` and `Graph::to_ion` retain the remaining
content, including all five independent concerns and unknown descriptive fields.
No graph field is reconstructed from a smaller JSON representation.

Decoding checks required structural members, exact record/profile versions,
known record-member uniqueness, graph-wide record IDs, known variant boundaries
and the nested records used by inspection. Contract and claim subjects, declaration
parents and derived provenance inputs require resolved references. Digest claims
require `sha256` and 64 lowercase hexadecimal digits. Opaque ASTs, types and payloads remain
Ion values; their struct multiplicity, annotations, exact numbers, typed nulls
and symbol/string distinctions survive. Decode and accessors copy mutable Ion
containers and Blob/Clob bytes, so callers cannot mutate validated storage through
aliases, including bytes created through unsafe mutable reinterpretation. Standalone
decode checks depth 128 and 100,000 values before copying, including cyclic input.
Engine codecs additionally apply their existing transport budgets and symbol
catalog rules.

`Graph::inspect(inputs~)` reports structural reference failures or independent
representation gaps. `inputs` maps declared `inputId` values to explicit Graph
snapshots. Resolution traverses only declared, supplied exact snapshots, including
transitive dependencies. Each graph's references use its own closure; an ancestor's
extra inputs do not grant it access. Model trait targets use the same exact local
or declared dependency snapshots. Missing or mismatched resolved references are
invalid. Authored unresolved references remain gaps. Conflicting same-revision
snapshots are invalid, and closure traversal is bounded to 128 distinct snapshots.
Dependency diagnostics use `/inputs/<escaped-input-id>` prefixes.

Built-in entity trait targets check the referenced kind and declaration role;
unresolved targets check their claimed expected kind. Unknown targets, foreign
target profiles and module artifact targets retain their values and report gaps
for interpretation or artifact binding that this package does not implement.

Inspection includes source pin gaps, unresolved references, built-in relationship
signatures, formalization/example gaps, open domain aspects, implementation gaps,
projection gaps, unsupported critical/semantic facts, trait interpretation
mismatches and competing single-valued applications. Conflicts retain both
assertions and their provenance; inspection selects neither. `Inspected` reports
only these checks. It does not certify a complete M1/M2 validator, payload
assignability, binder/type correctness, evidence currency, source digest
verification, provider trust, target-profile semantics or successful execution.
Digest claims remain unverified: a source without a revision still reports
`conceptual.source_unpinned`. The original records remain available for those consumers.

`Graph::require_interpretation(Check | Execute | ValidateTraits)` always refuses:
this package has no semantic interpreter. It names a required semantic fact when
one is present. Unknown required semantics remain storable and inspectable with
gaps, independently of this refusal. No capability advertisement or stored evidence
is converted into new execution evidence.

The engine adapter supplies `IRUnit::with_conceptual_graph`,
`IRUnit::conceptual_graph` and `IRUnit::conceptual_specification`. See
[the data boundary](../../morphir-engine/data/README.md). MEP model transport,
provider publication, linked-metadata projection, source acquisition and expression
evaluation retain their existing owners; this package introduces no envelope,
transport tuple or compatibility runner.

[Fixture provenance and operation coverage](fixtures/README.md) identify the
independent upstream inputs and the bounded claims established by the tests.
