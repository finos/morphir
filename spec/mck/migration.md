# MCK migration to the Rust CLI: consumers, parity and cutover

Status: **approved** in the IR-0 design review on 2026-09-18 ([#851](https://github.com/finos/morphir/issues/851)). Changes now need their own review.
Parent tracking is [#849](https://github.com/finos/morphir/issues/849).

**Transition state, 2026-09-18.** The ownership decision is made
([decision 0003](../../kb/bundles/morphir/morphir-package-system/decisions/0003-mck-tooling-lives-in-the-rust-morphir-cli.md)).
No Rust MCK tooling exists. Every task, CI job and release path below still runs the TypeScript
driver, and those gates stay authoritative until the cutover conditions at the end of this page are
met. TypeScript MCK features are frozen; break/fix only.

## Consumer inventory

Audited at the [baseline](baseline/README.md) pins. "Slice" is where the consumer moves to Rust.

### finos/morphir

| Consumer | What it runs today | Slice |
| --- | --- | --- |
| mise `mck:check` | `bun .../mck/src/cli.ts check spec/ir/mck`, JSON Schema checks, `tools/validate-mck-protocol.ts` | IR-3 |
| mise `mck:schema-check` | `tools/validate-mck-fences.ts` | IR-3 |
| mise `mck:run` | TypeScript binding in-process and through its adapter, then `coverage` | IR-3. The in-process run has no Rust equivalent and is dropped; the adapter run remains. |
| mise `mck:run-rust` | Builds `mck-adapter-rust`, `tools/run-mck-rust.ts`, schema validation, `tools/check-mck-report.ts` against `allowed-failing.json` | IR-3 |
| mise `check` aggregate | Depends on `mck:check` and `mck:schema-check` | IR-3 |
| `tools/run-mck-rust.ts`, `tools/rust-mck-command.ts` and test | Resolve the adapter path and spawn the TypeScript driver | Retired in IR-3 |
| `tools/validate-mck-fences.ts`, `tools/validate-mck-protocol.ts` | Fence and protocol example validation | Replaced by `morphir mck schema check` in IR-3 |
| `tools/check-mck-report.ts` and test | Allowed-failing baseline gate | Replaced by `morphir mck report check` in IR-3 |
| CI `docs` job | `mck:check`, `mck:schema-check`, `mck:run`; uploads `mck-reports` | IR-3 |
| CI `rust-conformance` job | `mck:run-rust`; uploads `mck-report-morphir-rust` | IR-3 |
| CI `changes` filters `mck`, `rust-conformance` | Path-aware routing from [#843](https://github.com/finos/morphir/pull/843) | IR-3 extends them with `crates/morphir-mck/**` and the command module. The older all-jobs workflow is not restored. |
| `tests/ci/test_ci_path_aware.py`, `test_release_workflow.py` | Pin that routing | Updated with the workflow in IR-3 |
| mise `package:*` tasks, CI `package-mck` job, `tools/package-ci.test.ts` | Package suites draft.1 and draft.2, assurance and publisher checks | Unchanged until [#852](https://github.com/finos/morphir/issues/852) |
| `AGENTS.md`, `ecosystem/AGENTS.md`, `CONTEXT.md`, `spec/mck/README.md`, `spec/ir/mck/README.md` | Ownership guidance | Updated with this document; rewritten to the Rust commands at IR-4 |
| `docs/spec/ir/schemas/**`, `docs/developers/*.md` mentions | Refer to MCK cases, not to driver commands | Reviewed at IR-4 |

### finos/morphir-typescript

| Consumer | What it runs today | Slice |
| --- | --- | --- |
| `@finos/morphir-mck` npm package, bins `mck` and `mck-adapter-typescript` | Driver, embedded kit, adapter | IR-4: the adapter becomes independently distributable; the runner, CLI and kit embedding retire after adoption. Published versions and release assets stay available. |
| mise `check:conformance` | Driver against its own adapter | IR-4: pins a `morphir` release and a vendored kit |
| mise `check:kit` | `mck kit status` | IR-4: `morphir mck kit status --kit <vendored>` |
| mise `check:package`, CI Node 24 gate | Package suites | Unchanged until #852. `@finos/morphir-ir` keeps its Node 20 artifact gate; the MCK Node 24 floor never raises it. |
| Release workflow and `scripts/release/*` | npm tarball plus ten compiled `mck` and adapter binaries | IR-4: adapter binaries only, after cutover |

### finos/morphir-rust

| Consumer | What it runs today | Slice |
| --- | --- | --- |
| `crates/morphir-mck-adapter` (`mck-adapter-rust`) | The Rust adapter, IR and package suites | Stays. It is an implementation adapter, not shared tooling. |
| `.mise/tasks/check/kit` | Downloads the pinned TypeScript `mck` binary, verifies its SHA-256, runs it against the adapter. Refuses to run on Windows. | IR-4: pins a `morphir` release and a vendored kit, which also removes the Windows refusal |
| `.config/mck-driver-version`, CI `kit-conformance`, `.github/ci-impact.toml` | Pin and route the above | IR-4 |
| `tests/report.rs` | Allowed-failing gate, mirrored by the parent tool | IR-4: replaced by `morphir mck report check`, or kept as an adapter-local test |

### Other bindings

morphir-python, morphir-gleam, morphir-scala, morphir-moonbit and morphir-elm have no adapter, no
MCK CI step and no MCK release step at the baseline. `ecosystem/AGENTS.md` and the parent `mck` path
filter name Gleam as a future target only. Nothing to migrate. Their first integration uses
`morphir mck` and a vendored kit directly.

## Parity method

The old and new runners are compared against **the same external adapters** at the same pins, at
least `mck-adapter-typescript` and `mck-adapter-rust`. The baseline reports are
[baseline/reports/](baseline/reports/).

Compared: the report header, every record, every field, and record order.

Excluded, and nothing else:

| Field | Reason |
| --- | --- |
| `startedAt` | Wall-clock time |
| `durationMs` | Timing |
| `driverVersion` | Intentionally a different driver |

Kit errors, skip reasons, missing records and ordering are never discarded to make parity pass.
The old runner's reports were checked for determinism under these exclusions: three runs of the
TypeScript binding, in-process, through its adapter, and through a recording proxy, were identical.

Two further sources keep a shared bug or a binding gap from hiding a runner defect:

- **Transcript replay.** [baseline/transcripts/](baseline/transcripts/) holds every request and
  response of a full run. A replay adapter answers from it, so the Rust runner must send
  byte-equivalent requests in the same order and produce the same report, without Bun or Node.
- **Hostile adapters.** One fixture per failure class in the
  [CLI contract](cli-contract.md#failure-classes). Each must fail the run.

Temporary old/new comparison code lives in development and CI only. The shipped CLI never depends
on it, and it is deleted at cutover. There are not two permanent MCK implementations.

## Approved departures from old-runner behaviour

Fixed corpus expectations stay normative. These are the only intended differences; each needs a
regression test, and any further one needs its own approval before it lands.

| # | Old behaviour | New behaviour | Authority |
| --- | --- | --- | --- |
| 1 | No `--adapter` runs the TypeScript binding in-process | Usage error 2, nothing runs, no report | Maintainer decision, 2026-09-18 |
| 2 | A run selecting zero cases exits 0 | Exits 1, `no cases selected` | #849, hardened claim gate |
| 3 | `--only` is a JavaScript `RegExp` | `--filter` (alias `--only`) uses Rust `regex` syntax; unsupported constructs are usage errors | #849 |
| 4 | Response frames are unbounded | 16 MiB cap, transport failure | #849 |
| 5 | Invalid UTF-8 becomes U+FFFD | Transport failure | #849 |
| 6 | No session bound | 30 min session timeout | #849 |
| 7 | Timeout sends SIGTERM to the child only | Process tree terminated and reaped on every platform | #849 |
| 8 | `kit sync`, `kit status --remote` | Removed; `kit vendor`, `kit update`, local-only `kit status` | #849 |
| 9 | Provenance is `kitVersion` only, no dirty flag | Version 1 report unchanged, plus a provenance sidecar | #849 |
| 10 | `mck` binary | `morphir mck`; the old name gets no shim in this delivery | #849 |
| 11 | The report gate never compares the report's records with the kit | `report check` rejects missing, extra and duplicate records against the kit's expected inventory | #849 |

Departures 2, 4, 5, 6 and 11 cannot change a report for a well-behaved adapter, so they do not
affect the parity comparison.

## Cutover conditions

TypeScript-owned IR runner, CLI, kit embedding and release paths are retired only when all hold:

1. Parity is published for both adapters with every difference mapped to the table above.
2. Transcript replay and hostile-adapter tests pass on Linux, macOS and Windows.
3. A released native `morphir` runs the fresh-repository acceptance test in
   [kit-manifest.md](kit-manifest.md#acceptance) offline on all three platforms.
4. Parent CI and the audited binding CI above use the Rust runner with no required case or
   regression gate dropped.
5. `mck-adapter-typescript` is distributable without the retired runner, and migration and
   deprecation guidance for CLI and library users is published. Library users get explicit
   migration guidance, not a source-compatibility promise.
6. The cutover review in #851 is complete.

Package paths stay frozen in TypeScript, untouched, until #852.
