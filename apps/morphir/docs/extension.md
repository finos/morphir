# Pinned extension commands

`morphir extension describe|compile|generate` invokes a provider selected by an
explicit pin. Each operation writes to a new output directory. Repository and
bundle commands below manage local installations separately. Invocation never
silently substitutes an installed provider or another engine.

The portable `core-wasm-process` binding runs a saved core-Wasm guest
(`model.wasm` plus its binary Ion `manifest.ion`) runs inside the Node process
host in `pkgs/morphir-host/embedding`, which speaks Content-Length JSON-RPC on
stdio. This is the route qualified by issue #152. It is not a WebAssembly
Component Model binding. The explicit `native-process` route delegates to the
shared Rust host as described below. Components and Extism require separately
qualified adapters.

## A portable example

Package the MoonBit extension, then write a pin over the bytes you built:

```sh
mise run package:mep-extension
mise exec -- bun run --cwd apps/morphir build
```

```json
{
  "contractVersion": "0.1.0-draft.1",
  "binding": "core-wasm-process",
  "executionProfile": {
    "id": "morphir/mep-bytes-v1/v1-draft",
    "sha256": "6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6"
  },
  "runtime": {
    "name": "node",
    "version": "v24.22.1",
    "executable": "/tools/node-24.22.1/bin/node",
    "sha256": "<SHA-256 of that executable>"
  },
  "host": {
    "root": "/work/morphir-moonbit/pkgs/morphir-host/embedding",
    "modules": { "node-mep-cli.mjs": "<SHA-256>", "...": "one entry per host module" }
  },
  "artifact": {
    "directory": "/work/morphir-moonbit/.dev/portable-mep/extension",
    "wasmSha256": "<SHA-256 of model.wasm>",
    "manifestSha256": "<SHA-256 of manifest.ion>"
  },
  "origin": "where these bytes came from"
}
```

`host.modules` must list exactly the twelve modules the Node host loads:
`node-mep-cli.mjs`, `node-mep-stdio.mjs`, `node-mep-adapter.mjs`,
`node-mep-worker.mjs`, `mep-adapter.mjs`, `mep-frames.mjs`, `wasm-memory.mjs`,
`node-artifacts.mjs`, `artifacts.mjs`, `assembly.mjs`, `index.mjs` and
`dist/bridge.mjs`. Rebuilding the embedding package can change these bytes even
when the source does not, because the bundler writes a build-specific debug ID.
Write the pin after the last build. `scripts/portable-mep-cli.mbtx` shows how.

Then compile a MoonBit source file and generate a library from the result:

```sh
export MORPHIR_EXTENSION_PIN=/work/pin.json
morphir extension describe
morphir extension compile src/main.mbt --package my/bool --output model
morphir extension generate model/model-envelope.json --output generated
```

`compile` writes `model/model-envelope.json`, the MorphirModel envelope exactly as
the guest returned it, and `model/model.ionb`, its decoded payload. The CLI checks
the payload's length and SHA-256 before publishing either file. `generate` sends
that envelope back unchanged and writes every returned artifact, including the
guest's retention sidecars `mep/source-model.ionb` and `mep/source-envelope.json`.

The npm launcher selects its adjacent helper. A native executable needs
`--extension-helper /installed/build-provider/extension.mjs` (or
`MORPHIR_EXTENSION_HELPER`) and can name the Node that runs the helper with
`--node`. The guest always runs under the pinned runtime, not under `--node`.

## What each portable session does

The CLI builds the whole session before it starts a process: `describe`,
`initialize` with exactly one model tuple, the operation, `shutdown` and the
`exit` notification. `describe` alone sends `describe` and `exit`. The helper
reads the runtime, every host module and both artifact files through no-follow
descriptors. It hashes each one and copies the bytes it hashed into a private
temporary directory. It checks the SHA-256 against the pin, confirms the copied
runtime reports `v24.22.1`, and starts the guest from those copies. Replacing a
pinned file after verification cannot change what runs. The guest gets an empty
environment and an empty working directory. The copies are removed after its
process group has exited.

The guest serves the pipelined requests in order. Afterwards the CLI decodes the
frames and requires one response per request, in order, with matching IDs. A guest
that exits early leaves an `extension.incomplete_session` failure, never a partial
success. Initialization must agree on MEP `0.2.0-draft.1` and return the offered
tuple. An empty intersection is `extension.tuple_unavailable`.

Ion is the default: `--model-format ion` selects `morphir-model` with
`ion-binary`, and `--model-format json` selects `morphir-ir` with `morphir-json`.
There is no fallback between them. The MoonBit frontend refuses JSON compilation
that would drop source and naming provenance with `data.lossy_conversion`.
`generate` takes the tuple from the envelope and refuses anything other than those
two pairs, envelope `0.1.0-draft.1` and IR `4.0.0`, before a process starts.

