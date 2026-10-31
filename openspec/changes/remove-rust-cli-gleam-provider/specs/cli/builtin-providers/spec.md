# Spec Delta

## Purpose

Defines which language providers the Rust Morphir CLI ships built in, how a
command reaches them, and which language-specific commands the CLI offers.

## ADDED Requirements

### Requirement: The native Elm provider is the only built-in provider
The CLI SHALL ship exactly one built-in language provider, the native Elm
provider `morphir-elm-native`. The CLI SHALL register it only when a command
selects it by id, with `--extension` or with `[frontend.elm] extension`.

#### Scenario: No selection reaches no built-in provider
- **WHEN** a command resolves a frontend or backend for `elm` or `gleam` with no provider selected and nothing installed
- **THEN** resolution fails and no built-in provider is used

#### Scenario: Selection by id reaches the native Elm provider
- **WHEN** `morphir compile --extension morphir-elm-native` compiles an Elm source
- **THEN** the native Elm provider compiles it in process

### Requirement: Gleam is not built in
The CLI SHALL NOT register a Gleam provider unless one is installed. The ids
`morphir-gleam` and `morphir-gleam-binding` SHALL select only an installed
extension with that exact id.

#### Scenario: The legacy Gleam id is not an alias
- **WHEN** `morphir compile --extension morphir-gleam-binding` runs and no extension with that id is installed
- **THEN** the compile fails and reports that no extension with that id is installed

### Requirement: Generate uses installed backends
`morphir generate` SHALL resolve its backend from installed extensions only.

#### Scenario: No installed backend for the target
- **WHEN** `morphir generate` runs for a target that no installed extension generates
- **THEN** the command fails and names the target

### Requirement: The CLI has no language-specific subcommand for Gleam
The CLI SHALL NOT offer a `gleam` subcommand. Compile and generate SHALL use
the generic `compile` and `generate` commands.

#### Scenario: The gleam subcommand is refused
- **WHEN** a user runs `morphir gleam compile`
- **THEN** the CLI reports an unknown subcommand and exits with an error
