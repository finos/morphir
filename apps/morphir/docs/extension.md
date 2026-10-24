# Pinned extension commands

`morphir extension` runs one MEP extension that you select with an explicit pin
file. Each invocation starts a fresh guest process, runs a single MEP session and
writes the returned model or generated library to a new directory. The CLI never
searches for extensions, installs them or substitutes another engine.

The only binding today is `core-wasm-process`. A saved core-Wasm guest
(`model.wasm` plus its binary Ion `manifest.ion`) runs inside the Node process
host in `pkgs/morphir-host/embedding`, which speaks Content-Length JSON-RPC on
stdio. This is the route qualified by issue #152. It is not a WebAssembly
Component Model binding. Component, native-process and Extism bindings are
refused with `extension.unsupported_binding`. Installed extension bundles and
repository selection are separate work.

## A complete example

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

## What each session does

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

## Output, exit status and cancellation

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
