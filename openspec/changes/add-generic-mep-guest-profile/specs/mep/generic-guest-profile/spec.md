# Spec Delta

## Purpose

Defines the generic JSON Library profile of the shared MEP guest kit. With it,
any MEP extension that compiles and generates a fixed Bool library can show
conformance through `morphir mck mep guest-run` without claiming the identity
of another extension.

## ADDED Requirements

### Requirement: Any extension identity
The profile `generic-json-library-v1` SHALL accept any extension id. The
describe result SHALL give a non-empty `id`, a non-empty `name` and a SemVer
`version`, and every initialize result SHALL repeat the same `extension`
value.

#### Scenario: SDK fixture identity
- **WHEN** a guest describes itself as `morphir-sdk-fixture` version `0.1.0`
- **THEN** the identity check passes

#### Scenario: Initialized identity changes
- **WHEN** the initialize result gives an `extension` value that differs from the describe result
- **THEN** the run is not qualified

### Requirement: One fixed package with one expected IR per version
The kit SHALL fix one package, `mck/generic` with module `main`, and one
expected IR for each of `3.0.0` and `4.0.0`. Every language source set in the
kit SHALL describe the same package and SHALL compare with the same expected
IR.

#### Scenario: Two languages, one expectation
- **WHEN** the Python source set and the flags source set compile at `3.0.0`
- **THEN** the runner compares both results with the one `3.0.0` expected IR

### Requirement: Language source sets
The kit SHALL give, for each kit language, the documents of the fixed package
and the documents of a malformed source. Each document URI SHALL be relative to
the source folder. It SHALL NOT be absolute, have a scheme, a `src/` prefix, an
empty segment, or a `.` or `..` segment.

#### Scenario: Relative URI
- **WHEN** the Python source set gives the document `main.py`
- **THEN** the kit loads

#### Scenario: Prefixed URI
- **WHEN** a source set gives the document `src/main.py` or `/work/main.py`
- **THEN** the kit is refused before any guest starts

### Requirement: Language selection from the claim
The runner SHALL select the first kit language, in lexical order of its id,
that the guest claims both as a frontend language id and as a backend target. When the guest
claims no such language, the run SHALL NOT be qualified.

#### Scenario: Guest claims Python
- **WHEN** the guest claims frontend language `python` and backend target `python`
- **THEN** the runner uses the Python source set

#### Scenario: Language without a source set
- **WHEN** the guest claims only a language that the kit has no source set for
- **THEN** the describe case fails and the run is not qualified

### Requirement: IR versions from the claim
The runner SHALL test each IR version, of `3.0.0` and `4.0.0`, that the guest
claims for both its frontend and its backend. A claim of `3` or `3.0.0` SHALL
select `3.0.0`, and a claim of `4` or `4.0.0` SHALL select `4.0.0`. When no
version is selected, the run SHALL NOT be qualified.

#### Scenario: Guest claims only IR 3
- **WHEN** the guest claims IR version `3` for its frontend and its backend
- **THEN** the plan has the `3.0.0` cases and no `4.0.0` cases

#### Scenario: Frontend and backend differ
- **WHEN** the frontend claims `3` and `4` and the backend claims only `4`
- **THEN** the plan has only the `4.0.0` cases

### Requirement: Required legacy JSON tier
For every guest, the runner SHALL negotiate MEP `0.1` in one process. For each
selected IR version it SHALL compile the fixed source with
`morphir.frontend.compile`, generate from the compiled IR with
`morphir.backend.generate`, and generate from the kit's expected IR, and it
SHALL compile the files of each generate case again.

#### Scenario: Legacy-only guest
- **WHEN** a guest claims only protocol version `0.1`
- **THEN** the plan has the legacy tier and no model tier

### Requirement: Model tier when claimed
When the describe result claims protocol `0.2.0-draft.1`, the runner SHALL, in
a new process, negotiate `0.2.0-draft.1` with the `morphir-json` tuples of each
selected IR version for which the guest claims both a `compileModel` and a
`generateModel` JSON tuple, and SHALL compile and generate through them.

#### Scenario: Guest claims JSON model tuples at 4.0.0
- **WHEN** a guest claims `0.2.0-draft.1` and JSON `compileModel` and `generateModel` tuples at `4.0.0`
- **THEN** the plan has the model cases at `4.0.0`

