# Runtime capability policy verification

Exact offline Workbench MCK `0.1.0-draft.12` defines the JSON-only operation
`run-capability-policy` in the shared Rust runner and independent checker. The
[fixed corpus](../mck/draft.12/README.md) checks the bounded Scheme execution
policy and completion validation against a real immutable selected context.
Earlier drafts, corpora and public jobs/native/HTTP protocol mappings are frozen.
The existing `admission` selection member and `morphir/workbench/admission`
profile keep their compatibility spelling; human-facing terminology is runtime
capabilities and capability validation.

This is scoped verification evidence, not formal proof, business-rule validation,
or authority to advertise provider, job, UI, generated-target or packaged-platform
support. The actual-production path and supplied-evidence path remain explicit:

| Input | Observation mode | Evidence established |
| --- | --- | --- |
| No `completion` | `execute` | The real Scheme plan prepares and evaluates submitted calls, constructs typed terminals and validates publication against its captured boundary. |
| `completion` supplied | `validate-completion` | The real Scheme plan validates supplied terminal evidence against its captured boundary and invocation context without executing the selected source. This does not prove the producer ran it, cancelled it or cleaned up. |

A test adapter must call the production selected planner, retain its boundary,
policy and submitted calls, and use its policy-aware execution or completion
validation API. It must not fabricate a public manifest, dispatch by case ID,
read expectations, infer a verdict or ignore the frozen whole-manifest validator's
rejection. The shared runner sends only input, operation, format and exact version.

## Closed negotiation and bounded input

Capabilities contain suite `workbench`, exact version `0.1.0-draft.12`, formats
`["json"]`, and operations exactly `["run-capability-policy"]` or `[]`. A missing
claim yields MCK `unsupported` without executing the case. Adjacent drafts,
build suffixes, extra operations and Ion transport reject. JSON transport can
carry either JSON or Ion *argument and completion source text*.

Every input is closed:

| Member | Shape |
| --- | --- |
| `model` | Original complete IR JSON source, at most 262,144 Unicode code points. |
| `calls` | One to 1,000 ordered objects, each exactly `id`, `entry`, `inputs`. IDs contain 1–128 Unicode code points; entry identities contain 1–512. Production invocation validation additionally enforces existing UTF-16 identity limits. |
| `inputs` | Exactly `format: "json" | "ion-text"` and `source`, at most 262,144 Unicode code points. Source is a whole tagged-argument array or Ion list. |
| `runtime` | Exactly `"scheme"`. |
| `extensions` | Required null or `{format:"ion-binary",bytes:[...]}` with 1–65,536 byte integers. Production invocation decoding validates the bytes. |
| `admission` | Optional exact policy [selection](../admission/draft.1/README.md). Omission resolves once to strict. |
| `completion` | Optional `{format,source}` using the same bounded source-text shape as `inputs`. A complete terminal envelope, not an implementation verdict. |

The compact entire input is at most 1 MiB. Literal schema validation and duplicate
member rejection precede typed infrastructure conversion, including rejection of
JSON-library private marker objects. The runner leaves model, argument and
completion source text opaque, including deliberately malformed negative cases.
It does not parse IR or link a production evaluator or boundary decoder.

The production adapter preflights JSON argument and completion source with a
100,000-node and 1,048,576 decoded-string-unit parser budget, depth 512. Parser
resource exhaustion maps to `execution.value_limit` before tagged-value checks.
An integer source string longer than 10,000 characters uses the existing
`execution.invalid_integer` parser diagnostic; `execution.integer_limit` is the
separate validation diagnostic for an already constructed oversized integer.

All production source grammar, envelope, identity, declaration and data limits
remain mandatory. Selected boundary validation includes the complete input/output
custom-type closure and every constructor alternative before either execution or
completion validation. Unused source still consumes structural budgets.
Existing limits remain: global 4 MiB source, depth 128, 100,000 data nodes;
selected type closure depth 64, 10,000 nodes, 256 custom definitions, 256
constructors, 64 constructor inputs, 1,024 record/tuple members; tagged values
depth 64 and 100,000 value nodes, existing exact scalar and UTF-16 bounds; runtime
1,000,000 steps, depth 128 and 100,000 frames. File preparation and invocation
share an active runtime budget. Interpreter preparation separately bounds retained
constructor arity at 256. A retained oversized constructor rejects planning even
in an untaken branch; unrelated pruned constructor metadata does not.
These are interpreter fuel/depth/frame, source/value and encoded-byte budgets.
They do not impose a hard process-memory or CPU quota on opaque SDK internals.
For example, SDK String.repeat with a large count can allocate its result before
typed output validation, and interpreter fuel does not meter that internal loop.
A passing kit does not establish allocation bounds or cancellation responsiveness
inside every SDK operation. SDK resource hardening and worker process deadlines
or memory settings require separate qualification.

The published Ion parser's container-depth limit of 128 may apply before semantic
tagged-value depth. Resource refusal remains `execution.value_limit`.

## Actual execution semantics

Strict uses the existing whole-library generated-plan capability checks.
Permissive retains bounded original source and validated selected calls, prepares
selected definitions on demand, and places explicit unsupported-operation traps
at their original evaluation positions. It does not recover malformed IR,
ambiguous identities, source/parser failures, preparation resource limits or
unavailable authority as deferred operations.

