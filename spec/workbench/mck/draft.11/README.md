# Selected Scheme witness corpus

This immutable exact `0.1.0-draft.11` kit contains 37 fixed cases for
`run-selected-scheme`. The [contract](../../draft.11/README.md) defines its narrow
selected-public-boundary and unused-declaration scope. A later exact kit qualifies
full runtime capability-check policy branch semantics; it does not add cases to this version.

All models, arguments and expected observations are complete inline values in
`cases.json`. Expected results were authored from the accepted requirements and
existing IR/value contracts before implementation comparison. They are never
captured from adapter output or regenerated from implementation behavior.

The complete v4 Library fixture owns `selected:main#answer`. Its supported entry
returns Int literal 42. The dormant unsupported declaration variants are a Hole,
IncompleteBody, unbound NativeBody and unbound ExternalBody. Strict omission and
explicit strict preserve the existing generator rejection codes. Explicit
permissive evaluates the selected supported entry without loading the dormant
declaration. JSON arguments `[]` and Ion text `$ion_1_0 [ ]` stay distinct inputs.

The controls cover:

- Missing/private selected entries, wrong arity and wrong tagged argument type.
- Empty List of function and Nothing of function, and an unselected function
  alternative inside a custom boundary. None waive the declared boundary.
- A complete public recursive tree returning Leaf(Int42), its unselected
  unsupported-constructor variant, missing custom references, private
  constructors, a generic alias and an alias cycle.
- Duplicate canonical constructor identities and duplicate source JSON members.
- Selected closure depth, constructor count and constructor arity bounds;
  dormant whole-source tree limits; tagged argument depth limits.
- Malformed whole model source and malformed/nonarray JSON or malformed Ion
  arguments. These remain domain decoder observations, distinct from malformed
  MCK infrastructure.

Every successful boundary expectation is independent of renderer manifests and
whole-library code generation. Refusal expectations retain their decode/plan
stage and stable original code. Current corpus cases establish no runtime branch,
terminal, worker, provider, UI, native, HTTP, or packaged-platform capability.
