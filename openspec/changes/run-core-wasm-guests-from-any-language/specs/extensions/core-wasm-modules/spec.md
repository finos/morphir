# Spec Delta

## Purpose

Defines how the worker host pins, checks and runs a WASM module guest that was not assembled by MoonBit, through a
contract `0.2.0` pin, its release descriptor and the execution profile, instead of the MoonBit artifact manifest.

## ADDED Requirements

### Requirement: Contract 0.2.0 pin for a WASM module
A WASM module SHALL be pinned with a contract `0.2.0` pin: `artifact` (`{path, sha256}`), `runtime` (`{kind:
"wasm"}` with an optional `abi`), `origin` and a `descriptor` (`{path, sha256}`), which is optional except as
"Descriptor for a morphir-bytes-v1 pin" says. It SHALL need no `manifest.ion`. Another member SHALL be refused with
`extension.pin_invalid`, exit 2, and the message SHALL name it. A pin with contract `0.1.0` or `0.1.0-draft.1` SHALL
be refused with `extension.pin_retired`, exit 2.
#### Scenario: Gleam module pin
- **WHEN** a pin names `morphir-gleam-0.4.0.wasm` with its SHA-256, the runtime `{kind: "wasm", abi:
  "morphir-bytes-v1"}` and the bundle's descriptor
- **THEN** the CLI accepts the pin and runs the module with no `manifest.ion`

#### Scenario: Pin with a manifest digest
- **WHEN** a contract `0.2.0` pin also has `manifestSha256`
- **THEN** the command exits 2 with `extension.pin_invalid` and the message names `manifestSha256`

#### Scenario: Retired module form pin
- **WHEN** a user runs a `core-wasm-process` pin with contract `0.1.0-draft.1`
- **THEN** the command exits 2 with `extension.pin_retired`, the message points to the migration, and no worker
  starts

### Requirement: Descriptor for a morphir-bytes-v1 pin
An installed pin for a `morphir-bytes-v1` module SHALL name the release descriptor; without it, the command
SHALL exit 2 with `extension.pin_invalid` before the guest starts. A local pin (`--extension-pin` or
`MORPHIR_EXTENSION_PIN`) MAY omit it. The host SHALL then run the module and add a `warning` diagnostic,
`extension.descriptor_checks_skipped`, that names the skipped checks.

#### Scenario: Installed pin without a descriptor
- **WHEN** the CLI runs an installed `morphir-bytes-v1` extension whose pin names no descriptor
- **THEN** the command exits 2 with `extension.pin_invalid`, the message names `descriptor`, and no guest starts

#### Scenario: Local pin without a descriptor
- **WHEN** a user compiles with a local pin for a `morphir-bytes-v1` module that names no descriptor
- **THEN** the compile runs and exits 0, stderr has one `extension.descriptor_checks_skipped` line, and the report
  `diagnostics` has that `warning` diagnostic, which names the digest against the published release, the critical
  `runtime` and `executionProfile` members, and the published claims

#### Scenario: Local pin with a descriptor
- **WHEN** a user compiles with a local pin for a `morphir-bytes-v1` module that names its descriptor
- **THEN** the host runs every descriptor check of this capability, and the command has no
  `extension.descriptor_checks_skipped` diagnostic

### Requirement: Descriptor integrity
When the pin names a descriptor, the CLI SHALL read it before any worker starts, through a bounded read of at most
1 MiB, and SHALL require its SHA-256 to equal the pin's `descriptor.sha256` before it decodes it. A mismatch SHALL
exit 2 with `extension.digest_mismatch`, and no guest SHALL start.

#### Scenario: Changed descriptor
- **WHEN** one byte of `morphir-gleam-0.4.0.release.json` changes after the pin was written
- **THEN** the command exits 2 with `extension.digest_mismatch` and no guest starts

### Requirement: Descriptor content
The descriptor SHALL have `schemaVersion` `2.0.0-draft.2`, and its `extensionId` and `version` SHALL equal the
live claims. Exactly one artifact SHALL have the pin's `artifact.sha256`, with a `filename` that has no path
separator. If its `runtime` is `core-wasm`, the pin's `abi` SHALL be absent or `morphir-bytes-v1`, and its
`executionProfile` SHALL equal the host's profile. Otherwise the command SHALL exit 2 with
`extension.descriptor_invalid`, and no operation session SHALL start.

#### Scenario: Gleam 0.4.0 descriptor
- **WHEN** the pin names the `morphir-gleam` 0.4.0 module and its descriptor
- **THEN** the CLI selects the artifact `morphir-gleam-0.4.0.wasm` and accepts the descriptor

#### Scenario: Wrong execution profile
- **WHEN** the descriptor artifact names an execution profile digest other than the host's
- **THEN** the command exits 2 with `extension.descriptor_invalid` and no operation session starts

#### Scenario: Descriptor of another extension
- **WHEN** the descriptor has `extensionId` `morphir-elm` and the live claims name `morphir-gleam`
- **THEN** the command exits 2 with `extension.descriptor_invalid` and no operation session starts

