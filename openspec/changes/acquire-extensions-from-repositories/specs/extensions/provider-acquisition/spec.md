# Spec Delta

## Purpose

Defines how a compile or generate gets the provider it needs: from installed extensions first, and from the
repositories when none is installed, now that language frontends are not built into the CLI.

## ADDED Requirements

### Requirement: Frontends are not built in
The CLI binary SHALL NOT contain the Elm or MoonBit frontend. Both SHALL be extensions offered by the `finos`
repository and obtained like any other extension.

#### Scenario: Fresh install compiles Elm
- **WHEN** a user with no installed extensions runs `morphir compile` on an Elm project interactively
- **THEN** the CLI offers to install the Elm frontend from `finos` and, after the user accepts, compiles the project

### Requirement: Installed providers are used
Compile and generate SHALL select providers from the installed extensions, honoring an explicit provider choice from
the command line or the workspace configuration. More than one installed provider for the same role and language,
with no explicit choice, SHALL be an error that names them.

#### Scenario: Two installed Elm frontends
- **WHEN** two installed extensions both compile Elm and nothing selects one
- **THEN** the compile fails and lists both, with the option and configuration key that select one

### Requirement: Same compile contract for installed providers
`morphir compile` SHALL accept the same options and produce the same model formats and report when its provider is an
installed extension as it did when the provider was built in.

#### Scenario: Elm checkpoint after the move
- **WHEN** a project compiled with the built-in Elm frontend is compiled with the installed Elm frontend extension of
  the same version
- **THEN** the written model files and the JSON report have the same content

### Requirement: On-demand acquisition
When no installed extension provides a needed role, the CLI SHALL run a capability query against the enabled
repositories. In an interactive run it SHALL offer the matches, install the chosen extension
and continue the same command. The repository's recommended provider SHALL be offered first.

#### Scenario: One match
- **WHEN** one enabled repository offers the only matching provider
- **THEN** the CLI asks one question, installs it and continues

#### Scenario: Non-interactive run
- **WHEN** a non-interactive run needs a provider that is not installed and no install option was given
- **THEN** it fails without downloading anything, names the provider it found, and shows the command or option that
  installs it

### Requirement: Unattended acquisition
Compile and generate SHALL accept an option that allows on-demand installation without a prompt.

#### Scenario: CI compile
- **WHEN** CI runs `morphir compile --install-missing` in a workspace that needs the Elm frontend
- **THEN** the frontend is installed from `finos` and the compile runs, with no prompt

### Requirement: Nothing found
When no repository offers a needed provider, the CLI SHALL fail with a message that names the role, the language or
target and the IR version, and the repositories it searched.

#### Scenario: Unknown language
- **WHEN** a compile needs a COBOL frontend and no enabled repository offers one
- **THEN** the error names `frontend.compile`, `cobol`, the IR version and each repository searched
