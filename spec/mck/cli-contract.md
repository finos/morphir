# `morphir mck` CLI and engine contract

Status: **approved** in the IR-0 design review on 2026-09-18 ([#851](https://github.com/finos/morphir/issues/851)). Changes now need their own review.
Implemented: `check`, `kit status`, `kit vendor`, `kit update`, `run`, `coverage`, `schema check`, `report check`, `report render`, `package run` and `package inspect`. Parent IR gates use the Rust CLI. IR runs write consolidated `2.0.0-draft.1` reports; HTML is an optional offline view. Coverage and schema gates work from embedded, source and managed kits without external validators. Parent package integrity and resolution gates also use the native CLI after beta.3 qualification and adoption under #852. Frozen migration evidence remains; the replaced TypeScript runner is retired.

The IR commands retain their approved contract. The package addition under
[#852](https://github.com/finos/morphir/issues/852) uses its existing separate versioned protocols and reports.
Ownership is recorded in
[decision 0003](../../kb/bundles/morphir/morphir-package-system/decisions/0003-mck-tooling-lives-in-the-rust-morphir-cli.md).

Each behaviour below is marked **kept** (same as the TypeScript driver at the
[baseline](baseline/README.md)), **hardened** (a deliberate, stricter departure) or **new**.

## Components

| Component | Responsibility |
| --- | --- |
| `crates/morphir-mck` library | `kit` (parse, load, hash, manifest, acquisition), `transport` (adapter sessions), `ir` (execution, comparison, capabilities, vocabulary coverage), `schema` (offline authoring validation), `report` (draft schema reader, records, summary, baseline gate, HTML rendering). |
| `crates/morphir/src/commands/mck` | Argument validation, help, terminal output, exit status. No compatibility logic. |
| Adapter | Owned by each implementation. Decodes, encodes and handles document trees. |

Case interpretation and comparison are pure functions, callable without a subprocess or global
state. The runner checks an adapter's `formatVersions` with its own implementation of the support
tables in `docs/spec/ir/format-version.md`, tested against that page's conformance corpus; it never
borrows a binding's. The engine never links an implementation's IR codec. It compares canonical strings under the
existing rule: strip one trailing `\n` or `\r\n`, then compare line by line (kept).

Suite identity, contract version, case id and capability requirement are validated domain types,
not bare strings.

## Commands

```text
morphir mck check <dir> [--repo-root <dir>] [--json]
morphir mck run --adapter <exe> [--adapter-arg <arg>]... [--kit <dir>] [--repo-root <dir>]
                [--report <file>] [--strict] [--filter <regex>]
                [--timeout <ms>] [--session-timeout <ms>]
morphir mck coverage [--kit <dir>] [--repo-root <dir>]
morphir mck schema check [--kit <dir>] [--repo-root <dir>]
morphir mck report check <report.json> <allowed-failing.json> [--kit <dir>] [--repo-root <dir>]
                        [--filter <regex>]
morphir mck report render <report.json> --format html --output <report.html>
morphir mck package run --kit <dir> --adapter <exe> [--adapter-arg <arg>]...
                        [--contract <version>] [--report <file>]
                        [--timeout <ms>] [--session-timeout <ms>]
morphir mck package inspect --source <repository-root> --contract 0.1.0-draft.3
morphir mck kit status [--kit <dir>] [--json]
morphir mck kit vendor --source <source> [--revision <commit>] [--expect-digest <digest>] --dest <dir>
morphir mck kit update --kit <dir> [--source <source>] [--revision <commit>] [--expect-digest <digest>]
```

All listed commands are implemented. Release and consumer adoption remain a separate milestone.

For `kit vendor` and `kit update`, `--revision` is required with `--source github:finos/morphir` and
is usage error 2 with any other source. `kit update --revision <commit>` without `--source` updates a
snapshot whose manifest records the GitHub source, and is usage error 2 for any other snapshot. The
existing snapshot is verified before anything is downloaded.

`kit vendor`, `kit update` and the managed-kit rules are specified in [kit-manifest.md](kit-manifest.md).
`kit sync` is retired and has no successor: parent builds embed the corpus directly.

### Exit codes (kept)

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | A check, run, coverage or gate failure, or an operational error printed as `error: <message>` on stderr |
| 2 | Usage error. Printed on stderr. Nothing was executed and no report was written. |

Bare `morphir mck` and bare `morphir mck kit` print usage on stderr and exit 2 (kept).

### Output routing (kept)

stdout carries the command's result: the summary and non-pass lines, or JSON with `--json`.
Diagnostics, the capabilities header line, warnings and errors go to stderr. `--report` writes
tab-indented JSON with a trailing newline and creates parent directories.

### `check`

Validates a kit directory without an adapter. Output formats are kept:
`<file>:<line>: <message>` per error on stderr, then `N case(s) in M file(s), K error(s)` on
stdout. `--json` prints `{files, cases, errors}`. Exit 1 when any error exists.

The Gherkin scenario grammar, tags, case IDs, duplicate-id detection and external fixture
confinement are described in the [IR suite README](../ir/mck/README.md).
[baseline/kit-cases.json](baseline/kit-cases.json) preserves the retired Markdown parser's
reading of the historical corpus for migration evidence.

**Fixtures (hardened).** `check` also resolves every external text fixture against the repository root
(`--repo-root`, or the root inferred when the path ends in `spec/ir/mck`) and reports, at the
step's line, a fixture that is missing, escapes the root, is neither `.json` nor `.yaml`, is not
valid UTF-8, or starts with a byte-order mark. The TypeScript `check` never opened fixtures, so a
broken one surfaced only during `run`. A case file that is not valid UTF-8 is a kit error too,
where the old driver substituted U+FFFD. This is departure 12 in
[migration.md](migration.md#approved-departures-from-old-runner-behaviour).

A snapshot root, or a kit directory whose repository root holds `mck-kit.lock.json`, is a managed
snapshot. It is verified against its manifest before any case is read
([kit-manifest.md](kit-manifest.md#managed-and-raw-kits)); a failure is exit 1 naming each missing,
altered or extra file, and the kit is never read raw instead.

### `run`

**`--adapter` is required (hardened; maintainer decision 2026-09-18).** There is no implicit binding,
no adapter discovery and no fallback. Omitting it is usage error 2 before any testee starts or any
case executes, and no report is written. This holds when a Rust adapter is installed and on `PATH`;
a CLI regression test must prove it. `--adapter-arg` without `--adapter` is also usage error 2.

Kit selection is independent of adapter selection. Without `--kit` the embedded IR kit runs (kept).
With `--kit`, the checkout is used with the explicit `--repo-root`, or the inferred root three
levels up when the path ends in `spec/ir/mck` (kept). A supplied kit is never refreshed or replaced
by the embedded one. No command in this list except `kit vendor` and `kit update` touches the network.

`--strict` changes only the exit code: any `skipped` record also fails the run (kept). Capability
skips and pending reasons stay visible in the report either way.

**Empty selection (hardened).** A run that produces zero records exits 1 with
`error: no cases selected`. The TypeScript driver exits 0 and prints `0 pass, 0 fail, ...`. An
empty run is not a compatibility claim, so the Rust runner refuses to report it as success. The
report file is still written so the empty selection is inspectable.

### `--filter`

`--filter <regex>` selects cases. `--only` is accepted as an alias for migration.

| Aspect | Rule |
| --- | --- |
| Subject | The case id only, for example `types-0001`. Not the file or the heading title. (kept) |
| Anchoring | None implied. `types-` matches as a search; use `^types-0001$` for one case. (kept) |
| Flags | None. Matching is case-sensitive. (kept) |
| Kit-error records | Emitted regardless of the filter. (kept) |
| Syntax | The Rust [`regex`](https://docs.rs/regex/latest/regex/#syntax) crate syntax. (hardened) |
| Unsupported constructs | Look-around and backreferences do not exist in this syntax. A pattern using them is usage error 2, `invalid --filter regex: <message>`. It is never silently reinterpreted. (hardened) |

The TypeScript driver compiled the filter as a JavaScript `RegExp`. Every filter in the parent
repository, morphir-typescript and morphir-rust at the baseline is `^types-0001$` or `^types-`,
and no CI task passes one. Literals, anchors, character classes and alternation mean the same in
both syntaxes. Two differences are
documented for users instead of emulated: `\d`, `\w` and `\s` are Unicode-aware in Rust, which
cannot change a match against ASCII case ids, and named groups are written `(?P<name>...)` or
`(?<name>...)`. This is a CLI migration note. It does not change the IR protocol.

### `coverage` (kept, new data source)

Reports vocabulary entries with no case, one `formatGap` line per gap on stdout, exit 1 if any.
The vocabulary and node-alias catalog come from parent-owned data, `spec/mck/vocabulary.json`, with
a schema and a version. IR-3 creates it from `packages/ir/src/versions/v4/vocabulary.ts` and
`NODE_ALIASES` at the baseline pin and verifies its meaning against the specification. The runner
never derives the required vocabulary from a binding under test.

The heuristic is kept as is, with its known limits stated in `--help`: a pending case counts as
coverage, and members nested under an entry-point document are not seen.

### `schema check` (kept behaviour, new home)

Replaces `tools/validate-mck-fences.ts` and `tools/validate-mck-protocol.ts`. It validates every
canonical and accepted JSON fence against the published IR v4 schemas, validates
`protocol.example.json` message by message against `protocol.schema.json`, and enforces request and
response id pairing, including multiple alternative responses for one example request. Every message
must also validate at the root schema. Legacy warning spellings must fail schema validation except
the three retained documentation-wrapper cases. Unknown validation targets fail explicitly.

The same command validates all original schemas against their metaschemas and validates the report,
vocabulary and lock examples. The [gate inventory](schema-gates.md) records their entry points and
expected outcomes. The catalog reads only selected-kit bytes; it never resolves a reference through
the network or an arbitrary filesystem path. A missing input or malformed schema fails the command.

The repository retains vocabulary authoring checks in `mck:vocabulary-check`, separate from the installed CLI's offline gates. The parent owns protocol schemas; temporary TypeScript contract-copy drift checks are retired.

### `report check` (kept gate, hardened inventory, new home)

Replaces `tools/check-mck-report.ts` in the parent IR run gates. The shared native reader first
validates the consolidated draft schema, with unknown fields rejected and no remote reference
resolution. Kept: record shapes are validated; the set of failing case ids
must equal the `cases` array of the allowed-failing file in both directions, so a stale entry fails
as loudly as a new failure; at least one record must pass; every skip must carry a legitimate driver
reason: `pending`, or `node|version|layout|profile|path <x> not in capabilities`.

**Record inventory (hardened).** The old tool never compares the report with the kit, so a truncated
report, or one with duplicated passing records, is accepted. The Rust gate derives the expected
record identities from the independently loaded kit (`--kit`, default embedded) and the negotiated
capabilities in the report, and rejects missing, extra, duplicate and reordered records. It checks
the report's snapshot digest against that kit. A missing digest, failed negotiation or failed
adapter session cannot pass, even if the baseline allows every failing case. #849 requires the
inventory check; it is departure 11 in
[migration.md](migration.md#approved-departures-from-old-runner-behaviour).

Authoring errors in the kit prevent the existing snapshot algorithm from establishing complete
identity. Such runs remain useful diagnostic reports, but cannot pass this gate through an
allowed-failing entry. Their synthetic error records retain their order and multiplicity, including
multiple errors with the same case and fence identity. This restriction does not prohibit baseline
allowances for adapter-returned kit errors from a kit with complete identity and a finished session.

By default the checker requires `selection.kind = all`. A filtered report requires an independently
supplied `--filter` with exactly the same pattern. The checker derives that selection itself; it does
not adopt the report's claim of scope. For a filtered check it compares only baseline entries in
scope and reports that unselected entries were not checked. Unknown baseline case IDs are rejected
even when outside the filter. Kit-error records remain in scope regardless of the filter.

A development baseline that allows known binding defects is not a compatibility certificate, and
the command's output says so whenever it accepts allowed failures in scope. An empty baseline also
does not establish complete compatibility: capability skips and filtered scope still limit the claim.

### `report render` (new)

Reads the same strictly validated draft JSON and writes a standalone HTML file atomically. HTML is
optional and opens offline, without a server, CDN, or external assets. JSON remains authoritative.
Rendering does not run an adapter, adjudicate the baseline or certify inventory. A valid report of
a failed session or failing cases can render successfully; exit 0 means the HTML was written, not
that the tests passed. The output cannot overwrite the JSON input, including through a filesystem alias.

## Adapter transport

The wire protocol is IR protocol version 1, unchanged: newline-delimited JSON, one object per line,
request ids starting at 1 and incrementing, strict envelopes, unknown fields rejected, capability
negotiation first, `{"op":"exit"}` to shut down.

### Limits

| Limit | Value | Source |
| --- | --- | --- |
| Per-request timeout | 30 000 ms, `--timeout` | kept |
| Session timeout | 1 800 000 ms (30 min), `--session-timeout` | new |
| Maximum response frame | 16 MiB | new |
| Captured stderr | 4 096 bytes, remainder drained and discarded | kept cap, hardened draining |
| Exit grace after stdout closes | 1 000 ms | kept |
| Shutdown grace after `exit` | 5 000 ms, then terminate | kept |

The largest frame in the baseline transcript is 4 635 bytes, and a full IR run exchanges about
390 KiB in 706 requests. The frame cap leaves three orders of magnitude of headroom while bounding
memory. A full run takes seconds; the session timeout exists so a CI job cannot hang on an adapter
that answers slowly forever.

Each request has one deadline covering both writing the request to stdin and waiting for its
response. An adapter that stops reading a large request still times out. The shutdown grace
period covers writing the `exit` request and waiting for the process to stop.

stderr is read continuously on its own task so a chatty adapter can never block on a full pipe. The
spawned process never opens a console window on Windows.

### Failure classes

A transport failure is never a domain result. None of these can satisfy an expected rejection:

| Condition | Classification |
| --- | --- |
| Spawn failure | transport: `failed to start adapter` |
| stdin closed or write failed | transport: `adapter stdin closed` |
| EOF on stdout, or process exit mid-session | transport: `adapter closed stdout` / `adapter exited with code <n>; stderr: <captured>` |
| Line is not JSON, not an object, or has a bad `id` | transport: malformed frame |
| Response `id` differs from the request | transport: `expected id <n>, got <m>` |
| Invalid UTF-8 in a frame | transport: malformed frame (hardened; the TypeScript driver substituted U+FFFD) |
| Frame exceeds the cap | transport: `frame exceeds <n> bytes` (new) |
| Per-request or session timeout | transport: `adapter timed out` |
| Non-zero exit or timeout at shutdown | reported as a shutdown failure; fails the run |

After the first transport failure the session is broken for good (kept). The failing fence becomes a
`kit-error` record, and every later fence records `adapter unavailable: <first failure>`. A broken
session is never restarted within a run.

Pending fences are no exception (hardened). The TypeScript driver skipped a pending case before
consulting the failure, so a dead adapter could pass a selection of pending cases. This is departure
14 in [migration.md](migration.md#approved-departures-from-old-runner-behaviour).

On timeout or cancellation the adapter and its descendants are terminated and reaped: the process
group on Unix, a Job Object on Windows. Ctrl-C does the same before the CLI exits.

## Reports

Production reports use the consolidated draft in
[`report-draft.schema.json`](../ir/mck/report-draft.schema.json), with the exact string
`contractVersion: "2.0.0-draft.1"`. The adapter wire protocol remains integer version 1.
The reader rejects unknown report versions rather than guessing their shape. Stable `2.0.0`
requires an explicit stabilization decision. This draft does not promise indefinite support for
earlier drafts.

Record identity (`caseId`, `irVersion`, `profile`, `role`, `fenceIndex`, `path`), result kinds
(`pass`, `fail`, `kit-error`, `skipped`), skip reasons and failure messages are kept exactly.
Canonical mismatches retain the short first-line `message` and may also carry a bounded
three-context-line unified `diff`. Its headers identify the case, fence, profile and, for
document-tree writes, the logical path. The optional `check` member is `spelling`, `semantic`
or `round-trip`; readers treat its absence in older reports as `semantic`. The terminal and
offline HTML report show the diff under the short message.

Record order is part of the contract (kept): kit-error records first in kit error order; then cases
with files sorted by name and cases in file order; within a case, each path in the adapter's
`capabilities.paths` order, records sorted by `fenceIndex`. Parse errors attach to the nearest
preceding case heading in the same file, or to the reserved id `kit-0000`.

The report contains driver and kit provenance, the adapter command and complete negotiated
capabilities or a negotiation failure, explicit all/filter selection, strict mode, session
completion or phase-tagged session errors, and the ordered records. `driver.version` carries the
CLI version; `kit.version` retains the old `kitVersion` meaning. See the
[draft example](../ir/mck/report-draft.example.json) for the full shape.

### Consolidated provenance

`--report <file>` writes one JSON file. Production runs no longer write a provenance sidecar.
The unchanged [`report.schema.json`](../ir/mck/report.schema.json) and
[`provenance.schema.json`](provenance.schema.json) describe historical version 1 evidence only.
The frozen transcript replay tests retain their historical report evidence;
production runs emit only the consolidated draft report.

A build from a dirty tree or a source archive reports `dirty: true` or `commit: null`. It never
claims a clean commit it cannot prove. The digests identify the bytes that actually ran. A `local`
kit is a raw authoring checkout and is never reported as matching an upstream snapshot.

## Test obligations

- Rust unit tests for the parser, hash, comparison and report gate, using the
  [hash vectors](baseline/hash-vectors.json) literally.
- A replay adapter that answers from each [baseline transcript](baseline/transcripts/), so the runner
  is tested against both bindings' answers without Bun or Node.
- Hostile adapter fixtures, one per failure class above, plus stdout flood, stderr flood and a child
  that ignores termination. Each must end in a failed run and must never produce a `pass`.
- CLI tests: missing `--adapter` is exit 2 with no report and no spawn; empty selection is exit 1;
  diagnostics stay off stdout; paths and piping work on Windows as well as Unix shells.
- JSON Schema validation of every emitted draft report; legacy baseline reports retain their own schema gate.
- Report reader, inventory, selection, baseline and session-failure tests, plus offline HTML escaping
  and CLI tests. New draft-only fields have separate tests.

## `package inspect` (PKG-2)

Inspects the draft.3 candidate definitions in an explicit repository root,
including schemas, fixed expectations and asset bindings. The contract is
required and currently accepts only `0.1.0-draft.3`. This is definition
inspection; it does not invoke an adapter or execute restore.

stdout contains a JSON definition summary with `kind: "definition-summary"`,
`caseCount`, `boundAssetCount`, `pendingAssetCount` and `errors`. Valid pending
definitions are not errors. The preserved starting inventory is 54 definitions,
6 bound assets and 121 pending bindings. Schema, semantic, path or asset errors
produce exit 1 with diagnostics in the summary. Unsupported contracts and
missing required arguments produce usage exit 2.

The summary contains no compatibility records, pass count or executable kit
hash. Full engine admission rejects pending assets. Exact-case admission is
test-only and cannot turn the candidate corpus into a compatibility report.
`package run` continues to accept only its implemented draft.1/draft.2 contracts.

The separate `package mvp-run` command executes the required local Library MVP
profile through the same native runner and an explicit adapter. `--report FILE`
writes one `0.1.0-draft.1` prerelease JSON report, including failed runs. The
report records driver version and source state, start time, adapter command and
timeouts, negotiated capabilities, profile, full-inventory selection, admitted
kit hash and all ordered required results. `package mvp-report check REPORT
--source DIR` independently reloads the admitted 70-case inventory and rejects
missing, extra or reordered records, a changed kit hash, invalid capabilities,
and any failed case or adapter session. `package mvp-report render REPORT
--output FILE` writes offline HTML atomically. Rendering never certifies the
inventory or a passing run. The existing IR `report` command and draft.1/draft.2
package contracts remain separate.

## `package run` (PKG-1)

`morphir mck package run` extends the same engine with the existing package
contracts. It requires an explicit `--kit` directory and `--adapter` executable;
`--adapter-arg` repeats for the adapter's arguments. The default contract is
`0.1.0-draft.1`, the 80-case integrity suite. `0.1.0-draft.2` selects the 78-case
resolution suite. Other versions are usage errors. Select the same version in
the adapter's own arguments. Missing required arguments or invalid timeouts
return exit 2 before loading data or starting the adapter.

The runner preserves the package contracts' existing request, capability and
report shapes. Canonical schemas live in `spec/package/schemas/package-protocol.schema.json`,
`package-report.schema.json`, `package-resolution-protocol.schema.json` and
`package-resolution-report.schema.json`. These are separate from the IR protocol
and consolidated IR report. The Rust runner identifies its own version in
`driverVersion`; this does not change `contractVersion` or `kit.formatVersion`.

Loading validates corpus structure, unique IDs, fixed expectations, local schemas
and fixture paths before starting an adapter. The existing file-map digest
identifies exactly the consumed bytes under the same logical names. Raw operation
inputs are retained. No expectation is derived from a package implementation.
The engine does not link either adapter's package library.

The same bounded NDJSON session provides request IDs, frame limits, request and
session timeouts, stderr capture and process-tree shutdown. Package capability
and response envelopes are closed; malformed responses are kit errors, never
successful domain rejections. Every case is required. Unsupported operations or
profiles are reported as skips, and any skip, failure or kit error returns exit 1.
Adapter shutdown failures add a `package-adapter-close` kit-error record.

`--report` writes the selected contract's JSON report, including capabilities,
content hash and records, and creates missing parent directories. Without it,
only the terminal summary and diagnostics are emitted. This command does not
embed or acquire package data. The existing `kit`, `report check` and `report render`
commands retain their IR scope.

PKG-1 verified native parity against the same two external adapters, comparing complete
reports except `driverVersion` and `startedAt`. Beta.3 published-artifact qualification
passed on all six targets. After consumer adoption and review, the TypeScript runner,
its APIs and its release paths are retired. Frozen reports and recordings remain
acceptance evidence; live native gates continue to exercise both independent adapters.
