# Shared MCK commands

The MoonBit CLI delegates MCK work to an explicitly pinned `finos/morphir`
executable. The canonical runner owns kit integrity, schemas, suites, diagnostics
and report validation. This bridge requires Node and the prebuilt executable.
It does not require Cargo or a Rust toolchain.

Supported hosts are Node on Linux, macOS and Windows, and native MoonBit on
Linux and macOS with the installed Node helper. Wasm, Wasm GC and native Windows
refuse these process effects. `conform` remains the separate local pipeline
comparison command.

## Select the backend

Provision the released executable separately, verify its archive against an
accepted SHA-256 pin, and save a runner pin such as:

```json
{
  "contractVersion": "0.1.0-draft.1",
  "runnerVersion": "0.4.0-beta.12",
  "executable": "/tools/morphir-backend/morphir",
  "sha256": "<64 lowercase hexadecimal characters for the executable bytes>",
  "sourceRevision": "<40 lowercase hexadecimal characters from the embedded kit>",
  "origin": "<release asset URL and verified archive digest>"
}
```

Replace the example placeholders with verified identities. `origin` records
provenance supplied by the caller; it does not authenticate a download. Store
the executable in a location other than the MoonBit launcher. The CLI never
searches PATH for the backend, downloads it, or installs an interpreter.

This bridge qualifies beta.12, and new pins should select it. A pin saved for
beta.10 stays accepted, so an existing setup keeps working. No other version is
accepted. The gate runs the real backend for beta.12 only; the beta.10 path has
controlled process tests. Each invocation verifies the executable hash, the exact
version that the pin selects and the embedded kit source revision before running
the canonical command, then verifies the hash again. The embedded corpus hash
and driver contract appear in structured receipts. A selected external kit has
its own revision and corpus hash, available through `kit status --kit`.

```sh
export MORPHIR_MCK_PIN=/tools/morphir-backend/runner.json
morphir mck kit status --json
morphir mck check /work/vendored-kit --json
```

The npm launcher selects its adjacent helper. A native executable or a directly
invoked compiled JS file needs `--mck-helper /installed/build-provider/mck.mjs` or
`MORPHIR_MCK_HELPER`. Native callers can select an absolute Node executable with
`--node /tools/node`.

## Commands and output

Wrapper controls go before the canonical command. Everything from that command
onward is forwarded as exact argv, including repeated options, empty strings and
hyphen-leading adapter arguments. An optional `--` separates the two parsers.

```sh
morphir mck --runner-pin /tools/runner.json kit vendor --source embedded --dest ./kit
morphir mck kit update --kit ./kit --source embedded
morphir mck check ./kit --json
morphir mck coverage --kit ./kit
morphir mck schema check --kit ./kit
morphir mck run --kit ./kit --adapter /tools/adapter --report report.json
morphir mck report check report.json allowed-failures.json --kit ./kit
morphir mck report render report.json --format html --output report.html
morphir mck report compare before.json after.json
morphir mck workbench --help
morphir mck package --help
morphir mck node-address --help
```

Canonical help describes each suite's contract versions and report format.
`report compare` compares the canonical IR/v1 record format. Workbench and
package reports retain their suite-specific checks. Do not feed them to the IR
comparator or interpret a transport receipt as a conformance certificate.
Executable MEP qualification remains pending with its upstream owner; it is
outside the suites qualified by this bridge.

By default, stdout, stderr and exit status are the canonical command's outputs.
For example, `morphir mck kit status --json` returns canonical kit JSON. Prefix
`--json` instead to request the MoonBit execution receipt:

```sh
morphir --json mck kit status --json
morphir --json-lines mck report compare before.json after.json
```

The receipt contains `state`, `exitCode`, the runner identity, embedded kit
identity, arguments and captured stdout/stderr. `completed` means the backend
finished; its `exitCode` and canonical report carry the verdict. Failed, skipped
and pending records are not converted into passing cases. JSON Lines wraps the
receipt in a `type: "mck"` record.

`coverage` reports vocabulary entries with no corresponding case. It emits one
`formatGap` line for each missing entry and returns exit 1 while gaps remain.
Pending cases count toward coverage. Members nested inside an entry-point
document are not seen, so complete vocabulary coverage does not establish
implementation conformance.

## Cancellation and bounds

`mck --timeout N` sets the whole backend operation budget, including identity
checks. The default is 180000 milliseconds and the maximum is 594000.
Options after the canonical command, such as `run --timeout`, retain their
canonical meaning. On POSIX, SIGINT requests cancellation. On every supported
host, `mck --cancel-file PATH` requests cancellation. Windows console Ctrl-C is
not qualified by this bridge.

The host supervises the backend and gives it up to five seconds to clean its own
adapter processes before reclaiming the owned process group. Unconfirmed cleanup
is an explicit failure. It publishes no partial stdout as a completed operation.
User cancellation returns 130, a deadline returns 124, refused setup returns 2,
and other bridge failures return 1. The canonical command's normal exit status
passes through unchanged. A report left at the caller-selected destination
after failure must pass the canonical checker before use.

The request is limited to 128 KiB and 1000 arguments, each at most 65536 string
units. Captured stdout and stderr together are limited to 1 MiB. Report files
written by the canonical runner retain that runner's limits.

## Qualification

`apps/morphir/fixtures/mck/release.json` pins the published `v0.4.0-beta.12`
archives by SHA-256 for each host, with the source and fixture revision
`d3154e9b9a54162a1409593972ac31c4a369f0ec`. Before the gate runs,
`moonx scripts/mck-release.mbtx apps/morphir/fixtures/mck/release.json DESTINATION`
downloads the archive for this host into a new destination and verifies its digest.
It also checks the executable version and the embedded kit revision, then fetches
only `spec/` at the fixture revision. It writes `runner.json` and `receipt.json`
and compiles no source. The CLI commands themselves never call it. The same
command also accepts a manifest saved for `v0.4.0-beta.10`.

The frozen IR and package transcripts are not stored in this repository. They are
the `spec/mck/baseline/` files of finos/morphir, and the fixture revision selects
them. To move them, change that revision and run the acquisition command again.

The headless CLI gate runs the shared backend with PATH empty through release
JS, native POSIX and an installed npm package. It compares inspection outputs
with direct canonical invocations, checks managed-kit edits and malformed
schemas, runs frozen independent IR and package transcripts, and exercises
node-address delegation. These replay fixtures qualify command delegation;
they do not certify a new implementation of those protocols.

Workbench draft.29 uses 32 actual model inspect/export operations, an independent
canonical report check, five tampered-report refusals and the one-MiB original
byte boundary. Real backend adapter processes verify file cancellation and
deadlines on every supported host, plus SIGINT on POSIX. Receipts, fixture hashes and reports are retained under
`.dev/headless-model-mck-evidence/` and uploaded by CI.
