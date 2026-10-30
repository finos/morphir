# Tasks

## 1. Worker session core and host API (morphir-ukvn.5.64.36.1)

- [x] 1.1 Create `pkgs/morphir-host/worker` with the domain types (`WorkerSpec`, `WorkerRuntime`, `WasmAbi`,
  `Claims`, `ProtocolLine`, `ModelTuple`, `Limits`, `Outcome`), the `Channel` and `Launcher` traits and an in-memory
  channel (CHAN-1); land it as its own pull request; verify it builds on native, js, wasm and wasm-gc with no new
  warnings
- [x] 1.2 Implement the pure session state machine for probe and operation sessions on both protocol lines (SES-1,
  SES-2); verify with the recorded transcripts in `tests/fixtures/mep-smithy` and new transcript tests for the
  "Interactive session order" and "Response checks" scenarios (early exit, failed initialize, wrong ID, unsolicited
  and second response, oversized response)
- [x] 1.3 Implement protocol and model-tuple negotiation with the smaller-limit rule and the request limits; verify
  the "Protocol lines", "Model tuple negotiation" and "Limits" scenarios as tests
- [x] 1.4 Implement claim checks at activation and the outcome classes with diagnostics and stderr tails; verify the
  "Activation against recorded claims", "Session calls" and "Outcome classes" scenarios as tests
- [x] 1.5 Implement the host API (`probe`, `activate`, `compile`, `generate`, `close`, `supports`) and its async
  driver with session deadlines and cancellation through Moon-Lander stop tokens; verify the "Describe probe",
  "Deadlines and cancellation" and "Host worker support" scenarios against fake workers on the in-memory channel
- [x] 1.6 Implement the `runtime` JSON decoder that pins and the installed catalog share; verify the "Worker
  specification" scenarios, including mixed runtimes, a missing digest and a platform mismatch
- [x] 1.7 Document the host API for acquisition in `pkgs/morphir-host/worker/README.mbt.md`; verify its examples run
  as documentation tests

## 2. Native process workers (morphir-ukvn.5.64.36.2)

- [ ] 2.1 Implement verified staging: no-follow read, hash of the bytes read, private copy, cleanup; verify the "Run
  verified copies" scenarios, including an artifact replaced during start
- [ ] 2.2 Add the Unix spawn stub (`posix_spawn` with a new process group, three pipes, no other descriptors, empty
  environment, private working directory) and the `killpg` stop with confirmation (PROC-1); verify on macOS and
  Linux with a fixture worker that starts a grandchild, for exit, deadline, cancellation and a worker that ignores
  `exit`
- [ ] 2.3 Add the Windows stub with one job object per worker, assigned before the worker runs, and job termination;
  verify with the same fixture worker in one deliberate Windows run that the build-master reviewed, with no new
  per-push job
- [ ] 2.4 Implement the framed stdio channel over `@mep.Decoder` and `encode_frame`, and the 64 KiB stderr tail;
  verify the "Framed stdio", "Bounded stderr" and "Host exit" scenarios as tests
- [ ] 2.5 Document the native process worker rules and their limits in the package README; verify the README matches
  the tested bounds

## 3. Node process workers (morphir-ukvn.5.64.36.3)

- [ ] 3.1 Implement the Node `child_process` adapter through `extern "js"`: detached spawn, piped stdio, stdout read
  through `@js_async.ReadableStream`, stdin writes (PROC-2); verify with the group 2 fixture worker on Node
- [ ] 3.2 Implement tree stop with `process.kill(-pid)` on Unix and `taskkill /T /F` on Windows, and wait for exit;
  verify deadline and cancellation tests on Node, and the Windows scenario in the group 2 deliberate run
- [ ] 3.3 Run one launcher conformance suite against the native and Node process launchers; verify both pass the same
  transcripts and fault cases
- [ ] 3.4 Document the Node process worker differences (tree termination on Windows) in the package README; verify
  against the conformance suite results

## 4. MoonBit Extism host in moonrockz/extism (morphir-ukvn.5.64.36.4)

- [ ] 4.1 After the maintainer approves, create `moonrockz/extism` with the canonical moonrockz setup (site app,
  OpenSpec with `html-design`, `moonx` and `.mbx` scripts, CI); verify its CI passes on the empty packages
- [ ] 4.2 Write its first OpenSpec change for the engine, kernel and plugin packages (EXT-1); verify
  `openspec validate --all --strict` passes there
- [ ] 4.3 Write the Extism kernel in Zig and compile it to one `wasm32-freestanding` module with the upstream export
  names and signatures and no externref global (EXT-3); verify with Zig tests and with a check that the embedded
  bytes match a fresh build
- [ ] 4.4 Build the engine package: WAMR fast interpreter built with Zig for every CLI platform (including the Windows
  MSVC link), a js engine over `WebAssembly`, kernel binding per engine, memory ceiling, instruction budget,
  interruption and named feature errors (EXT-2, EXT-3); then run the EXT-2 gate: the Python `0.4.2` fixture compiles
  within the 30-second call deadline with metering on the slowest qualified platform; record timings for the
  forwarding binding and multi-module linking as a comment on this bead, and switch to the Wasmtime C API only if
  the gate fails
- [ ] 4.5 Build the `wasi` package (WASI preview 1 sandbox) and the plugin package with the Extism host functions, an
  embedder policy for configuration, variables, logging and HTTP, and host functions the embedder registers in any
  namespace; verify Python `0.4.1` and `0.4.2` answer `morphir_extension_info` and a `describe` request through
  `handle` with identical results on native, Node and a browser, and verify a WASI-importing fixture plugin built
  with an upstream Extism PDK runs under the sandbox