#### Scenario: Model transport without JSON tuples
- **WHEN** a guest claims `0.2.0-draft.1` but no JSON model tuple pair at a selected IR version
- **THEN** the plan has no model tier

### Requirement: Semantic IR comparison
A compiled IR SHALL equal the expected IR after these rules only: JSON object
member order is ignored; in IR `3` the order of the `modules`, `types` and
`values` name-keyed lists is ignored; in IR `4`, at an `outputType` or a member of `inputTypes`, a `Reference` with
an `fqname` and no or empty `args` equals its FQName string.

#### Scenario: Different value order
- **WHEN** a guest returns IR `3` with `blocked` before `ready`
- **THEN** it equals the expected IR, which has `ready` first

#### Scenario: Long form type reference
- **WHEN** a guest returns IR `4` with `{"Reference": {"fqname": "morphir/SDK:basics#bool"}}` as an output type
- **THEN** it equals the expected `"morphir/SDK:basics#bool"`

#### Scenario: Reference outside a type position
- **WHEN** a guest returns IR `4` with `{"Reference": {"fqname": "mck/generic"}}` as the `packageName`
- **THEN** the comparison fails

#### Scenario: Wrong type
- **WHEN** a guest returns IR `4` with output type `Unit` for `ready`
- **THEN** the comparison fails

### Requirement: Successful compile
A successful compile SHALL have `success` true, a diagnostics array without an
`error` diagnostic, and an IR (legacy tier) or a valid `morphir-json` model
(model tier) that equals the expected IR. Warning and info diagnostics SHALL be
allowed.

#### Scenario: Compile with a warning
- **WHEN** a compile succeeds with one `warning` diagnostic and the expected IR
- **THEN** the compile case passes

### Requirement: Generated files and round trip
Every successful generate SHALL return a non-empty list of text artifacts with
unique, relative paths. After every generate case, the artifacts whose path
ends in a claimed file extension of the selected language SHALL compile again,
in the same tier, to the expected IR. The kit SHALL NOT fix generated bytes.

#### Scenario: Round trip keeps the IR
- **WHEN** the generated `main.flags` compiles again to the expected IR
- **THEN** the round trip case passes

#### Scenario: Round trip loses a type
- **WHEN** the generated file compiles again with a different output type
- **THEN** the round trip case fails and the run is not qualified

### Requirement: Refusals and lifecycle
The runner SHALL require that a malformed source gives `success` false with no
IR and an `error` diagnostic, that an unknown method gives `-32601`, that a
request after shutdown gives `-32014`, that notifications give no output, that
`describe` does not change, and that each process exits cleanly. In the
model tier a payload with a wrong SHA-256 SHALL give `-32602`.

#### Scenario: Malformed source
- **WHEN** the guest compiles the kit's malformed source
- **THEN** the result has `success` false, no IR and an `error` diagnostic

### Requirement: Numeric request ids
Each request SHALL have a numeric id, counted from 1 in each guest process.
Identity echo of string or other id forms is outside this profile.

#### Scenario: Guest that reads only numeric ids
- **WHEN** a guest accepts only numeric JSON-RPC ids
- **THEN** the profile can still qualify it

### Requirement: Supported claims format
The describe result SHALL use a supported claims format: `claimsVersion`
`0.1.0-draft.2`, or the draft.1 field `statementVersion` `0.1.0-draft.1`. A
claim with both fields, another version, or a `critical` path other than its
version field SHALL fail the describe case.

#### Scenario: Draft.1 claim
- **WHEN** a guest describes itself with `statementVersion` `0.1.0-draft.1`
- **THEN** the describe case passes the format check

#### Scenario: Unknown claims version
- **WHEN** a guest sends `claimsVersion` `garbage` or `0.1.0-draft.3`
- **THEN** the describe case fails

### Requirement: Recheck from the recorded claim
`morphir mck mep report-check` SHALL rebuild the plan from the recorded
describe observation, and SHALL check the case order, every request and every
response against the kit. A changed claim in a stored report SHALL fail the
recheck unless the full recorded plan agrees with it.

#### Scenario: Report with a removed case
- **WHEN** a stored report omits the round trip case of a selected IR version
- **THEN** `report-check` fails
