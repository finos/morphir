# Spec Delta

## Purpose

Defines how the MoonBit CLI runs a WASM extension guest as a worker: which guest ABIs it accepts, what authority a
guest gets, its resource bounds, and where the guest runs on native, Node and browser hosts.

## ADDED Requirements

### Requirement: Any conformant extension runs
The host SHALL contain no code for a particular language, extension or publisher. Any WASM extension that conforms
to MEP and to one of the host's ABI profiles SHALL run with no host change. Language, operations and source file
types SHALL come from the extension's claims.

#### Scenario: New language frontend
- **WHEN** a conformant Extism extension claims a `frontend` for a language the host has never seen
- **THEN** describe, compile and generate run with no change to the host

#### Scenario: Extension built with another PDK
- **WHEN** a conformant extension is built with an Extism PDK that imports WASI preview 1
- **THEN** the host classifies it as `extism-kernel-v1` and runs it under the WASI sandbox rules

### Requirement: ABI classification
Before instantiation, the host SHALL read the module's imports and exports and classify it as exactly one ABI
profile: `extism-kernel-v1` or `morphir-bytes-v1`. An import outside the profile's import surface, or with another
signature, SHALL be refused with `extension.abi_unsupported`, naming that import.

#### Scenario: Python extension
- **WHEN** the host reads the Python extension `0.4.1` or `0.4.2` module
- **THEN** it classifies it as `extism-kernel-v1`

#### Scenario: Import from an unknown namespace
- **WHEN** a module imports `env.open_socket`
- **THEN** the host refuses it with `extension.abi_unsupported`, naming `env.open_socket`, and does not instantiate it

### Requirement: Extism import surface
For `extism-kernel-v1` the host SHALL accept imports of the Extism kernel and host functions (`extism:host/env`),
the Morphir host functions (`extism:host/user` `morphir_get_workspace_info`, `morphir_cache_ir`,
`morphir_get_cached_ir`, `morphir_log`) and WASI preview 1 (`wasi_snapshot_preview1`). The module SHALL export
`handle`.

#### Scenario: Module with Morphir host functions
- **WHEN** an extension built with the Morphir extension SDK imports `morphir_cache_ir` and `morphir_log`
- **THEN** the host links them and the module runs

#### Scenario: Module without `handle`
- **WHEN** a module imports only Extism kernel functions but exports no `handle`
- **THEN** the host refuses it with `extension.abi_unsupported`

### Requirement: Declared ABI must agree
When a worker specification or release descriptor declares an ABI, the host SHALL require the classified ABI to be
the same. A declaration SHALL NOT widen what the module may import.

#### Scenario: Wrong declaration
- **WHEN** a specification declares `morphir-bytes-v1` for an Extism module
- **THEN** the host refuses with `extension.abi_mismatch`

### Requirement: WASI sandbox
A guest that imports WASI preview 1 SHALL see no preopened directories, empty arguments and environment and an
empty stdin. Clocks and random bytes SHALL be available. Writes to stdout and stderr SHALL become bounded
diagnostics. Every other WASI function SHALL return an error code and SHALL NOT reach the host system.

#### Scenario: Guest opens a file
- **WHEN** a guest calls `path_open`
- **THEN** the call returns an error code, no file is opened and the session continues

#### Scenario: Guest prints
- **WHEN** a guest writes to stdout through `fd_write`
- **THEN** the text appears in the report's stderr tail and never in the MEP response stream

### Requirement: Host function policy
The Extism host functions SHALL behave as follows: `config_get` finds no value, `var_get` and `var_set` use a store
that lives only for the session, `log_*` become diagnostics, and `http_request` fails without network access. The
Morphir host functions SHALL see an empty private workspace and a cache that lives only for the session, and
`morphir_log` SHALL become diagnostics.

#### Scenario: Guest requests HTTP
- **WHEN** a guest calls `http_request`
- **THEN** the call fails, no connection is made and the report records the refused request

#### Scenario: IR cache between calls
- **WHEN** a guest stores IR with `morphir_cache_ir` during compile and reads it with `morphir_get_cached_ir` in the
  same session
- **THEN** it receives the stored value, and a new session starts with an empty cache

### Requirement: Extism kernel adapter
For `extism-kernel-v1` the host SHALL keep one instance per session, call `handle` once per request with the request
bytes as input, and read the response from the kernel output. It SHALL deliver no notification to the guest; `exit` SHALL
end the instance. A call that sets an error or traps SHALL fail the session.