- [ ] 4.6 Publish an exact version to Mooncakes; verify a fresh module can pin and build it on native and js

## 5. WASM workers (morphir-ukvn.5.64.36.5)

- [ ] 5.1 Implement the import and export reader, the profile classifier over the import surfaces of WASM-1 and
  WASM-4, and the memory-maximum rewrite; verify the "Any conformant extension runs", "ABI classification", "Extism
  import surface" and "Declared ABI must agree" scenarios with the Python modules, the portable MoonBit guest and
  crafted modules
- [ ] 5.2 Implement the `morphir-bytes-v1` adapter over the engine package; verify the "Byte callback adapter"
  scenario: the portable guest returns the same envelopes as the native guest
- [ ] 5.3 Implement the Extism adapter over the plugin API with the WASM-4 policy and the four Morphir host functions
  registered by this repository; verify the "Extism kernel adapter", "WASI sandbox" and "Host function policy"
  scenarios with the Python guest and crafted guests, including undelivered notifications and a trap
- [ ] 5.4 Add the `morphir extension worker` mode with the build identity check and a `--json` startup report on
  stderr, and the native WASM launcher over the process launcher (WASM-2); verify the "Native WASM worker runtime",
  "Memory ceiling", "Per-call budget" and "Unsupported WASM features" scenarios, and record the CLI binary size
  before and after in the pull request
- [ ] 5.5 Add the Node worker-thread launcher and its entry module built from MoonBit, shipped in the npm package
  (WASM-3); verify the "Node worker threads" scenario and that the npm package runs it from an unpacked tarball

## 6. Extension commands on the worker host (morphir-ukvn.5.64.36.6)

- [ ] 6.1 Decode pin contract `0.2.0` and refuse retired pins and options (CLI-1); verify the "Worker pin contract"
  and "Retired pins and options" scenarios
- [ ] 6.2 Switch `extension describe|compile|generate` to the host API, take the protocol line from the describe
  answer, and select sources and operations from the claims, removing the Python-specific source handling of
  `extism.mbt`; verify the "No helper, Node or service pin", "Compile and generate options" and "Sources and
  operations from claims" scenarios and the updated CLI unit tests
- [ ] 6.3 Write the `morphir/command-result` report and the exit table in human and JSON mode (CLI-2); verify the
  "JSON report" and "Exit status" scenarios, including stdout parsing while the guest writes to stderr
- [ ] 6.4 Keep safe publication after the worker tree has stopped; verify the "Safe publication" scenario
- [ ] 6.5 Rewrite `apps/morphir/docs/extension.md` for the worker host: pins, migration from old pins, limits,
  enforced bounds per host and the platform table; verify the documented commands run as written

## 7. Qualify the published extensions on the worker host (morphir-ukvn.5.64.36.7)

- [ ] 7.1 Qualify the Elm extension `v0.4.1` executables from the native and npm CLI on macOS arm64 and Linux x64;
  verify compile of the Elm fixture and the absence of Node from the native run's environment
- [ ] 7.2 Rewrite `test:cli-extism-python` for `0.2.0` pins and qualify Python `0.4.1` (single document and the
  multi-document refusal) and `0.4.2` (IR 3 and 4 compile and generate, consumer check) from both CLIs; verify the
  receipts
- [ ] 7.3 Rewrite `test:portable-mep-cli` and `test:cli-native-prerequisites` for the worker host and qualify the
  MoonBit native and portable guests with the shared MCK kit; verify the kit's expected output
- [ ] 7.4 Add a conformance fixture guest built with `morphir-extension-sdk` at a pinned revision, importing WASI and
  the Morphir host functions, stored with its source and build receipt under `apps/morphir/fixtures`; run the shared
  MEP conformance kit against it and against the MoonBit guest from both CLIs; verify the "Conformance, not a list of
  extensions" scenarios with no host change made for that guest
- [ ] 7.5 Run one Windows x64 qualification of tasks 7.1 to 7.4 after a build-master review; verify the receipts and
  add a `Tested-on:` trailer
- [ ] 7.6 Record every receipt with its exact artifact digests as a comment on this bead; verify each receipt names
  its platform, CLI build and guest digest

## 8. Browser Web Worker feasibility (morphir-ukvn.5.64.36.8)

- [ ] 8.1 Implement the browser launcher and the message-port channel (BRW-1); verify with unit tests in a js test
  run
- [ ] 8.2 Add a Playwright proof page with the MoonBit portable guest and the Python extension; verify the "Browser Web
  Workers" scenarios, including a runaway guest and a refused process artifact
- [ ] 8.3 Write the feasibility report as an HTML document stored in this bead's design; verify it records measured
  results separately from proposals
- [ ] 8.4 Create follow-up beads for Workbench adoption and for an Elm worker-module asset request to
  finos/morphir-elm; verify both link to this bead

## 9. Retire the helper routes (morphir-ukvn.5.64.36.9)

- [ ] 9.1 Remove `apps/morphir/build-provider/extension.mts`, `extism.mts`, the invocation role of
  `native-services.mts` and the Native and Extism operations of `apps/morphir/native-services/`, and the npm
  launcher's helper default (MIG-1); verify the CLI, npm package and qualification tasks build and pass
- [ ] 9.2 Remove the MoonBit code of the old bindings; verify no new warnings in the touched modules
- [ ] 9.3 Add the breaking-change notes and update the remaining documentation; verify the docs build and link check
  pass

## Workflow follow-up

- Archive the change after the last group's pull request merges, following the archive guidance in
  `openspec/config.yaml`.
