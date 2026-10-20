# Workbench codec compatibility slice

Contract version: `0.1.0-draft.1`. The shared Rust `morphir mck` runner owns this
corpus, transport validation and verdict calculation. Implementations provide an
explicit adapter. The runner never loads an implementation's codec to calculate
expected values, and never sends case IDs or expectations to the adapter.

`cases.json` contains 64 independently authored inputs and expected observations.
It covers JSON and Ion text decoding into the typed JSON projection, including
exact integers above JavaScript's safe range, Decimal validation and retained scale,
Float64 signed zero/NaN payloads/infinity/subnormals, UTF-16 surrogate units,
records, containers, constructor identities, Maybe, Result and top-level SDK model
errors. Rejection cases cover numeric bounds, annotations, duplicate fields,
unknown fields, invalid model-error codes and depth limits.

This qualifies the listed codec projections. It does not establish declared-type
argument validation, constructor registry membership, evaluation, SDK comparison,
Ion binary decoding or reverse encoding. The generic MoonBit codec accepts model
errors before declared-type validation; these fixtures exercise only top-level
outcome errors. Nested errors and model errors used as arguments require the
execution engine's separate type validation. Rust and TypeScript adapters remain
pending. These test capabilities do not advertise connected-host RPC support.

## Adapter protocol

Adapters read one UTF-8 JSON object per line on stdin and write one response per
request on stdout. Diagnostics use stderr. The shared transport supplies a
positive correlation `id`; adapters echo it. Unknown and duplicate members are
rejected. Draft support is exact, with no fallback to a nearby draft.

The first request negotiates this test contract:

```json
{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.1"}
```

```json
{"id":1,"suite":"workbench","contractVersion":"0.1.0-draft.1","binding":"morphir-moonbit","language":"moonbit","operations":["decode-value"],"formats":["json","ion-text"]}
```

Operation and format arrays contain unique supported claims. Empty arrays are
allowed and produce unsupported cases. A missing claim skips the case; it cannot
qualify the full corpus. An unknown claim or malformed negotiation fails validation.

The runner then sends inputs without goldens:

```json
{"id":2,"op":"decode-value","suite":"workbench","contractVersion":"0.1.0-draft.1","format":"ion-text","input":"9007199254740993"}
```

```json
{"id":2,"status":"ok","value":{"type":"int","value":"9007199254740993"}}
```

A rejected value returns `{"id":2,"status":"invalid","code":"execution.float_bits"}`.
The observation schema permits a nonempty code of at most 128 UTF-16 units.
MoonBit maps its execution codec's diagnostic to the stable code before the
first colon, omitting input names and paths from the bounded code. A malformed Ion text
document uses `workbench.invalid_ion`. Adapter/runtime failures prevent
qualification; they do not become model errors.

Finally, the transport sends `{"id":N,"op":"exit"}`. The adapter exits
successfully and closes stdout without a response. An extra line, nonzero exit,
timeout or failed cleanup prevents qualification even if every case passed.
The shared transport bounds messages and deadlines and terminates the process
tree on failure or interruption.
Its duplicate-aware JSON validation has a separate limit of 127 nested containers.
That framing bound also applies to corpus and report documents; it can be stricter
than the value-node depth limit for records with deeply nested field wrappers.

<a id="corpus-and-report-admission"></a>

## Corpus and report validation

The offline corpus directory must be explicit and contain a regular `cases.json`
file of at most 16 MiB. The document is closed, duplicate JSON members are rejected,
and there must be 1 to 1,024 cases with distinct nonempty IDs of at most 128 UTF-16
units. Each encoded JSON input or UTF-8 Ion text input is at most 1 MiB.

Expected and observed successful projections must pass the parent-owned outcome
schema and output limits. Integer coefficients and Float64 bit strings use their
canonical output spellings. Record fields compare by name recursively and must
be distinct; list and tuple order remains significant. Decimal projection retains
the validated coefficient and exponent, so `1200` at exponent `-3` remains that
pair. This is a projection golden, not normalized Decimal SDK comparison.

Each output projection is at most 1 MiB, with an aggregate budget of 100,000
nodes/code units and depth 64. Total retained compact observations are at most
16 MiB. An overflow stops further requests and produces failure evidence.

Reports use compact JSON and `formatVersion: "0.1.0-draft.1"`, record the SHA-256 of the exact corpus
bytes, validated capability documents, every case observation/verdict, failures and the
computed `qualified` flag. Reading a saved report is bounded at 32 MiB. The check
command reloads the corpus, verifies its digest and ordered inventory, revalidates
capability documents and observations, and recomputes every verdict and qualification.
Changing a claimed result, dropping an observation or forging `qualified` fails.
A well-formed unqualified report remains failure evidence and returns exit code 1.
Checking is evidence consistency validation, not proof of who produced a report.

```sh
cargo build --locked -p morphir
target/debug/morphir --no-banner mck workbench run \
  --kit spec/workbench/mck --adapter /path/to/adapter \
  --report .dev/workbench-report.json
target/debug/morphir --no-banner mck workbench check \
  --kit spec/workbench/mck --report .dev/workbench-report.json
```

`--adapter-arg` repeats for arguments passed directly without a shell. For a Node
adapter, select `--adapter node --adapter-arg /path/to/adapter.js`. No default
embedded IR kit or implicit adapter is selected. Usage errors return 2;
qualification/operational failures return 1; qualified runs/checks return 0.

Run `mise run workbench:schema-check` for schemas, structural fixtures and corpus
structure, and `cargo test --locked -p morphir-mck workbench` plus
`cargo test --locked -p morphir --test mck_workbench` for the engine/CLI boundaries.
The MoonBit repository owns its adapter and the opt-in `test:workbench-mck` gate,
which requires explicitly selected parent runner/corpus paths and exercises Node
and native debug/release lanes. The pure protocol component runs on JS, native,
Wasm and Wasm GC; browser/Wasm process adapters are not claimed by that gate.

## Local model inspection and originals

Exact offline [draft.29](draft.29/README.md) adds `inspect-model` and
`export-model-original` for explicit local providers and JSON/YAML/Ion model bytes.
The parent owns fixed semantic and original-byte expectations; it never links a
model codec. Its positive controls are checker infrastructure evidence only.
Historical exact kits and connected model-service ownership remain unchanged.

## Connected model originals allocation preparation

The parent owns the Workbench MCK draft registry. The next connected allocation
is prepared separately from the offline local model kit:

| Exact MCK contract | Operations | Current scope |
| --- | --- | --- |
| `0.1.0-draft.29` | `inspect-model`, `export-model-original` | Existing offline local model kit |
| `0.1.0-draft.30` | `model-originals-server`, `model-originals-client` | [Unpublished capability allocation preparation](../draft.30/README.html); remaining schemas, corpus and actual adapters pending |

Draft.30 requires a nonempty unique subset of its two operations and exactly
JSON framing. Its binding and language identities each contain 1 to 128 decoded
UTF-8 bytes. The older drafts retain their existing identity and empty-claim
rules. The connected service wire profile remains `0.1.0-draft.1`.

This preparation does not qualify a role or publish a complete runnable kit.
The full objective remains all original 151 cases and 175 role executions with
independent strong expectations, complete source lineage and genuine producer
evidence. The existing partial candidate remains explicitly unqualified.
