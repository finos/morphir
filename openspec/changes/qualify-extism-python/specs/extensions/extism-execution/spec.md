## Purpose

Allow users of the MoonBit Morphir CLI to invoke explicitly selected Extism extensions with verified bytes, bounded authority and documented protocol compatibility, qualified against the existing Python bundle.

## ADDED Requirements

### Requirement: Explicit adapter selection

The CLI SHALL execute Extism only through an explicit `extism-wasm` provider pin for `extension describe`, `extension compile` and `extension generate`. It SHALL preserve existing binding behavior and refuse unavailable hosts without selecting another engine or installed provider. (bead: morphir-ukvn.5.98)

#### Scenario: Explicit Python selection
- **WHEN** the user selects an Extism pin and qualified host for a Python operation
- **THEN** only the pinned WASM bytes run through the Extism adapter

#### Scenario: Different or unavailable binding
- **WHEN** an Extism bundle is supplied to `core-wasm-process`, or the selected Extism host is unavailable
- **THEN** the command fails explicitly without automatic fallback, download or installation

### Requirement: Verified immutable execution inputs

The CLI SHALL validate a versioned pin, host/runtime/helper digests, exact shared source revision, release descriptor digest and WASM digest before guest execution. It SHALL execute the verified bytes, reject unsafe artifact references and report identity/version mismatch without publishing results. (bead: morphir-ukvn.5.98)

#### Scenario: Byte replacement after verification
- **WHEN** a pinned path changes after its bytes were verified
- **THEN** execution uses the verified private snapshot or refuses, never the replacement bytes

#### Scenario: Invalid bundle identity
- **WHEN** a digest differs, a descriptor names an escaping path, or the guest disagrees with the pinned ID/version
- **THEN** invocation fails with a structured integrity or identity diagnostic and no successful output

### Requirement: Legacy MEP session compatibility

The Python route SHALL offer exactly MEP `0.1`, validate discovery and initialized capabilities, and use legacy compile/generate methods. It SHALL correlate response IDs, require valid response envelopes and complete lifecycle handling, and refuse rich-only peers or capability drift. (bead: morphir-ukvn.5.98)

#### Scenario: Existing Python guest
- **WHEN** the pinned guest describes Python frontend/backend capabilities and initializes with MEP `0.1`
- **THEN** the host invokes `morphir.frontend.compile` or `morphir.backend.generate` as requested

#### Scenario: Rich transport is requested
- **WHEN** the request requires MEP `0.2.0-draft.1`, compileModel, generateModel or a model-transport guarantee
- **THEN** the legacy route refuses before operation dispatch without relabeling or downgrading the request

#### Scenario: Invalid session response
- **WHEN** a response has the wrong ID, malformed JSON-RPC, changed capabilities or failed required shutdown
- **THEN** the CLI reports session failure and publishes no operation success

### Requirement: Explicit IR and codec boundary

Extism compile SHALL require `--ir-version` selecting `3`/`3.0.0` or `4`/`4.0.0` and emit validated plain `morphir-ir.json`. Generate SHALL validate the input header and selected version. The route SHALL refuse Ion, MorphirModel envelopes, unsupported versions and implicit migration or metadata loss. (bead: morphir-ukvn.5.98)

#### Scenario: Compile and generate each supported IR
- **WHEN** Python is compiled with each accepted version alias and the resulting JSON is generated back to Python
- **THEN** the output uses the corresponding validated v3 classic or v4 compact JSON representation and preserves structured guest diagnostics

#### Scenario: Envelope or unsupported input
- **WHEN** generation receives Ion bytes, a rich envelope, IR 1/2/3.1, mismatched headers or a version outside the Python bundle's declared support
- **THEN** it fails before guest operation dispatch with a compatibility diagnostic and no conversion

#### Scenario: Explicit format mismatch
- **WHEN** an Extism invocation asks for `--model-format ion`, or compilation omits the IR version
- **THEN** it fails with instructions identifying the required JSON/version selection

### Requirement: Capability claims do not grant authority

The host SHALL validate Python language, source-count, compile/generate flags, target and IR capabilities per operation. It SHALL distinguish recorded claims from live checks and authenticated provenance, and SHALL deny guest network, inherited environment and workspace filesystem access independently of claims. (bead: morphir-ukvn.5.98)

#### Scenario: Installed claims remain unchecked
- **WHEN** a WASM descriptor records unchecked capabilities
- **THEN** installation alone does not qualify execution, and invocation verifies live identity and capabilities without reporting authenticated authorship