Untaken conditionals and fully applied `and`/`or` retain their ordinary special
short-circuit behavior. First-class and partially applied Boolean procedures keep
ordinary eager application semantics. Operators, arguments and local value
let/letrec right-hand sides execute in their normal order. Uncalled function and
lambda bodies remain dormant. Constructor metadata preparation is bounded.
A reached explicit Hole or incomplete operation produces exactly a failed
terminal with stage `evaluate`, code `execution.unsupported_reached`, and bounded
message `Unsupported operation reached`; it never becomes returned data or an SDK
model error. Missing declared global references and unbound lexical variables
reject during selected preparation. Missing runtime bindings, budget exhaustion,
cancellation, malformed values and ordinary runtime errors retain their separate
terminal classes.

The production selected Scheme plan has no registered external native authority.
Native and external declarations therefore retain genuine missing-binding failure
when dereferenced; an untaken reference remains dormant. Direct backend tests may
qualify host-supplied registered native candidate/fallback order, target/arity
checks, no retry after invocation failure, and dormant fallback traps. That
backend-only evidence does not grant an external binding to this operation or
claim an authorized provider integration.

The execution API constructs one terminal per submitted call in submission order,
with an exact invocation-extension echo and independent cleanup field. Each
ordinary call failure remains a typed terminal so later calls retain their own
outcomes. Returned values are checked against the captured output types.
Scheme Decimal execution uses the existing SDK normalization law: trailing
coefficient zeros are removed and zero becomes coefficient 0/exponent 0. The
exact numeric value is preserved, without a scale/cohort guarantee. Supplied
completion validation performs no arithmetic and preserves accepted serialized
Decimal coefficient/exponent representation through the frozen value codec. Ordinary
typed `Result.Err` remains returned data; the enumerated SDK model errors and
cancellation retain their terminal variants. This bounded test mapping creates no
new provider authority or live cancellation/cleanup claim.

## Completion and closed observations

A domain observation is always `{"status":"ok","value":...}`. Its projection
contains exactly `mode`, `policy`, `runtime`, `boundary`, `outcomes`, `failure`:

- Successful execution or successful completion validation has a nonempty
  canonical captured `boundary`, a complete typed `outcomes` envelope and null
  `failure`. Failed/cancelled/model-error calls are valid typed terminal evidence.
- Decode or plan refusal has null `boundary` and `outcomes`, with failure exactly
  `{stage:"decode"|"plan",code:...}`.
- Publication or supplied-completion refusal has the real captured `boundary`,
  null `outcomes`, and failure exactly `{stage:"complete",code:...}`. It can occur
  in either mode; oversized actual outcomes must not be published as success.

The boundary is actual `SchemePlan.boundary_json()` serialized with recursively
sorted object keys and deterministic UTF-16 lexical declaration ordering. It is
opaque to the runner. Effective policy comes from the actual plan accessor.
Failure codes contain 1–128 UTF-16 units and omit detail after a colon. Fixed
bounded runtime messages contain no source, private path, stack trace or secret.

Outcomes reuse the [draft.5 terminal envelope and tagged-value codecs](../draft.5/README.md),
including exact scalar values, ordered call identities/count, opaque extension
bytes, enumerated model errors, primary/cleanup separation and unknown-field
rejection. Completion validation uses the plan's immutable validated public
boundary and captured calls, not the original permissively deferred declaration
graph passed back through frozen whole-manifest validation. Failed/cancelled
outcomes cannot waive boundary or argument validation. Completion decoding never
executes source. Every returned value still passes its captured output type.

A retained projection is at most 1 MiB. Actual serialized aggregate outcomes over
1 MiB refuse with `execution.output_limit`; the adapter's complete projection over
1 MiB refuses with `workbench.projection_limit`. The existing 16 MiB aggregate
observation, 32 MiB report, transport framing and session bounds apply unchanged.
Malformed/contradictory projections or a domain-invalid envelope are infrastructure
errors; well-formed mismatches are compatibility failures.

## Independent comparison and qualification

The shared runner checks literal observation shape, terminal variant/value bounds,
UTF-16 failure identities, duplicate terminal call IDs and stable structural
projection. It compares fixed expected policy, mode, boundary and typed outcomes.
Record fields compare by name through existing value projection; call order,
list/tuple order, opaque boundary text, extension byte order and primary/cleanup
causes remain significant.

The checker reloads exact original corpus bytes, recomputes SHA-256 and the full
ordered case/operation/format inventory, revalidates capabilities/observations,
and recomputes every verdict and qualification bit. It refuses forged mode,
policy, boundary, value, terminal inventory, outcome, corpus identity or verdict.
Infrastructure transcript replay tests the runner and checker only. Real adapters
must qualify against the same fixed corpus without receiving expectations.

```sh
morphir mck workbench run --kit spec/workbench/mck/draft.12 \
  --adapter /path/to/capability-policy-adapter --report report.json
morphir mck workbench check --kit spec/workbench/mck/draft.12 --report report.json
```

The fixed execution fixtures qualify Library distributions only. They provide no
execution evidence for other distribution kinds or source frontends.

A green exact report covers only this inventory and the actual named adapter,
implementation, runtime and execution context. Jobs/workers, retained policy
through claims and completion, host/native negotiation, UI adoption and each
packaged OS/architecture require their subsequent qualification gates. This kit
does not establish generated-artifact tree shaking.

SDK allocation and cancellation hardening is tracked separately as `morphir-be5t`, discovered from `morphir-etg2.16.2`.