The CLI offers 2 MiB decoded and 2,796,204 encoded model bytes, depth 128 and
100,000 nodes. The guest uses the lower of its own limits and these. The framed
request must fit in 4 MiB. Guest stdout is capped at 16 MiB and its stderr at
64 KiB. The Node host keeps its own limits: 256 MiB Wasm memory, a 10-second worker
deadline per call and only the three `morphir_bytes_v1` byte callbacks as imports.

Source files enter the request with a clean relative path, or only their file
name when the path is absolute or contains `..`. The context digest is the SHA-256
of the package name and options for `compile`, and of the target and model
identity for `generate`.

## Portable output, exit status and cancellation

Human output prints a summary on stdout and diagnostics on stderr. `--json` prints
one report, and `--json-lines` wraps it in `{"type":"extension","data":...}`. The
report has the profile `morphir/cli/extension-command`, contract
`0.1.0-draft.1`, the operation, `state`, `exitCode`, the verified pin, the guest's
`extension` identity, the negotiated tuple and limits, the guest's `result` with
its diagnostics, the published files with their sizes and SHA-256, lifecycle facts
and the guest's stderr.

| Exit | State | Meaning |
| --- | --- | --- |
| 0 | `completed` | The operation succeeded and output was published. |
| 1 | `completed` | The guest answered with `success: false`, for example source errors or a lossy JSON request. |
| 1 | `failed` | The guest rejected the operation with a JSON-RPC error (for example `digest_mismatch`), exited early, answered out of order or wrote files. |
| 2 | `refused` | A pin, identity, runtime version, negotiation or local input check failed. Identity refusals start no guest. |
| 124 | `failed` | The `--timeout` deadline expired. The default is 60000 ms and the maximum 594000 ms. |
| 130 | `cancelled` | SIGINT or `--cancel-file PATH` stopped the session. |

MEP wire cancellation is not supported, and the report says so
(`wireCancellation: false`). Cancellation and deadlines terminate the guest's
whole process group, and the helper confirms the group has exited before the
CLI returns. Output is written to `<output>.morphir-partial` and renamed into
place without replacement, so a failure never leaves a partial output directory.
An existing output path is refused. The command writes no log files.

Supported hosts are the npm launcher on Node and native MoonBit on Linux and
macOS. Wasm, Wasm GC and native Windows print help but refuse dispatch with
`extension.runtime_unavailable`.

## Qualification

```sh
MORPHIR_MEP_KIT=/path/to/finos/morphir/spec/mep/mck/guest-moonbit-bool.json \
MORPHIR_MEP_KIT_SHA256=<kit SHA-256> \
mise run test:portable-mep-cli
```

The script builds the embedding host, the npm CLI and the native CLI, pins the
current bytes and runs the real command on both CLI builds. It compiles the shared
kit's Boolean source and generates from the result. Then it builds the kit's own
consumer against the returned library and requires the kit's expected stdout. It
also generates from the kit's plain Morphir JSON and requires the kit's expected
artifacts byte for byte. It covers lossy JSON refusal, malformed source, a retired
source profile, a tampered payload digest, an unsupported tuple, an existing
output, a wrong Wasm digest, an unsupported binding, a cancel file and a deadline.
Every invocation runs with its own `TMPDIR`, which must be empty afterwards.
Evidence goes to `MORPHIR_MEP_CLI_EVIDENCE`, default `.dev/portable-mep-cli`, which
must not exist yet.

`scripts/test-extension-provider.ts` runs in routine CLI tests with a stand-in
pinned runtime. It checks identity refusal before launch, a runtime version
mismatch, separate stdout and stderr, guest file writes, execution of verified
copies when pinned paths change during a run, process-group cleanup after a deadline or cancellation, and the stderr
limit.

## Explicit native processes

Build the adapter against the pinned shared checkout using Rust 1.98.0. The
MoonBit build script verifies the shared revision and library tree, uses the
tracked Cargo lock and writes `.dev/native-services/host-pin.json`:

```sh
moon run scripts/native-services.mbtx -- --shared /path/to/finos/morphir --json
```

The adapter links the shared `morphir-host`, `morphir-host-native`,
`morphir-extension-sdk` and `morphir-distribution` libraries at finos/morphir
`ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409`. It does not invoke the Rust product CLI
or implement a checker. Copy the generated host pin into this explicit provider pin:

```json
{
  "contractVersion": "0.1.0",
  "binding": "native-process",
  "host": {
    "executable": "/work/adapter",
    "sha256": "<adapter SHA-256>",
    "sourceRevision": "ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409"
  },
  "artifact": {
    "executable": "/work/morphir-moonbit",
    "sha256": "<native guest SHA-256>",
    "extensionId": "morphir-moonbit",
    "version": "0.1.0",
    "args": []
  },
  "origin": "description of the explicitly selected local build"
}
```

Use the same describe/compile/generate arguments as above, with
`--extension-helper /work/apps/morphir/build-provider/native-services.mjs` and
`--extension-pin native.json`. The native helper is always explicit, including
from the npm launcher. Pin after building; rebuilding either executable invalidates
its old digest. Optional native `artifact.args` is an opaque array, forwarded
unchanged, including empty strings and delimiters.

