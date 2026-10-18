# Selected Scheme witness

This explicit offline adapter implements only Workbench MCK exact
`0.1.0-draft.11`, operation `run-selected-scheme`, with JSON transport. It is a
bounded witness for selected public boundary planning and execution beside unused
unsupported declarations. The historical Workbench MCK adapter and application,
provider, native and HTTP offers remain unchanged.

The adapter imports the complete fixture model through the production registry,
constructs a typed invocation, calls the actual immutable `SchemePlan`, observes
its retained policy and fresh boundary projection, then evaluates and validates
actual returned values. It never receives expected results or computes verdicts.
The independent shared Rust runner owns fixtures, comparisons, corpus hashes and
report checking. This supplies scoped capability verification evidence for
this witness, rather than a proof for all programs or business outcomes.

Model source and JSON/Ion-text arguments remain separate bounded source strings.
Planning retains mandatory source integrity, public visibility, complete selected
input/output type closure, argument and resource checks. The boundary observation
is canonical JSON text, with lexical key ordering. Decode, plan and evaluate
refusals are bounded observations, not transport errors or missing capabilities.

Argument decoding retains the published value codec's semantic depth limit of
64 and its Ion parser's container depth limit of 128. Tagged JSON containers can
consume multiple parser levels per value, so that representation limit may be
reached first. Both are resource refusals, distinct from malformed argument syntax.
The selected Scheme planner currently accepts Library distributions only.

This witness does not qualify untaken/reached expression semantics, complete
capability-check policy conformance, asynchronous execution retention, terminal inventory, UI support,
generated targets or a packaged platform. A later exact kit qualifies those
additional semantics without changing this frozen inventory. The application
continues to use strict capability checks until its separately tracked integration gates
are complete.

Build the explicit process with `moon build --target js` or
`moon build --target native`; its entry points are `mck/selected/js` and
`mck/selected/native`. Run and independently check it with the upstream kit at
`finos/morphir/spec/workbench/mck/draft.11`.
