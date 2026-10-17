# Selected Scheme plan witness

Exact offline Workbench MCK `0.1.0-draft.11` adds the JSON-only operation
`run-selected-scheme` to the existing shared Rust runner and checker. Its complete
fixed inventory qualifies a narrow witness: validation of one selected public
boundary, evaluation beside unused unsupported declarations, and the required
structural, identity, type-closure, argument and budget rejection controls.
This is scoped capability verification evidence for this implementation and
witness, not formal proof of correctness for all programs or business outcomes.

This operation does not qualify unsupported operations in untaken or taken
branches, terminal inventories, jobs or workers, providers, host/native mappings,
UI capability advertisement, generated targets, or packaged platforms. The full
runtime capability-check policy semantics require a later exact kit and operation. Draft.11 is
not extended in place to acquire those claims. Historical MCK drafts.1 through
.10 and existing live profiles remain unchanged.

```sh
morphir mck workbench run --kit spec/workbench/mck/draft.11 \
  --adapter /path/to/selected-scheme-adapter --report report.json
morphir mck workbench check --kit spec/workbench/mck/draft.11 --report report.json
```

The adapter must use the real selected Scheme planner, its retained public
boundary context, actual captured policy accessor, evaluator, and captured-context
output validation. It must not fabricate a manifest, create an empty generated
library, decode expected results, or implement a second verdict engine. Runner
transcript replay tests infrastructure only.

## Exact negotiation and bounded inputs

The [schemas](schemas/) require suite `workbench`, exact version
`0.1.0-draft.11`, and formats `["json"]`. Operations are either exactly
`["run-selected-scheme"]` or `[]`. An empty claim produces a truthful MCK
`unsupported` record without executing the case. It does not mean a selected
operation ran and failed. Adjacent drafts, build suffixes, unsupported operations,
and Ion transport reject during negotiation.

Every case input is a closed object with:

| Member | Shape and bound |
| --- | --- |
| `model` | Complete immutable IR JSON source string, at most 262,144 Unicode code points |
| `entry` | Selected public entry identity, 1–512 Unicode code points |
| `inputs` | Exactly `format` and `source`; format is `json` or `ion-text`, source at most 16,384 Unicode code points |
| `runtime` | Exactly `"scheme"` |
| `admission` | Optional exact [selection](../admission/draft.1/README.md), with `profile`, `contractVersion`, and `policy` |

An omitted `admission` member means strict in this mapping. Explicit selection
uses profile `morphir/workbench/admission`, exact version `0.1.0-draft.1`, and
policy `strict` or `permissive`. Unknown profiles, versions, policies, runtimes,
fields and scalar kinds are invalid fixture infrastructure. Explicit permissive
never silently falls back. This explicit test-adapter mapping grants no public
runtime, provider, UI, HTTP or native capability.

The compact input is at most 491,520 encoded UTF-8 bytes. Tagged argument source
is one whole array in JSON, or list in Ion text, interpreted by the production
adapter through the existing tagged-value codecs. The shared Rust runner leaves
model and argument source text opaque, including malformed source used by fixed
negative cases. It never parses IR, links a production decoder/evaluator, or
accepts a caller-supplied public manifest.

Source imports retain the existing data limits: 4 MiB source bytes, depth 128,
and 100,000 data values, plus the original IR grammar, envelope and identity
checks. The tighter test-transport input bounds above apply first. Selected type
closure is bounded to depth 64 and 10,000 shared traversal nodes, 256 custom type
definitions, 256 constructors per definition, 64 inputs per constructor, and
1,024 members per record or tuple. Closure traversal includes every declared
alternative, including finite named recursive references. Empty containers,
Nothing, unselected constructors and later failure cannot waive closure checks.