### Requirement: Critical members
Every name in the selected artifact's `critical` list SHALL be a member that the host understands and checks. The
host SHALL understand `runtime` and `executionProfile`. An unknown critical name SHALL be refused with
`extension.descriptor_invalid`, and the message SHALL name it.

#### Scenario: Unknown critical member
- **WHEN** the artifact has `critical: ["runtime", "executionProfile", "memory64"]`
- **THEN** the command exits 2 with `extension.descriptor_invalid` and names `memory64`

### Requirement: Verified staging
The worker host SHALL read the module bytes, SHALL refuse a module larger than 512 MiB before it hashes it, SHALL
check the SHA-256 of the bytes that it read against the pin's `artifact.sha256`, and SHALL compile and run only
those bytes. A digest mismatch SHALL exit 2 with `extension.digest_mismatch`, and no guest SHALL start.

#### Scenario: Module replaced after the check
- **WHEN** the module file is replaced after the worker host read and hashed it
- **THEN** the guest runs the bytes that the host hashed and the run is not changed

#### Scenario: Module digest mismatch
- **WHEN** the module bytes do not match the pin's `artifact.sha256`
- **THEN** the command exits 2 with `extension.digest_mismatch` and no guest starts

#### Scenario: Module above the artifact bound
- **WHEN** the module is larger than 512 MiB
- **THEN** the worker host refuses it before it hashes it, and no guest starts

### Requirement: Execution profile structure
Before it instantiates a WASM module, the MoonBit worker host SHALL check it. A `morphir-bytes-v1` module SHALL
import only `morphir_bytes_v1.input_len: () -> i32`, `input_byte: (i32) -> i32` and `output_byte: (i32) -> ()`,
and SHALL export `handle: () -> i32`. Another import or signature SHALL be refused with
`extension.abi_unsupported`, and the message SHALL name it. A pin `abi` that differs from the checked profile
SHALL be refused with `extension.abi_mismatch`.

#### Scenario: Gleam module
- **WHEN** the worker host checks `morphir-gleam-0.4.0.wasm`
- **THEN** the check passes and the guest is instantiated

#### Scenario: Extra import
- **WHEN** a crafted module has the three byte imports and also imports `extism:host/env.input_length`
- **THEN** the run fails with `extension.abi_unsupported`, the message names that import, and the guest is not
  instantiated

#### Scenario: Wrong signature
- **WHEN** a crafted module imports `morphir_bytes_v1.output_byte` with the type `(i64) -> ()`
- **THEN** the run fails before instantiation with `extension.abi_unsupported` and names
  `morphir_bytes_v1.output_byte`

### Requirement: Memory ceiling of a WASM module
The worker host SHALL refuse a shared, 64-bit or second memory before instantiation. It SHALL run a memory whose
maximum is above 4,096 pages, or that has no maximum, with a maximum of 4,096 pages, and SHALL refuse an initial
memory above 4,096 pages with `extension.memory_limit`.

#### Scenario: Larger memory maximum
- **WHEN** a crafted module declares a memory with a maximum of 65,536 pages
- **THEN** the worker host runs it with a maximum of 4,096 pages

#### Scenario: Initial memory above the ceiling
- **WHEN** a crafted module declares an initial memory of 5,000 pages
- **THEN** the run fails with `extension.memory_limit` and the guest is not instantiated

### Requirement: Descriptor claims equal live claims
When the pin names a descriptor, the claims of the selected descriptor artifact SHALL decode to the same claims as
the live describe answer of the probe, including the extension ID and the version. A difference SHALL exit 2 with
`extension.claims_mismatch`, and no operation session SHALL start.

#### Scenario: Descriptor claims a different language
- **WHEN** a descriptor, written again with a correct digest, claims language `elm` but the guest claims `gleam`
- **THEN** the command exits 2 with `extension.claims_mismatch`

### Requirement: Claims are not authority
Descriptor and live claims SHALL select requests and SHALL be compared. They SHALL NOT widen the imports, memory,
time or file access of a guest. The report SHALL show the descriptor `gitCommit` as a claim, not as verified
origin.

#### Scenario: Report origin
- **WHEN** a module form compile succeeds in JSON mode
- **THEN** the report shows the descriptor digest, the module digest and `gitCommit` under the report's `worker`
  object, with `origin: "claimed"`

### Requirement: Same session behavior for every worker kind
After the checks, a WASM module worker SHALL run with the same session order, limits, deadline, cancellation,
output publication, report schema and exit statuses as a process worker.

#### Scenario: Same messages for two worker kinds
- **WHEN** the same guest runs once as a process worker and once as a WASM module worker
- **THEN** the host sends the same messages and returns the same result

#### Scenario: Deadline
- **WHEN** a compile passes `--timeout` and the guest does not answer in time
- **THEN** the command exits 124, the worker is stopped and no output directory exists