#### Scenario: Missing multi-document claim
- **WHEN** a frontend omits `multiDocument` or declares it false and a compile request contains more than one source document
- **THEN** the host refuses before dispatch, including for the Python 0.4.1 bundle despite that bundle's observed multi-module implementation

#### Scenario: Unsupported operation or access
- **WHEN** a guest lacks the requested Python capability or attempts network, workspace reads or writes
- **THEN** the operation or access is denied and the CLI reports the applicable structured failure

### Requirement: Finite resource and lifecycle bounds

Every Extism session SHALL enforce finite WASM size, memory, fuel, call/session deadline, control input, reply, diagnostic, model depth/node and generated-output budgets. Cancellation or limit failure SHALL terminate and reap the supervised host before cleanup and SHALL publish no partial success. (bead: morphir-ukvn.5.98)

#### Scenario: Exact bound and one-over
- **WHEN** input, output, memory, fuel or time reaches its enforced bound or exceeds it
- **THEN** the documented boundary behavior holds and excess fails without unbounded copying or publication

#### Scenario: Cancellation during a guest call
- **WHEN** the user cancels during discovery, compilation or generation
- **THEN** the host group stops, owned storage is cleaned after reaping, and the CLI exits 130 with cancellation diagnostics

### Requirement: Transactional safe artifact publication

Compile and generate SHALL publish to a new output directory only after response, model and artifact validation and required writes succeed. Generation SHALL reject absolute, traversing, duplicate, symlink-escaping and platform-colliding paths and preserve guest-declared content encoding. (bead: morphir-ukvn.5.98)

#### Scenario: Unsafe or interrupted output
- **WHEN** a guest returns `../escape.py`, conflicting filenames, invalid binary encoding, or a required write fails
- **THEN** the destination remains unpublished and no success result is emitted

### Requirement: Structured command reporting

All affected commands SHALL declare `--json` through their owning parser, keep the MEP wire unchanged, and emit one finite `morphir/command-result` `0.1.0` document on stdout in JSON mode. Failures SHALL contain `error` and diagnostics instead of `result`; child logs SHALL use stderr. Existing binding schemas and syntax/status mappings SHALL remain compatible. (bead: morphir-ukvn.5.98)

#### Scenario: Result and diagnostic separation
- **WHEN** a Python compile succeeds with warning PY006 or fails with a Python diagnostic
- **THEN** stdout remains parseable as one result, diagnostic codes/severity/location survive, and child logs do not corrupt it

#### Scenario: Refusal statuses
- **WHEN** JSON validation refuses a pin, tuple, capability or resource request
- **THEN** the result has `state: "failed"`, `exitCode: 1`, stable error code/message and diagnostics, while cancellation retains 130 and syntax retains 2

#### Scenario: Help and self-tests
- **WHEN** `--json` is combined with help or the existing self-test controls
- **THEN** the owning command uses its documented help/self-test JSON schema and preserves the existing default-mode behavior

### Requirement: Real Python bundle qualification

Support claims SHALL require candidate-bound corrected Python bundle receipts with explicit multiDocument support for describe, two-module compile/generate/recompile in IR 3 and 4, Python API parity, source and packaged CLI entry points, offline replay, negative cases and cleanup. Receipts SHALL identify exact artifacts, host, dependencies, toolchain, platform and check definition. (bead: morphir-ukvn.5.98)

#### Scenario: Qualified cell
- **WHEN** the real bundle passes all required cases for a specific OS, architecture and CLI target
- **THEN** only that matrix cell can be documented as qualified with its receipt and digests

#### Scenario: Missing or stale evidence
- **WHEN** qualification is missing, skipped, failed or bound to different candidate bytes
- **THEN** that platform/target is not advertised as supported and cannot be promoted using another cell's evidence

### Requirement: Truthful interoperability documentation

Documentation SHALL distinguish Extism, core-WASM, native-process and Component Model adapters; MEP versions, envelope versions, IR versions and codecs; and planned versus qualified targets. It SHALL provide checked commands and link the Python `add-documentation-site` intent without making this adapter a prerequisite for that site's current compatibility guidance. (bead: morphir-ukvn.5.98)

#### Scenario: Copyable Python workflow
- **WHEN** a user follows the documented pinned describe/compile/generate example for a qualified cell
- **THEN** the example runs as written and states plain-JSON limits, refused rich inputs, digest/provenance meaning and the exact qualification scope