#### Scenario: Python compile
- **WHEN** the host runs `initialize`, `morphir.frontend.compile` and `shutdown` on the Python guest
- **THEN** each request is one `handle` call on the same instance, and `initialized` and `exit` are not delivered

#### Scenario: Guest traps
- **WHEN** the guest traps during `handle`
- **THEN** the session fails with `extension.guest_trap` and the instance is discarded

### Requirement: Byte callback adapter
For `morphir-bytes-v1` the host SHALL provide exactly `input_len`, `input_byte` and `output_byte` and interpret the
`handle` result as today: a positive value is a response length, 0 is exit, -2 is a notification and -1 is a
failure. Requests and responses SHALL be valid UTF-8.

#### Scenario: MoonBit portable guest
- **WHEN** the host runs the MoonBit portable guest's `model.wasm`
- **THEN** compile and generate return the same envelopes as the native MoonBit guest

### Requirement: Memory ceiling
The host SHALL cap each guest's linear memory at 256 MiB, including a module that declares no maximum or a larger
one. A growth beyond the ceiling SHALL fail the call; it SHALL NOT be granted.

#### Scenario: Module without a maximum
- **WHEN** the Python module, which declares no memory maximum, tries to grow past 256 MiB
- **THEN** the call fails with `extension.memory_limit` and the session fails

### Requirement: Per-call budget
Each guest call SHALL have a deadline of 30 seconds for `extism-kernel-v1` and 10 seconds for `morphir-bytes-v1`,
inside the session deadline. Where the engine meters instructions, the host SHALL also apply a budget of
1,000,000,000 per call. The report SHALL state which bounds the host enforced.

#### Scenario: Runaway guest
- **WHEN** a guest loops forever inside `handle`
- **THEN** the call is stopped at its deadline, the outcome is deadline and the worker is gone

#### Scenario: Budget exhausted
- **WHEN** a guest runs more instructions than its per-call budget on an engine that meters
- **THEN** the call stops, the session fails with `extension.budget_exhausted` and the exit status is 1, not 124

#### Scenario: Host without metering
- **WHEN** the guest runs on a host whose engine has no instruction metering
- **THEN** the report lists the deadline and memory ceiling as enforced and the instruction budget as not enforced

### Requirement: Native WASM worker runtime
The native CLI SHALL run WASM guests in a separate process started from its own verified executable in a documented
worker mode, under the process worker rules. The native CLI SHALL need no Node, no Extism library supplied by the
user and no Rust helper.

#### Scenario: Python from the native CLI
- **WHEN** the native CLI compiles a Python file with the Python extension
- **THEN** the guest runs in a worker process of the CLI's own executable and that process's group is gone afterwards

#### Scenario: Worker mode output
- **WHEN** the worker mode runs
- **THEN** its stdout carries only MEP frames and its startup and diagnostic reports go to stderr

### Requirement: Node worker threads
The npm CLI SHALL run WASM guests in a Node worker thread. On deadline or cancellation the host SHALL terminate the
thread and wait until it has terminated before it returns.

#### Scenario: Cancel a WASM compile in the npm CLI
- **WHEN** the user presses Ctrl+C during a Python compile in the npm CLI
- **THEN** the worker thread is terminated, the outcome is cancelled and the exit status is 130

### Requirement: Browser Web Workers
A browser host SHALL run each WASM guest in its own Web Worker, connected through a message channel that carries
whole MEP messages. On deadline or cancellation it SHALL terminate that Web Worker.

#### Scenario: MoonBit and Python guests in a browser
- **WHEN** a page runs the browser host with the MoonBit portable guest and the Python extension
- **THEN** describe, compile and generate return the same results as on Node

#### Scenario: Runaway guest in a browser
- **WHEN** a guest in a Web Worker does not answer before its deadline
- **THEN** the Web Worker is terminated and the page stays responsive

### Requirement: Unsupported WASM features
The host SHALL refuse at load, with `extension.wasm_feature_unsupported`, a module that needs a WASM feature its
engine does not support, and SHALL name the feature when the engine reports it.

#### Scenario: Engine without a feature
- **WHEN** a module needs a feature the native engine was built without
- **THEN** the load fails with `extension.wasm_feature_unsupported` before any request
