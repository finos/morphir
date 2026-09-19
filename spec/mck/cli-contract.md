# `morphir mck` CLI and engine contract

Status: **approved** in the IR-0 design review on 2026-09-18 ([#851](https://github.com/finos/morphir/issues/851)). Changes now need their own review.
Nothing here is implemented yet. The TypeScript driver in finos/morphir-typescript remains the
authoritative gate until the cutover described in [migration.md](migration.md).

This contract covers the IR suite. Package commands are added by
[#852](https://github.com/finos/morphir/issues/852) and must not reuse IR fields with other meanings.
Ownership is recorded in
[decision 0003](../../kb/bundles/morphir/morphir-package-system/decisions/0003-mck-tooling-lives-in-the-rust-morphir-cli.md).

Each behaviour below is marked **kept** (same as the TypeScript driver at the
[baseline](baseline/README.md)), **hardened** (a deliberate, stricter departure) or **new**.

## Components

| Component | Responsibility |
| --- | --- |
| `crates/morphir-mck` library | `kit` (parse, load, hash, manifest, acquisition), `transport` (adapter sessions), `ir` (execution, comparison, capabilities, coverage), `report` (version 1 records, summary, baseline gate) |
| `crates/morphir/src/commands/mck` | Argument validation, help, terminal output, exit status. No compatibility logic. |
| Adapter | Owned by each implementation. Decodes, encodes and handles document trees. |

Case interpretation and comparison are pure functions, callable without a subprocess or global
state. The engine never links an implementation's IR codec. It compares canonical strings under the
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
morphir mck kit status [--kit <dir>] [--json]
morphir mck kit vendor --source <source> [--revision <commit>] [--expect-digest <digest>] --dest <dir>
morphir mck kit update --kit <dir> [--source <source>] [--revision <commit>] [--expect-digest <digest>]
```

For `kit vendor` and `kit update`, `--revision` is required with `--source github:finos/morphir` and
is usage error 2 with any other source.

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

The case grammar, fence roles, pending cases, duplicate-id detection, ignored prose illustrations
and `text` fixture confinement are those of the [IR suite README](../ir/mck/README.md). The Rust
parser must produce the same diagnostics, with the same source locations, for the same input.
[baseline/kit-cases.json](baseline/kit-cases.json) freezes the TypeScript parser's reading of the
corpus, and a Rust test compares itself with it case by case.

**Fixtures (hardened).** `check` also resolves every `text` fence against the repository root
(`--repo-root`, or the root inferred when the path ends in `spec/ir/mck`) and reports, at the
fence's line, a fixture that is missing, escapes the root, is neither `.json` nor `.yaml`, is not
valid UTF-8, or starts with a byte-order mark. The TypeScript `check` never opened fixtures, so a
broken one surfaced only during `run`. A case file that is not valid UTF-8 is a kit error too,
where the old driver substituted U+FFFD. This is departure 12 in
[migration.md](migration.md#approved-departures-from-old-runner-behaviour).

A directory holding a managed snapshot is verified against its manifest first
([kit-manifest.md](kit-manifest.md#managed-and-raw-kits)). Until IR-1V lands that verification, a
managed snapshot is refused with exit 1; it is never read as a raw kit.

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
response id pairing. The byte comparison against the morphir-typescript contract copies is dropped
at cutover, when those copies stop being authoritative.

### `report check` (kept gate, hardened inventory, new home)

Replaces `tools/check-mck-report.ts`. Kept: record shapes are validated; the set of failing case ids
must equal the `cases` array of the allowed-failing file in both directions, so a stale entry fails
as loudly as a new failure; at least one record must pass; every skip must carry a legitimate driver
reason: `pending`, or `node|version|layout|profile|path <x> not in capabilities`.

**Record inventory (hardened).** The old tool never compares the report with the kit, so a truncated
report, or one with duplicated passing records, is accepted. The Rust gate derives the expected
record identities from the kit (`--kit`, default embedded) and the capabilities in the report
header, and rejects missing, extra and duplicate records. #849 requires this; it is departure 11 in
[migration.md](migration.md#approved-departures-from-old-runner-behaviour).

A development baseline that allows known binding defects is not a compatibility certificate, and
the command's output says so whenever the allowed list is non-empty.

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

On timeout or cancellation the adapter and its descendants are terminated and reaped: the process
group on Unix, a Job Object on Windows. Ctrl-C does the same before the CLI exits.

## Reports

IR report version 1 is closed and unchanged. Header, record identity (`caseId`, `irVersion`,
`profile`, `role`, `fenceIndex`, `path`), result kinds (`pass`, `fail`, `kit-error`, `skipped`),
skip reasons and failure messages are kept exactly.

Record order is part of the contract (kept): kit-error records first in kit error order; then cases
with files sorted by name and cases in file order; within a case, each path in the adapter's
`capabilities.paths` order, records sorted by `fenceIndex`. Parse errors attach to the nearest
preceding case heading in the same file, or to the reserved id `kit-0000`.

`driverVersion` carries the `morphir` CLI version. `kitVersion` keeps its meaning: the revision of
the kit that ran.

### Provenance sidecar (new)

Version 1 cannot carry richer provenance and gains no undocumented fields. When `--report <file>` is
given, the runner also writes `<file>.provenance.json`:

```json
{
	"provenanceVersion": 1,
	"driver": { "name": "morphir", "version": "0.5.0", "commit": "<40 hex or null>", "dirty": false },
	"kit": {
		"source": "embedded | vendored | local",
		"revision": "<40 hex or null>",
		"snapshotDigest": "sha256-...",
		"corpusHash": "sha256-...",
		"modified": false
	},
	"adapter": { "command": ["./my-adapter"], "binding": "...", "formatVersions": "..." }
}
```

A build from a dirty tree or a source archive reports `dirty: true` or `commit: null`. It never
claims a clean commit it cannot prove. The digests identify the bytes that actually ran. A `local`
kit is a raw authoring checkout and is never reported as matching an upstream snapshot.

## Test obligations

- Rust unit tests for the parser, hash, comparison and report gate, using the
  [hash vectors](baseline/hash-vectors.json) literally.
- A replay adapter that answers from the [baseline transcript](baseline/transcripts/), so the runner
  is tested without Bun or Node.
- Hostile adapter fixtures, one per failure class above, plus stdout flood, stderr flood and a child
  that ignores termination. Each must end in a failed run and must never produce a `pass`.
- CLI tests: missing `--adapter` is exit 2 with no report and no spawn; empty selection is exit 1;
  diagnostics stay off stdout; paths and piping work on Windows as well as Unix shells.
- JSON Schema validation of every emitted report and sidecar.
