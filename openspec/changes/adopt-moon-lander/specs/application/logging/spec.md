# Spec Delta

## Purpose

Defines the leveled diagnostic logging of the Morphir CLI and Workbench: how a user selects what is logged, where log
records go, and how logging stays separate from command results and from telemetry.

## ADDED Requirements

### Requirement: Log levels

Diagnostic logging SHALL support the levels `trace`, `debug`, `info`, `warn`, `error` and `fatal`, and the setting
`off`. A record below the selected level SHALL NOT be written. The default level SHALL be `warn`.

#### Scenario: Default level

- **WHEN** a command runs with no logging setting
- **THEN** warning, error and fatal records are written and info, debug and trace records are not

### Requirement: Log level setting

The level SHALL come from the `--log-level` option, the `MORPHIR_LOGGING__LEVEL` variable, or the `logging.level`
configuration key, with the precedence of the configuration capability. An unknown level SHALL be a usage error.

#### Scenario: Option wins over configuration

- **WHEN** `morphir.toml` sets `logging.level = "info"` and the command line has `--log-level debug`
- **THEN** debug records are written

#### Scenario: Unknown level

- **WHEN** the command line has `--log-level loud`
- **THEN** the run fails with a usage error that lists the valid levels and exits with 2

### Requirement: Log output channels

Log records SHALL go to standard error. They SHALL NOT go to standard output in any output mode.

#### Scenario: JSON result stays parseable

- **WHEN** `morphir project list --json --log-level trace` succeeds
- **THEN** standard output holds only the JSON result and the trace records are on standard error

### Requirement: Log file

When `logging.file.enabled` is true, log records SHALL also go to text or JSON Lines files under `.morphir/logs/` in
the workspace, rolled daily and at 10 MiB, keeping the newest 31 files.

#### Scenario: File logging enabled

- **WHEN** `morphir.toml` sets `logging.file.enabled = true` and `logging.file.format = "json-lines"` and a command runs
- **THEN** a JSON Lines log file under `.morphir/logs/` holds the run's records

### Requirement: Logs are complete at exit

All accepted log records SHALL be written before the process ends, after success, failure or cancellation. When the
log queue is full, the newest records SHALL be dropped and the count of dropped records SHALL be reported.

#### Scenario: Records written before a cancelled exit

- **WHEN** a command logs records and is then cancelled by SIGINT
- **THEN** every accepted record is in the outputs before the process exits with 130

### Requirement: Structured records

Each log record SHALL have a timestamp in UTC, a level, a category that names the part of Morphir that wrote it, a
message, and named properties. JSON Lines records SHALL keep the properties as named fields.

#### Scenario: Property in a JSON Lines record

- **WHEN** the configuration loader logs the file it read, as the property `path`, in JSON Lines format
- **THEN** the record has a `path` field with the file path

### Requirement: Telemetry stays separate

The `--log`, `--log-file`, `--log-format` and `--otel-*` options SHALL keep their current meaning and formats.
Diagnostic log settings SHALL NOT change telemetry output.

#### Scenario: Telemetry with diagnostic logging

- **WHEN** a command runs with `--log --log-format ion-binary --log-level debug`
- **THEN** the telemetry file has the same Ion binary observations as without `--log-level`, and the debug records go
  only to the diagnostic outputs