For an operation, the shared host first describes an immutable executable copy
and closes that probe. It then initializes a new copy of the same verified bytes,
holding identity, version and capabilities to the description. The shared SDK
owns immutable tuple negotiation, request/result checks, framing and shutdown.
Compile and generate negotiate separate tuples. Payload bytes remain exact; the
retained envelope round-trips to the generator's source-envelope sidecar without
changing bytes. Optional claims are assertions, not authenticated authorship.

Native execution has no enforced sandbox. The adapter and provider inherit no
user environment. The helper owns a private temporary root and the entire process
group, terminates it on cancellation or deadline, and cleans its storage after
the group stops. Wire cancellation remains unsupported. Guest diagnostics use
stderr. Requests are limited to 4 MiB, helper replies to 16 MiB, and shared MEP
frames to the canonical host's 64 MiB limit; model negotiation has the smaller
limits shown in the report. Explicit executables are limited to 128 MiB.
Native commands record bounded cleanup observations through the existing telemetry
sink at `.morphir/logs/execution.ionb`. `--log-file` and `--log-format` honor explicit
paths and existing formats, including JSON Lines. Portable extension invocation
keeps its existing no-file-logging behavior and explicitly refuses these native
log controls.

Native JSON results use `morphir/command-result` version `0.1.0`, with `command`,
`state`, `exitCode` and `diagnostics`. Success has `result.binding`, `result.session`,
output digest receipts and lifecycle facts. Failure has `error: {code, message}`
instead of `result`; expected validation failures exit 1, cancellation exits 130
and parser syntax retains exit 2. Human mode currently prints the same structured
report. Help keeps the existing CLI help schema. The portable success schema is
unchanged. Wasm/Wasm GC and native Windows refuse execution explicitly; their help
remains available. This source acceptance is scoped to macOS arm64 and does not
claim installed or other-platform qualification.

## Controlled local repositories

These commands require `--services-pin host-pin.json` and
`--services-helper /work/apps/morphir/build-provider/native-services.mjs`.
Use `--home /isolated/morphir-home` to isolate state. Otherwise `MORPHIR_HOME`, then
the user's `.morphir` directory, supplies the home. Canonical directory layouts,
release descriptors, digests, locks, catalogs and installation transactions belong
to the shared distribution library.

```sh
morphir extension repository init /work/local-repository
morphir extension repository add local --directory /work/local-repository
morphir extension bundle --executable /work/guest --sha256 <SHA-256> --extension-id morphir-moonbit --short-id moonbit --version 0.1.0 --platform aarch64-apple-darwin --output bundle
morphir extension repository publish bundle --repository local
morphir extension search moonbit
morphir extension install morphir-moonbit --repository local --version 0.1.0
morphir extension list
morphir extension update morphir-moonbit --repository local --version 0.1.1
morphir extension uninstall morphir-moonbit
```

The example omits the common explicit service controls for readability. Repository
`list`, `inspect <name>`, `enable <name>`, `disable <name>`, `verify <name>` and
`remove <name>` complete the lifecycle. Disable excludes a repository from search,
resolution and publication. Bundle accepts an already-built native executable,
probes its declared identity/version and validates the canonical descriptor before
publication. Its current bounded byte bridge accepts artifacts up to 11 MiB and
requires the probing host's exact Rust target triple. Larger bundles, remote
repositories, channels, Wasm installation and cross-platform probing are outside
this adapter. Unsupported syntax is refused, never ignored.

Publish and fresh install use canonical describe probes. Update probes an isolated
materialization of the selected digest before the shared replacement installer
rehashes that digest and atomically replaces state. Its canonical lock retains the
repository claim record; the command also returns its separate probe evidence.
Corrupt bundles, failed probes and corrupt/disabled update selections leave the
previous active installation intact. `extension list` revalidates installed bytes
offline without executing them or reopening the repository. Uninstall removes
active state and retains the shared content-addressed cache. No signed registry or
authenticated publisher chain is required for this explicit local workflow.

Every lifecycle command accepts `--json` and uses the native finite-result schema
above. Diagnostics and child logs go to stderr; successful output appears only
after required writes. These commands do not automatically join installed
selection to invocation. That downstream acceptance remains morphir-ukvn.5.64.30.

Run the focused real native source-CLI path with:

```sh
mise run test:cli-native-prerequisites -- --shared /path/to/finos/morphir --json
```

It freezes separately built native guests and fault peers, tests embedded Boolean
and Elm compilation, compile/retain/generate/consumer execution, malformed/oversized
frames, tuple and context refusal, crashes, diagnostics, deadlines, cancellation,
shutdown and cleanup. It also tests local publication/install, a real version
update, corrupt and disabled selections, offline replay and removal in a fresh
home. It reruns the existing portable provider tests and CLI unit suite. The task
passes the produced CLI, adapter and guest paths explicitly to each test process,
binding its receipts to tested artifacts even when the caller has artifact
override variables set. Evidence and host pins stay under `.dev/native-services`;
no installed matrix, new CI job,
release or default switch is performed.
