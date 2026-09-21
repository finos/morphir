---
title: Migrating MCK IR checks to the native CLI
sidebar_label: MCK native migration
---

The shared MCK IR runner now lives in the Rust `morphir` CLI. Each binding still
owns its adapter. This guide covers migrating IR checks from the TypeScript
`mck` driver to `morphir mck`, including consumers of `@finos/morphir-mck`.

The release and binding adoption work is tracked in
[issue #851](https://github.com/finos/morphir/issues/851). The native
`v0.4.0-beta.1` release predates the complete reporting gates described here.
Use a subsequent release that includes them, and record its exact version and
archive checksum in your build configuration. The report format remains
`2.0.0-draft.1`; adopting the CLI does not stabilize that format.

## Pin the runner, kit and adapter separately

Install the archive for your operating system and architecture from
[Morphir releases](https://github.com/finos/morphir/releases), verifying its
published SHA-256 before extraction. Keep the runner version separate from the
kit revision and the binding's adapter version. Avoid a moving `latest` URL in CI.

Vendor a kit at an exact upstream commit. Replace `FULL_COMMIT_SHA` below with
the reviewed full commit hash containing the cases you intend to run.

```sh
morphir mck kit vendor --source github:finos/morphir \
  --revision FULL_COMMIT_SHA --dest vendor/mck
morphir mck kit status --kit vendor/mck
```

Add `vendor/mck/** -text` to your repository's `.gitattributes` to preserve the
snapshot's exact bytes across platforms. Commit that rule and the entire managed
snapshot, including `mck-kit.lock.json`. Acquisition uses the network; the remaining checks
run offline from the committed files. For the kit embedded in the installed
CLI, use `--source embedded` instead and omit `--revision`.

The TypeScript driver's `kit.lock.json` has a different format. Create a native
snapshot with `kit vendor`; renaming the old lock file does not migrate it.
Use `kit update --kit vendor/mck --revision FULL_COMMIT_SHA` to update a snapshot
whose source is GitHub, then review and commit the changes. Local modifications
to managed files fail verification before execution.

## Replace the commands

| Previous use | Native replacement |
| --- | --- |
| `mck check <dir>` | `morphir mck check <dir>` |
| `mck run` with an implicit TypeScript binding | `morphir mck run --adapter <executable>` |
| `mck run --only <pattern>` | `morphir mck run --adapter <executable> --filter <pattern>` |
| `mck kit status` | `morphir mck kit status --kit <snapshot>` |
| `mck kit sync` or remote status | Explicit `kit vendor` or `kit update`, then local `kit status` |
| Parent fence and protocol validation scripts | `morphir mck schema check --kit <snapshot>` |
| Parent report baseline script | `morphir mck report check <report> <baseline> --kit <snapshot>` |

Every run requires an explicit adapter. Pass extra arguments with repeated
`--adapter-arg` options. There is no adapter discovery or in-process fallback.
The IR adapter wire protocol remains version 1, so existing compliant adapters
can be used with the native runner.

These commands use the same committed snapshot throughout:

```sh
morphir mck check vendor/mck
morphir mck coverage --kit vendor/mck
morphir mck schema check --kit vendor/mck
morphir mck run --adapter /absolute/path/to/mck-adapter \
  --kit vendor/mck --report artifacts/mck-report.json
morphir mck report check artifacts/mck-report.json allowed-failing.json \
  --kit vendor/mck
morphir mck report render artifacts/mck-report.json \
  --format html --output artifacts/mck-report.html
```

Adapt the executable path for your installation, including `.exe` on Windows.
The HTML opens offline and contains no external assets. Preserve the JSON as the
authoritative report. Rendering can succeed for a failed run; it does not replace
the report check.

## Preserve CI failure handling

Remove an old report before starting a run. A usage error writes no new report,
so reusing yesterday's file can hide a failed invocation.

For a development gate with an allowed-failing baseline, handle execution in
this order:

1. Run the adapter and capture the exit status.
2. Propagate abnormal termination and statuses other than 0 or 1.
3. Require a fresh report, including when the run exited 1.
4. Run native `report check` with the same kit and the reviewed baseline.
5. Render and upload diagnostics without replacing a failed gate's status.

Exit 1 may represent known case failures or an operational error. Accept it only
when the fresh report passes the independent report check. The checker rejects
failed adapter sessions, missing provenance, incomplete or reordered inventories,
and stale baseline entries. Allowing a case in a baseline cannot waive those
checks.

Keep `--strict` failures fatal when your gate requires every record to pass.
A baseline gate describes development progress. Capability skips and filtered
scope still limit any compatibility claim, even with an empty failure baseline.

## Filters and reports

`--filter` matches case IDs using Rust regular-expression syntax. `--only` remains
an alias. Look-around and backreferences from JavaScript regular expressions are
unsupported and fail with usage status 2. Selecting no cases fails with status 1.

The report checker defaults to the full inventory. To check a deliberately
filtered run, supply the exact same filter independently to `report check`:

```sh
morphir mck run --adapter /absolute/path/to/mck-adapter \
  --kit vendor/mck --filter '^types-' --report artifacts/types.json
morphir mck report check artifacts/types.json allowed-failing.json \
  --kit vendor/mck --filter '^types-'
```

The consolidated report identifies its contract with the string
`"2.0.0-draft.1"`. It includes kit provenance, negotiated adapter capabilities,
selection, session outcome and records in one file. No run-context companion
file is needed. Readers should dispatch on `contractVersion` and explicitly
reject unsupported versions. Draft revisions may change as the design develops;
there is no indefinite compatibility promise for an old draft shape.

Historical version 1 reports lack evidence required by the new checker. Retain
them as historical results or rerun the adapter to obtain a current report.
Changing their version field or manufacturing missing context cannot establish
the provenance and session evidence that the native gate requires.

## Migrate library consumers

The Rust runner is not a source-compatible replacement for the TypeScript
library. Update integration boundaries explicitly:

| TypeScript library use | Migration |
| --- | --- |
| `runKit`, `processTestee`, or `inProcessTestee` to execute IR cases | Invoke `morphir mck run` as a subprocess with an explicit adapter, then read the versioned JSON report. |
| `coverageGaps` and kit/schema validation helpers used as build gates | Invoke native `coverage`, `check` and `schema check` against the selected snapshot. |
| `emptyReport`, `summarize`, or `writeReport` to construct runner reports | Let the runner produce its report. Use `report check` for adjudication and `report render` for HTML. |
| `loadKit`, embedded-kit imports or `kitVersion` for acquisition and identity | Vendor a managed snapshot and record its manifest alongside the pinned CLI version. |
| IR comparison helpers imported into custom validation | Review the caller's contract and migrate it explicitly. These helpers have no promised drop-in replacement. |
| `runPackageKit`, `runResolutionKit`, package corpus loaders or process-runner helpers | Invoke `morphir mck package run` with an explicit kit, matching contract and adapter; read the existing draft package report. |
| Independent package resolution, reference operations or draft.3 registry helpers | These implementation/support APIs remain; their presence does not establish authenticated restore. |

The parent repository's `crates/morphir-mck` contains the Rust engine for
workspace integrations. This guide does not promise a separately published Rust
crate or a stable library API. The released CLI and its explicitly versioned
report are the cross-language integration boundary.

## Consumer cutover

TypeScript's `check:kit` and `check:conformance`, and Rust's `check:kit`,
use the pinned native release. Remove custom invocations of their temporary
`check:kit-legacy` and `check:conformance-legacy` tasks. Rust no longer downloads
the standalone TypeScript driver or reads its legacy report during CI.

In the parent, use `mck:run` or `mck:run-rust` instead of the retired
`mck:parity-rust` task. `mck:check` retains vocabulary authoring checks and
native schema validation. `mck:vocabulary-check` replaces the temporary
`mck:source-parity` task; protocol schemas are owned by the parent.

For npm consumers, `@finos/morphir-mck` retains the `mck-adapter-typescript`
implementation adapter and library helpers. The `mck` runner bin is removed from
future artifacts; there is no forwarding shim or implicit download. Migrate
runner imports using the table above. Independent package operations and the
existing wire contracts remain.

Future compiled releases contain the five TypeScript adapter executables and
the two npm tarballs, without standalone IR runner binaries or an embedded IR
kit. The installed MCK artifact gate runs the native CLI against its Node 24
adapter. The independent IR npm artifact gate retains Node 20 support.

Published historical package versions and release assets remain available.
The [migration record](https://github.com/finos/morphir/blob/main/spec/mck/migration.md)
records the final repository consumer audit and qualification evidence. An audit
of repository integrations cannot identify every external npm library consumer;
those consumers must migrate explicitly before upgrading across this removal.

## Package consumer cutover

Version `v0.4.0-beta.3` introduces `morphir mck package run` for the existing integrity
and resolution suites and has passed [six-target published qualification](https://github.com/finos/morphir/actions/runs/35656031505).
This command is not in `v0.4.0-beta.2`. Pin beta.3 and its archive checksum when
migrating a package consumer. The TypeScript installed npm artifact gate uses
that release against the actual Node 24 adapter; the parent runs the full
80 integrity and 78 resolution cases against both independent implementations.

Use the same explicit adapter with the native runner. For example, after building
`mck-adapter-rust`, a source checkout can run:

```sh
cargo run --locked --package morphir -- mck package run \
  --kit spec/package/mck --contract 0.1.0-draft.2 \
  --adapter ecosystem/morphir-rust/target/debug/mck-adapter-rust \
  --adapter-arg --suite --adapter-arg package \
  --adapter-arg --contract --adapter-arg 0.1.0-draft.2 \
  --report .dev/out/mck/package-resolution-rust.json
```

On Windows, use `mck-adapter-rust.exe`. Contract `0.1.0-draft.1` selects integrity;
`0.1.0-draft.2` selects resolution in both runner and adapter. All package cases
are required, and a skip is a failing run. Reports preserve the package contracts'
existing draft schemas, including capabilities and content hashes. The offline
HTML renderer currently accepts the consolidated IR report only.
