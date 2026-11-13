# repository/development-tools Specification

## Purpose

Defines the internal development tool of finos/morphir and the accounting rule for the gates that ran on the deleted Rust CLI: each one is kept on a development tool or retired by name with its destination, so no check disappears without a record.

## Requirements

### Requirement: morphir-dev is an internal tool, not a CLI product
`morphir-dev` SHALL hold only commands a repository gate or maintenance workflow needs, starting with the `kb` tree. It SHALL NOT be released, SHALL NOT be described as the Morphir CLI, and SHALL NOT gain product commands.

#### Scenario: Knowledge base check
- **WHEN** a contributor runs `morphir-dev kb check` in a repository whose kb conforms
- **THEN** it exits 0, with the same behavior `morphir kb check` had

### Requirement: Library-level contract gates keep running
The MEP contract IR check, the signed tool release metadata conformance and the package runtime assurance, publisher and decoder vectors SHALL keep running in CI, read the checked-in specifications through the libraries that implement them, and start no Morphir CLI.

#### Scenario: Package assurance vectors
- **WHEN** `mise run package:assurance-check` runs
- **THEN** it runs the same assurance vectors it ran before the CLI was deleted

### Requirement: Every former CLI gate is kept or retired by name
Each gate that ran on the deleted Rust CLI SHALL either run on `morphir-mck` or `morphir-dev`, or be listed as retired with the reason and the repository that now qualifies the behavior. A retired task that contributors may still call SHALL fail with a message naming where the check went, never succeed silently.

#### Scenario: A retired task is called
- **WHEN** a contributor runs `mise run test:examples`
- **THEN** it exits non-zero and says the scenarios are pending qualification against the .NET Morphir CLI

### Requirement: Acquisition contracts retain their external .NET corpus gate
The acquisition contract gate SHALL retain main's external .NET corpus job, path filter and required aggregate gate, with metadata-only TypeScript checks in the parent. Its source pin SHALL remain independent of the CLI delivery tuple. No Rust acquisition reader or resolver SHALL be restored.

#### Scenario: Acquisition corpus changes
- **WHEN** a fixed acquisition case, schema or narrative input changes
- **THEN** CI runs the independently pinned .NET tests against the current parent corpus and requires their success, preserving the metadata-only gates

### Requirement: The Rust submodule stays while development tools need it
`ecosystem/morphir-rust` SHALL remain pinned while `morphir-mck`, `morphir-dev` or another retained development tool builds on its crates, and SHALL NOT be removed by this change.

#### Scenario: Retained tools still build
- **WHEN** the workspace builds `morphir-mck-cli` and `morphir-dev-tools`
- **THEN** their path dependencies on `ecosystem/morphir-rust` resolve
