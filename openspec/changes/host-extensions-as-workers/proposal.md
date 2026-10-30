# Proposal

## Why

The MoonBit CLI is becoming the main Morphir CLI, but it cannot run an extension by itself. Every route needs a
user-supplied pin and helper: `core-wasm-process` needs a pinned Node runtime and twelve pinned host modules,
`native-process` and `extism-wasm` need a Rust native-services helper built from a pinned finos/morphir checkout.
The session checks (handshake, tuple negotiation, reply order, shutdown) live as private functions in
`apps/morphir/cli/extension.mbt`, and they run only after the guest has exited, on a pipelined batch.

`acquire-extensions-from-repositories` (`morphir-ukvn.5.64.34`) installs extensions with no pins or helpers. It
needs a host that can probe a staged artifact, start an installed one from its recorded runtime, and give compile
and generate a session. That host does not exist yet. The Rust CLI that owns the helper's libraries is being
sunset.

## What Changes

- **One MoonBit session layer.** A new host package owns the MEP session as a pure state machine: describe,
  `initialize` and `initialized`, protocol and model-tuple negotiation, claim checks, request and result checks,
  limits, `shutdown` and `exit`. It runs over a channel abstraction that carries whole MEP messages, so the same
  code serves every kind of worker. It supports MEP `0.1` (`morphir.frontend.compile`, `morphir.backend.generate`)
  and MEP `0.2.0-draft.1` (`compileModel`, `generateModel`).
- **Process workers on native and Node.** The host starts a native executable that speaks Content-Length framed
  MEP on stdio. It owns the process tree (a new process group on Unix, a job object per worker on Windows), clears
  the environment, runs verified copies from a private directory, enforces deadlines, handles cancellation and
  confirms cleanup. The native target uses its own spawn stubs; the Node target uses `child_process`.
- **Any conformant extension.** The host holds no list of languages or extensions. Language, source file types and
  operations come from the extension's claims, so any extension that conforms to MEP and to a supported runtime and
  ABI profile runs with no host change, Elm and Gleam included. Qualification uses the shared conformance kits.
- **WASM workers.** The host classifies a WASM guest by its imports and exports against two ABI profiles: Extism
  (the full kernel, the Extism host functions, the four Morphir host functions of the extension SDK and a WASI
  preview 1 sandbox) and the existing `morphir_bytes_v1` ABI of the MoonBit portable guest. On native, the CLI starts its own executable in a worker mode that embeds a
  WASM engine, and that process is a process worker. On Node, the guest runs in a `worker_threads` worker. Memory,
  instruction budgets where the engine meters them, and deadlines are bounded.
- **A MoonBit Extism host, in its own repository.** No MoonBit Extism host exists. A new repository,
  `moonrockz/extism`, provides one for any MoonBit program: the Extism host API over a small WASM engine layer, a C
  engine built with Zig on native and `WebAssembly` on js. Its Extism kernel is written once in Zig and compiled to
  one WASM module, as upstream Extism does with its Rust kernel, so native, Node and browsers run the same kernel. It follows the canonical moonrockz setup (site, OpenSpec
  with `html-design`, `moonx` and `.mbx` scripts). This repository consumes its published package; the Morphir
  `morphir_bytes_v1` adapter stays here and uses the same engine layer.
- **Browser feasibility.** The same session code drives a WASM guest in a Web Worker through a message channel.
  This change proves it for the MoonBit and Python guests; product use in the Workbench can land later.
- **Host API for acquisition.** `probe`, `activate` with recorded claims, and session calls, keyed by a typed
  worker specification that the installed catalog can record. A host reports which worker kinds it can run, so
  acquisition can offer only WASM artifacts in the browser.
- **CLI commands.** `morphir extension describe|compile|generate` run on the new host. They keep their report
  schemas, exit codes, limits and diagnostics.
- **BREAKING**: explicit pins move to contract `0.2.0`, which names an artifact and its runtime, not a helper or a
  Node executable. `--extension-helper`, `--node` and pins with contract `0.1.0` or `0.1.0-draft.1` are refused
  with a migration message after the new host is qualified. The TypeScript extension helpers and the Extism and
  native-process roles of the Rust native-services helper are removed in the last group.

## Capabilities

### New Capabilities

- `extensions/worker-sessions`: the MEP session between the host and any worker: lifecycle, negotiation, claim
  checks, request and result checks, limits, failure classes, and the probe and activation operations that
  acquisition uses.
- `extensions/process-workers`: out-of-process workers: verified staging, environment, process tree ownership,
  deadlines, cancellation, stderr and cleanup on native and Node.
- `extensions/wasm-workers`: WASM guests: ABI classification, the two ABI adapters, resource bounds, the bundled
  native worker runtime, Node worker threads and browser Web Workers.
- `extensions/extension-invocation`: the `morphir extension describe|compile|generate` commands on the worker
  host: explicit worker pins, removed helper options, reports and exit status.

### Modified Capabilities

None. `openspec/specs/` holds no main specs yet. `qualify-extism-python` defines `extensions/extism-execution`
but is not archived; this change keeps its Python limits and refusals and replaces only its helper route.

## Beads

- **Tracked by**: `morphir-ukvn.5.64.36`
- **Related**:
  - `morphir-ukvn.5.64` (parent: the MoonBit CLI becomes the primary Morphir CLI)
  - `morphir-ukvn.5.64.34` (acquisition; its groups `.5` and `.7` wait on this epic)
  - `morphir-ukvn.5.64.30` and `morphir-ukvn.5.64.33` (installed native and portable qualification; they become
    consumers of this host)
  - `morphir-ukvn.5.98` (Extism Python qualification; its helper route is replaced, its limits are kept)
  - `morphir-ukvn.5.64.4` and `morphir-ukvn.5.64.6` (current native and Wasm routes, closed; this change replaces
    their helpers)
  - `morphir-ukvn.5.64.7` (connected daemon provider; a later channel kind, not part of this change)
  - `morphir-ukvn.5.99` (Moon-Lander adoption; hosting lifetimes and stop tokens this host uses)

## Impact

- **Code:** new packages under `pkgs/morphir-host` (session, channel, process and WASM workers), a worker mode in
  `apps/morphir`, `apps/morphir/cli/extension.mbt`, `extism.mbt` and `native_services.mbt`, and removal of
  `apps/morphir/build-provider/extension.mts`, `extism.mts` and the invocation role of `native-services.mts` and
  `apps/morphir/native-services/`.
- **Dependencies:** `moonrockz/extism` from Mooncakes, pinned to an exact version. Its native engine is C source
  built with the Zig already pinned in this repository, so no prebuilt engine or Rust toolchain is needed. No
  Extism SDK and no Rust host library. `moonbitlang/async` stays the async runtime; process-group spawn and Windows
  jobs are new C stubs, because `@process` does not provide them.
- **Packaging:** no new executable. The native CLI grows by the size of the engine; the npm package gains a worker
  thread entry module.
- **New repository:** `moonrockz/extism`, created only with the maintainer's approval.
- **Users:** extension commands no longer need Node, a helper or a Rust build. Explicit pins must be rewritten in
  contract `0.2.0`.
- **Other repositories:** `moonrockz/extism` (new). No change to the extension repositories is required. Running the Elm extension in a browser needs a new worker-module asset
  from finos/morphir-elm; that is a separate request, outside this change.
