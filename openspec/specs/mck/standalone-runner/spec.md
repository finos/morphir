# mck/standalone-runner Specification

## Purpose

Defines `morphir-mck`, the standalone program of the shared Morphir Compatibility Kit runner, and how the Morphir CLI reaches it. There is one runner: the same command tree, adapters, frozen expectations and exit codes, whether a user types `morphir-mck run` or `morphir mck run`.

## Requirements

### Requirement: morphir-mck keeps the existing command tree
`morphir-mck` SHALL accept exactly the commands, options, adapters, kits and report formats that the Rust CLI accepted under `morphir mck` (`spec/mck/cli-contract.md`), with only the program name changed: `morphir mck <command> ARGS` becomes `morphir-mck <command> ARGS`.

#### Scenario: A gate moves to the standalone program
- **WHEN** `morphir-mck check spec/ir/mck` runs on the kit that `morphir mck check spec/ir/mck` passed
- **THEN** it reports the same result with the same exit status

#### Scenario: The adapter is still explicit
- **WHEN** `morphir-mck run` is started without `--adapter`
- **THEN** it exits 2 as a usage error and writes no report

### Requirement: Output and exit codes are unchanged
`morphir-mck` SHALL write results to stdout and diagnostics to stderr, exit 0 on success, 1 on a failed check or an operational error and 2 on a usage error, and keep the member order of its JSON output.

#### Scenario: JSON output keeps its order
- **WHEN** `morphir-mck check <kit> --json` runs
- **THEN** stdout is one tab-indented JSON document whose first member is `files`

### Requirement: The Morphir CLI delegates to the one runner
The Morphir CLI SHALL implement `morphir mck ARGS` by starting `morphir-mck ARGS` with the same arguments, standard streams, working directory and exit status, and SHALL NOT carry a second implementation of these commands. A command it cannot delegate SHALL fail with a message that names `morphir-mck`.

#### Scenario: Delegated run
- **WHEN** a user runs `morphir mck run --adapter ./adapter --report r.json`
- **THEN** the report and exit status are the ones `morphir-mck run --adapter ./adapter --report r.json` produces

### Requirement: The runner is development-only during the transition
`morphir-mck` SHALL NOT be published as a product or included in an official CLI release. Its version and name SHALL identify it as the runner, not as the Morphir CLI, and gaps in the .NET destination runner SHALL be stated, not hidden.

#### Scenario: The runner identifies itself
- **WHEN** `morphir-mck --version` runs
- **THEN** it prints `morphir-mck <version>`, never `morphir <version>`

### Requirement: A packaged runner works without development tools
A copied `morphir-mck` executable SHALL vendor, check and run a kit and check and render its report with an empty tool path and only explicitly copied inputs, reproducing the frozen records of the historical replay.

#### Scenario: Copied binary with an empty PATH
- **WHEN** the copied binary replays the frozen TypeScript transcript on the historical kit with `PATH` empty
- **THEN** the report's 802 records equal the source run's records and `report check` passes
