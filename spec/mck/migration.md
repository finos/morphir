# MCK migration to the Rust CLI: consumers, parity and cutover

Status: **approved** in the IR-0 design review on 2026-09-18 ([#851](https://github.com/finos/morphir/issues/851)). Changes now need their own review.
Parent tracking is [#849](https://github.com/finos/morphir/issues/849).

**IR cutover, 2026-09-21.** Parent and audited binding IR gates use the Rust
`morphir mck` commands. Native `v0.4.0-beta.2` is published and qualified on
all six supported targets. Reports remain consolidated `2.0.0-draft.1` JSON
with optional offline HTML; this cutover does not stabilize the draft.

The cutover removes the TypeScript IR runner, embedded IR kit and future
standalone runner binaries, along with temporary parent and binding parity jobs.
The TypeScript adapter, codec regressions, package-only CLI/library APIs and both
npm artifacts remain. Historical published assets, frozen reports, protocol
transcripts and schemas remain available. Package runner migration stays in
[#852](https://github.com/finos/morphir/issues/852).

### Final consumer audit

The 2026-09-21 audit searched tracked content, including hidden workflows,
release configuration, task scripts, manifests and source, at the parent pins
and current remote heads. TypeScript `14f80183` and Rust `3db427f6` were the
only binding repositories with active legacy runner consumers. [TypeScript #32](https://github.com/finos/morphir-typescript/pull/32) and
[Rust #192](https://github.com/finos/morphir-rust/pull/192) remove those consumers
while retaining the required native gates. The parent pins their reviewed retirement revisions.

| Repository | Audited parent pin | Audited remote main | Result |
| --- | --- | --- | --- |
| morphir-python | `dc0b31756a839bd3dfacb2b19e5d32283779df7c` | `63534a6ea0760348f86705c22e1eb45ab4ef2d23` | No MCK integration |
| morphir-gleam | `aa2b7e2377b13ef1af48d9a3a30bec797015933c` | `9c6f0d1440b50909375475cd8781ce0f57d4960e` | No MCK integration |
| morphir-scala | `fb9ca0f4056e817dcf241f7f67ad96716fa8f7e7` | `2b3a935c09760cd0ab9ff09f3e48c0f2f8dceda2` | No MCK integration |
| morphir-moonbit | `6d473c7e1bc9b717cb4c25583cf3eb03b060510d` | `8958a343f29afcbee98fcb4377232bd0bfe4a3f1` | No MCK integration |
| morphir-elm | `b065e493d7a4256ed47878b129abf2333e977313` | `bc99af69a8b24d391311fae3822a87eafef3c334` | No MCK integration; also checked vnext `e27e12a3` |
| morphir-ui | `8e4bbf2f7a25d658ee162ab2b689bd1ed02cb138` | `86bcce97f58d29f4f844f5af3265fa4bd23b9321` | Five decoder comments name cases; no executable integration |
| morphir-examples | `7a4a90a03d15a4594aa9675c114f76f82aecf525` | `34b8cf58391ba7ec46f839e7d2376443db064e61` | No MCK integration |

No additional repository consumer needs a migration owner. The parent contains
no MCK integration references requiring expansion to Go, .NET, JVM or Bosque;
those sibling repositories are outside this audit. External npm consumers are
not enumerable from repository search. The
[CLI/library guide](../../docs/developers/mck-native-migration.md#consumer-cutover)
explains the removal and preserves access to historical versions.

### Retained checks and data

- Native authoring, full adapter runs, report inventory checks and JSON/HTML
  artifacts remain required in parent and binding CI.
- Vocabulary generation remains an authoring check against the TypeScript IR
  model, named `mck:vocabulary-check`. It is separate from the retired runner.
- TypeScript retains 98 canonical JSON/YAML pairs, 121 YAML idempotence cases,
  the complete example and nine rejected YAML cases as independent codec tests.
  The 77 layout tests retain their canonical distributions and document-tree
  fixtures; eight subprocess tests now exercise the shared transport directly.
  Fixture provenance records the original kit source at `2bab57ea23fe85c6f9cc434b32e61f29ca14190c`.
- The installed Node 24 MCK adapter is exercised by the released native CLI.
  The independent Node 20 IR artifact gate and package artifact checks remain.
- Parent package tasks and their adapter-path and recording helpers remain.
  No package runner semantics change before #852.
- Frozen legacy reports, report schemas and transcripts stay because native
  regression and release-qualification tests consume them. Temporary live
  old/new comparison executables and source-copy checks are removed.

## Historical consumer inventory

The following tables preserve the migration inventory and intermediate adoption state. They are historical; the final audit and retained checks above describe the cutover. "Slice" identifies the delivery phase.

### finos/morphir

| Consumer | What it runs today | Slice |
| --- | --- | --- |
| mise `mck:check` | Native kit and schema checks, with retained source parity | Adopted in IR-3 |
| mise `mck:schema-check` | Native `morphir mck schema check` | Adopted in IR-3 |
| mise `mck:source-parity` | Vocabulary regeneration check and protocol byte-copy comparison against the pinned TypeScript source | Retained until IR-4 |
| mise `mck:run` | Rust runner with explicit TypeScript adapter; native `report check` against the empty parent baseline; native `coverage` | Adopted in IR-3. The approved in-process run is dropped. |
| mise `mck:run-rust` | Builds `mck-adapter-rust`, Rust runner, native `report check` against the binding's `allowed-failing.json`, native coverage | Adopted in IR-3 |
| mise `check` aggregate | Depends on `mck:check`, which includes schema checks | Adopted in IR-3; standalone `mck:schema-check` remains available |
| `tools/run-mck-rust.ts`, `tools/rust-mck-command.ts` and test | Resolve the adapter path and spawn the TypeScript driver for parity and package suites | Retained until those consumers migrate; no shared helper deletion in the reporting slice |
| `tools/validate-mck-fences.ts`, `tools/validate-mck-protocol.ts` | Frozen fence/protocol validators for migration evidence | Production replaced by `morphir mck schema check`; retain until IR-4 |
| `tools/check-mck-report.ts` and test | Historical version 1 baseline gate | Parent IR tasks replaced by `morphir mck report check`; retained as legacy tooling |
| CI `docs` job | Native authoring gates and `mck:run`; renders HTML separately and uploads JSON plus HTML | Parent IR gates adopted in IR-3 |
| CI `rust-conformance` job | Native `mck:run-rust`, separate HTML rendering and JSON/HTML upload; live parity | Reporting adopted |
| CI `changes` filters `mck`, `rust-conformance` | Path-aware routing from [#843](https://github.com/finos/morphir/pull/843) | `mck` includes the native engine/CLI inputs; `rust-conformance` also runs for the existing `rust` filter. Prior inputs remain routed. |
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

### Historical IR-4 audit and adoption order

The 2026-09-20 audit checked both current binding heads against these pinned sources:
[TypeScript `a5e3be09`](https://github.com/finos/morphir-typescript/tree/a5e3be0922ce2dad1920956a8c7bfe6616d515d5)
and [Rust `1d2640e5`](https://github.com/finos/morphir-rust/tree/1d2640e50661509af3e31dba03376a11a0073adf).
The consumers above remain active. The parent CLI's published `v0.4.0-beta.1`
predates the IR-3 authoring gates; adoption requires a subsequent release carrying them.

TypeScript already defines separate adapter executables for five platform targets
in `scripts/release/binaries.ts`; Windows ARM uses its Windows x64 adapter under
emulation. Independent distribution does not inherently require another npm package.
The remaining dependency is in its source/build graph: `adapter.ts` loads the
package adapter, whose `package/reference.ts` imports `driver/version.ts`, which
imports `kit/embedded.ts`. Move binding version metadata out of the driver and
add an adapter-only build path while preserving package adapter behavior and
existing driver production. Its binary tests must execute the adapter through the
native runner; the current smoke test executes only the driver. Published adapter
download availability and execution still need verification.

Adoption proceeds in this order:

1. Land the packaged CLI gate and publish a native release containing IR-3. Record
   the exact release version, checksums, kit revision and three-platform offline
   acceptance evidence. Adapter build separation can proceed alongside this work.
2. Migrate TypeScript's `.config/mise/tasks/check/conformance.ts` and `check/kit.ts`
   to that pinned CLI, an explicit adapter and a vendored native kit manifest.
   The historical `packages/mck/kit.lock.json` has a different format and must not
   be renamed to `mck-kit.lock.json`. Preserve package checks, frozen parity and
   installed npm artifact tests; `scripts/release/package-mck.ts` still serves
   both IR and package consumers.
3. Migrate Rust's driver pin, acquisition task, report adjudication and CI routing
   together. Fetch the parent target archive and checksum, retain atomic download
   and stale-report handling, and use native `report check` against the same
   vendored kit as `run`. Replace the Unix-only acquisition path and validate on
   Windows too. Its legacy report test cannot certify draft session, provenance
   or inventory evidence.
4. Publish CLI/library migration guidance and review adoption evidence in #851.
   Only then retire the TypeScript IR runner, embedded-kit and related release
   paths. Keep all package tooling until #852 and preserve the IR package's Node
   20 artifact gate independently of the MCK package's Node 24 requirement.

### Published release and binding adoption evidence

The [beta.2 release](https://github.com/finos/morphir/releases/tag/v0.4.0-beta.2)
uses source `48977b55ec1c1ccf834837fe1912e01615071d46`. Its tag and binaries were
unchanged by the subsequent qualification-tooling repairs. The
[release run](https://github.com/finos/morphir/actions/runs/35557203384) passed all
six packaged CLI smoke jobs. The final
[published qualification run](https://github.com/finos/morphir/actions/runs/35565692422)
passed Linux, macOS and Windows on both x64 and ARM64.

Every target's retained artifact records its verified published archive checksum,
the exact acquired source commit, a committed kit snapshot, removed acquisition
state, and an operating-system network-denial result. The native runtime uses an
empty tool PATH and fresh home, verifies the kit and report, renders offline HTML,
and matches all 730 ordered records against the source kit. Source transcript and
hostile-adapter tests also pass on each target. The snapshot digest is
`sha256-07b32a353c34015ad96c84d02c85af00615aacdb5da4831a448708d051d7acfb`;
the corpus hash is
`sha256-0bacb95902e3870a2dadffe7f316d55ed849fe90a3b2fac11060b5b6a76909fa`.
This replay qualification proves the runner; the binding gates below exercise
the actual implementations separately.

| Consumer | Adopted revision | Evidence |
| --- | --- | --- |
| TypeScript | [`14f80183`](https://github.com/finos/morphir-typescript/pull/31) | Required native gates, six checksummed CLI pins, managed kit, JSON/HTML artifacts; 722 passing records and 8 declared-capability skips. Existing legacy parity, package checks, Node 20 IR and Node 24 MCK artifact gates remain. |
| Rust | [`3db427f6`](https://github.com/finos/morphir-rust/pull/191) | Required native gates on Linux/macOS/Windows, the same release and kit, JSON/HTML artifacts; all 730 records pass. The explicit Linux legacy gate and package/extension checks remain. |

Both live adapters also passed the complete migration comparison below against the
published CLI and the same managed kit. Both versioned report schemas were checked
with format assertions. The legacy runner received the manifest's source revision
as its kit version before execution; the comparison includes that header and every
ordered record, excluding only `startedAt`, `durationMs` and `driverVersion`.
An earlier TypeScript record-only comparison omitted the kit-version header and
was superseded by this complete comparison.

The retirement boundary covers the TypeScript IR runner,
embedding and future runner-binary releases, plus the temporary parent parity
gates. Shared package code, adapter implementations and both npm artifacts must
remain. In particular, preserve the binding regressions currently in
`driver/yaml-roundtrip.test.ts` before deleting that directory: canonical JSON/YAML
pairs, YAML idempotence, the complete example and rejected-input handling. Keep
package-only CLI/library exports, package hashing and transport helpers, the
installed Node 24 adapter smoke, and the independent Node 20 IR artifact gate.
Historical packages and release assets remain available. These obligations apply to the coordinated retirement changes.

## Parity method

The old and new runners are compared against **the same external adapters** at the same pins, at
least `mck-adapter-typescript` and `mck-adapter-rust`. The baseline reports are
[baseline/reports/](baseline/reports/).

Both reports must first pass their versioned schemas: the first driver's
`report.schema.json` and the Rust runner's `report-draft.schema.json`. The comparator uses an
explicit migration-only projection from the consolidated draft into legacy evidence:

| Draft field | Legacy field |
| --- | --- |
| `adapter.negotiation.capabilities.binding` | `binding` |
| `adapter.negotiation.capabilities.language` | `language` |
| `adapter.negotiation.capabilities.formatVersions` | `formatVersions` |
| `kit.version` | `kitVersion` |
| `records` | Every record, unchanged and in order |
| `contractVersion: "2.0.0-draft.1"` | `contractVersion: 1` for this comparison only |

Failed negotiation projects the legacy identity fields to `unknown`. New provenance,
capabilities, selection and session fields have separate schema and semantic tests; the legacy
projection cannot prove them. The engine's internal legacy report remains for transcript replay
until parity cutover. It is not a supported production output mode.

Compared after projection: the legacy header, every record, every field, and record order.

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
  response of a full run, one per adapter. A replay adapter answers from it, so the Rust runner must
  send byte-equivalent requests in the same order and produce the same report, without Bun or Node.
  The two adapters answer differently: the TypeScript binding skips the version 3 cases it does not
  support, and the Rust binding runs them, so the replays cover a skipping run and a complete one.
- **Historical live comparison on one adapter.** The retired `mck:parity-rust` task built the pinned Rust adapter and
  had both runners question that same build in one CI job, then compares the reports under the
  exclusions above. A recording keeps its answers fixed; this keeps the binding fixed instead, so a
  difference can only be the runner's. Its transcript is uploaded, and a future baseline is frozen
  from it.
- **Hostile adapters.** One fixture per failure class in the
  [CLI contract](cli-contract.md#failure-classes). Each must fail the run.

Temporary old/new comparison code ran in development and CI only. It is removed at cutover; frozen evidence remains. The shipped CLI never depended on it.

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
| 9 | Provenance is `kitVersion` only; IR-2 added a version 1 report plus provenance sidecar | Consolidated `2.0.0-draft.1` report contains provenance, capabilities, selection and session outcome; optional standalone HTML renders the JSON | #849 reporting-slice decision, 2026-09-20 |
| 10 | `mck` binary | `morphir mck`; the old name gets no shim in this delivery | #849 |
| 11 | The report gate never compares the report's records with the kit | `report check` rejects missing, extra and duplicate records against the kit's expected inventory | #849 |
| 12 | `check` never opens `text` fixtures and decodes case files lossily | `check` reports unusable fixtures and undecodable case files as kit errors | #849 (IR-1 fixture confinement) |
| 13 | Capabilities with an open-ended `formatVersions` interval are not checked against `versions` | Every major such an interval holds, from its lower bound up to the highest listed major (or the domain floor, if higher), must be listed | #876 review; maintainer approval 2026-09-19 |
| 14 | A pending case is skipped even after the adapter failed, so a dead adapter passes a selection of pending cases | After an adapter failure every fence is a kit error, pending ones included; pending is skipped only while the adapter lives | #879 review; maintainer approval 2026-09-19 |

Departures 2, 4, 5, 6, 11, 12 and 13 cannot change a report for a well-behaved adapter, so they do not
affect the parity comparison.

Departure 9 changes the envelope, not the record comparison. Historical report and provenance
schemas remain only for legacy evidence. The adapter protocol stays at version 1. Stabilizing the
report as `2.0.0` requires an explicit decision; this draft makes no indefinite support promise for
old draft shapes.

The report checker independently loads the kit and verifies its snapshot digest and expected
inventory. Missing digest or failed session evidence cannot be certified. The default scope is the
full kit; a filtered report requires an independently supplied exact filter. An allowed-failing
baseline is a development gate, not a compatibility certificate. JSON is authoritative; HTML is an
optional offline view with no server or CDN, and successful rendering does not mean tests passed.
CI renders after failures when a fresh report exists and preserves the failed run/check status.

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

### IR-4 packaged CLI smoke gate

Before uploading an archive, the release workflow extracts it and runs
`installed_cli_runs_vendored_kit_without_tool_runtimes` on each of the six native
Linux, macOS and Windows targets. The test copies that executable, a native
transcript replay adapter and its recorded inputs into a fresh temporary
directory. CLI subprocesses have an empty `PATH`, fresh home/cache/temp
directories and no inherited Morphir configuration.

The gate verifies installed help/version commands, embedded-kit vendoring,
status, check, coverage, schema validation, an explicitly selected adapter run,
report checking and standalone HTML rendering. It compares the vendored run's
snapshot digest and all records against the same executable using the source
kit, and verifies that a modified vendored schema is rejected. The replay adapter
tests runner installation; it is not a new binding implementation or evidence of
independent adapter distribution.

To repeat this gate against an extracted archive, set
`MORPHIR_MCK_INSTALLED_CLI` to the absolute executable path and run:

```sh
cargo test --locked --release --package morphir --test mck_run \
  installed_cli_runs_vendored_kit_without_tool_runtimes
```

Without that environment variable, ordinary Cargo tests exercise the locally
built CLI. A supplied missing or invalid executable fails the test; it never
falls back to the local build. The test harness itself still needs the source
checkout and Rust build tools. This smoke gate does not disconnect the operating
system's network, acquire a pinned upstream revision, or certify a published
release. The cache-removal/network-disabled acceptance test in
[kit-manifest.md](kit-manifest.md#acceptance), binding CI adoption, independent
TypeScript adapter distribution and cutover review remain required separately.
