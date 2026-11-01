# Spec Delta

## Purpose

Defines the `morphir extension describe`, `compile` and `generate` commands on the CLI's own worker host: the
explicit worker pin, the options that are removed, the JSON report and the exit status.

## ADDED Requirements

### Requirement: No helper, Node or service pin
`morphir extension describe`, `compile` and `generate` SHALL run on the CLI's worker host in the native and npm CLI.
They SHALL NOT need or read `--extension-helper`, `--node`, `MORPHIR_EXTENSION_HELPER`, `--services-pin`,
`--services-helper` or a Rust build.

#### Scenario: Native CLI with no Node installed
- **WHEN** a user with no `node` on PATH runs `morphir extension compile` with a pin for the MoonBit native guest
- **THEN** the compile succeeds

### Requirement: Worker pin contract
An explicit pin SHALL use contract `0.2.0` and contain `artifact` (path and SHA-256), `runtime` (`process` with
platform and argument array, or `wasm` with an optional ABI), an optional `descriptor` (path and SHA-256) and
`origin`. Unknown fields, relative paths and missing digests SHALL be refused.

#### Scenario: Python pin
- **WHEN** a pin names the Python `0.4.2` WASM file and its `release.json`, both with digests
- **THEN** the CLI checks both digests, compares the descriptor claims with the live describe, and runs the guest

#### Scenario: Unknown field
- **WHEN** a pin contains a `host` field
- **THEN** the command is refused with `extension.pin_invalid` and names the field

### Requirement: Retired pins and options
Pins with contract `0.1.0` or `0.1.0-draft.1`, and the options `--extension-helper` and `--node` on these commands,
SHALL be refused with `extension.pin_retired` or `extension.option_retired` and a message that points to the pin
migration in the extension documentation.

#### Scenario: Old portable pin
- **WHEN** a user passes a `core-wasm-process` pin with contract `0.1.0-draft.1`
- **THEN** the command exits 2 and the message names contract `0.2.0` and the documentation section

### Requirement: Compile and generate options
The commands SHALL keep their current source, package, model-format, IR-version, output, timeout and cancel-file
options and meanings, and SHALL derive the protocol line from the guest's describe answer, not from the pin.

#### Scenario: Elm compile
- **WHEN** a user compiles an Elm package through the Elm extension pin
- **THEN** the CLI uses MEP `0.1` `morphir.frontend.compile`, because the guest offers no model methods, and writes
  `morphir-ir.json`

#### Scenario: Python 0.5 compile at each IR version
- **WHEN** a user compiles with the Python extension `0.5.0`, which claims both lines, with `--ir-version 3` or `4`
- **THEN** the CLI uses MEP `0.2.0-draft.1` `morphir.frontend.compileModel` with the JSON tuple of that IR version and
  writes `model-envelope.json` and `model.json`, whose `formatVersion` is that version

#### Scenario: Plain IR with Python 0.5
- **WHEN** a user generates from a plain IR file of IR 3 or 4 with the Python extension `0.5.0`, which claims both lines
- **THEN** the CLI passes the file to the host's shared code and sends `morphir.backend.generateModel` with the tuple of
  that IR version

#### Scenario: Model generate of an IR 3 envelope
- **WHEN** a user generates from a model envelope of IR `3.0.0` with `--ir-version 3` through a guest that claims its
  tuple
- **THEN** the CLI sends `morphir.backend.generateModel` with that tuple; with `--ir-version 4` it refuses the model
  with `extension.ir_version_mismatch`

### Requirement: Safe publication
Output SHALL be written to `<output>.morphir-partial` and renamed into place without replacement only after the
session closed and the worker tree stopped. An existing output path SHALL be refused. A failure SHALL leave no
partial output directory.

#### Scenario: Failure after some artifacts
- **WHEN** generate returns artifacts and then the worker does not acknowledge `shutdown`
- **THEN** nothing is published and the staging directory is removed

### Requirement: JSON report
With `--json` the commands SHALL write one `morphir/command-result` `0.1.0` object to stdout. Success SHALL carry
`result` with the worker kind, extension identity, protocol line, negotiated tuple and limits, enforced bounds,
published files with sizes and SHA-256, lifecycle facts and the stderr tail. Failure SHALL carry `error`.

#### Scenario: Successful compile report
- **WHEN** `morphir extension compile --json` succeeds with the Python guest
- **THEN** stdout holds one object with `state: "succeeded"`, `exitCode: 0` and `result.worker.kind: "wasm"`

#### Scenario: Diagnostics stay on stderr
- **WHEN** the guest writes to stderr during a `--json` run
- **THEN** stdout still parses as one JSON object and the stderr tail is in the report

### Requirement: Exit status
The commands SHALL exit 0 on success, 1 when the guest answers `success: false` or the session fails, 2 when a pin,
identity, claim, negotiation or local input check refuses before an operation, 124 at the deadline and 130 on
cancellation, in human and JSON mode.

#### Scenario: Claims drift
- **WHEN** a pin's descriptor claims differ from the guest's live describe
- **THEN** the command exits 2 with `extension.claims_mismatch`

#### Scenario: Cancel file
- **WHEN** the file named by `--cancel-file` appears during generate
- **THEN** the command exits 130 and nothing is published

### Requirement: Sources and operations from claims
`compile` SHALL select source files by the file extensions in the extension's frontend claims and SHALL send the
claimed language ID. The commands SHALL offer only the operations the extension claims. The CLI SHALL hold no list
of supported languages or extensions.

#### Scenario: Gleam sources
- **WHEN** a user compiles a directory with an extension that claims `languageId: gleam` and `.gleam` files
- **THEN** the request carries the `.gleam` files of the bounded directory snapshot and the language ID `gleam`

#### Scenario: Unclaimed operation
- **WHEN** a user runs `generate` with an extension that claims only a frontend
- **THEN** the command exits 2 with `extension.capability_unavailable` and starts no operation

### Requirement: Conformance, not a list of extensions
Any extension that conforms to MEP and to a supported runtime and ABI profile SHALL run through these commands.
Qualification SHALL use the shared MEP conformance kits and independent fixture guests. The published Elm,
Python and MoonBit extensions SHALL be qualified as examples, not as the definition of support.

#### Scenario: Fixture guest from another toolchain
- **WHEN** a conformance fixture guest built with the Morphir extension SDK, importing WASI and the Morphir host
  functions, runs the shared conformance kit
- **THEN** the kit report qualifies with no host change made for that guest

#### Scenario: Published extensions
- **WHEN** a user runs the Elm extension `v0.4.1` executables, the Python extension `0.4.1` (single document) or
  `0.4.2`, or the MoonBit guest as a native executable or portable WASM module
- **THEN** they run on every host where their runtime is supported

#### Scenario: Python 0.4.1 with two modules
- **WHEN** a user compiles a two-module directory with the Python extension `0.4.1`
- **THEN** the command refuses it because the guest does not claim multi-document support, as before