Existing tagged-value limits remain: depth 64, 100,000 value nodes, integers of
at most 10,000 digits, bounded exact Float64 bits, UTF-16 code units, Decimal
precision, identities and collection limits. Runtime evaluation keeps 1,000,000
steps, depth 128 and 100,000 frames; those limits are not increased by this
witness. Dormant source still counts toward global structural limits.
The published value codec also retains its Ion parser container-depth limit of
128. A tagged JSON value can consume multiple parser levels per semantic value,
so this representation limit may be reached first. Either resource refusal is
observed as `execution.value_limit`, rather than malformed argument syntax.
The initial MoonBit selected planner accepts Library distributions only.

## Closed observations and comparison

Every request with valid fixture infrastructure yields `{"status":"ok","value":...}`. The value is one
of three closed shapes, always recording effective `policy` and runtime `scheme`:

- Success has a nonempty `boundary` string, exactly one tagged item in `values`,
  and `failure: null`. Policy comes from the actual immutable Scheme plan.
- Decode or plan refusal has `boundary: null`, `values: null`, and failure
  `{stage: "decode" | "plan", code: ...}`.
- Evaluate refusal retains the actual validated `boundary` string, has
  `values: null`, and failure `{stage: "evaluate", code: ...}`.

Failure codes contain 1–128 UTF-16 units after validation and are stable codes
only. Context following a colon, source text, paths, stack traces and private
error details are omitted. Domain refusals are completed observations and may
match fixed expected refusals. A `status: "invalid"` envelope, malformed scalar
or contradictory success/refusal shape is an infrastructure exchange error.
This narrow refusal projection does not claim terminal-outcome conformance.

`boundary` is the fresh actual `SchemePlan.boundary_json()` object serialized as
canonical JSON text, with recursively sorted object keys. Its underlying shape
is `{entries:[{name,inputs,output}],definitions:[...]}`. Entry, constructor and
definition arrays have deterministic UTF-16 lexical identity order. Only the
selected public context and its complete custom-type closure are retained.
The runner compares boundary text exactly and does not decode it or recreate
selected-boundary validation. Returned tagged values use the existing structural
Workbench output projection and its bounded canonical-value checks. Record
fields compare by name through that existing projection; list/tuple/call order
and opaque strings remain significant.

Each projection is at most 1 MiB. The existing 16 MiB aggregate observation,
32 MiB report, bounded transport and session limits apply. Literal schemas and
duplicate JSON member checks run before typed conversion, including private
JSON library marker objects. A well-formed mismatch is a compatibility `fail`;
an invalid observation is an infrastructure `error`. Missing capability is
`unsupported` and never becomes a domain failure.

The checker reloads complete original corpus bytes and recomputes hashes,
ordered case/operation/format inventory, observation validity, verdicts and
qualification. It accepts truthful unqualified evidence while refusing forged
policy, boundary, value, verdict, capability, inventory or corpus identity.
No case ID or expected result reaches the adapter.

## Fixed inventory and evidence limits

The [37-case corpus](../mck/draft.11/README.md) contains complete inline IR and
arguments, with independent expected policy, boundary and returned values or
stable refusal codes. It includes omitted/explicit strict controls, permissive
unused Hole/Incomplete/Native/External declarations, JSON/Ion arguments, public
entry authorization, arity/type checks, complete recursive/custom boundary
closure, duplicate identities, and source/input/selected-closure bounds.

Capability validation checks the chosen runtime/provider against the requirements
of a particular run, selected function and model revision under policy. Ordinary source, type,
argument, output, receipt and authority checks remain validation. The historical
`admission` member, profile ID and linked directory keep their names for
compatibility; this terminology update changes no schema or policy semantics.

A green report witnesses this exact inventory and the adapter implementation
named by its capabilities. It is not permission to advertise full permissive
runtime support. Full branch evaluation order, reached-unsupported diagnostics,
native binding/fallback behavior, terminal inventory/cleanup, immutable jobs,
workers, host/native negotiation and UI adoption require their separate complete
contracts and qualification gates.
