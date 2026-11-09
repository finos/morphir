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
message, and named properties. JSON Lines records SHALL keep event properties as fields of a `properties` object,
preserving each value's JSON type, including null, arrays and objects. Event properties SHALL NOT replace record
metadata.

#### Scenario: GC diagnostic clock

- **WHEN** a Wasm-GC command enables diagnostic logging
- **THEN** it requests `utc_milliseconds` through the existing `morphir_host_v1` interface, validates a whole numeric
  epoch-millisecond value in the framework's supported timestamp range, and writes UTC text diagnostics to stderr
- **AND** the command's stdout result and existing host response envelope remain unchanged

#### Scenario: Missing or invalid GC diagnostic clock

- **WHEN** a Wasm-GC host cannot provide the clock or returns an invalid timestamp while diagnostics are enabled
- **THEN** the CLI fails before starting the command, with a clear clock-capability error and exit 2
- **AND** JSON mode emits the owning command's existing structured failure

#### Scenario: GC help and disabled diagnostics

- **WHEN** a Wasm-GC invocation requests help or sets `--log-level off`
- **THEN** it does not request the UTC clock operation and does not fail merely because that capability is absent

#### Scenario: Property in a JSON Lines record

- **WHEN** the configuration loader logs the file it read, as the property `path`, in JSON Lines format
- **THEN** `record.properties.path` holds the file path

#### Scenario: Property name matches record metadata

- **WHEN** an event has level `Debug` and an event property named `level` with value `project`
- **THEN** the record's level remains `Debug` and `record.properties.level` is `project`

#### Scenario: Array-valued property

- **WHEN** an event has one `paths` property whose value is `["a", "b"]`
- **THEN** `record.properties.paths` is `["a", "b"]` and the record has no `duplicateProperties` field

### Requirement: Duplicate property winner

When an event's ordered property list repeats a name, `record.properties` SHALL keep the last occurrence's value
for that name, preserving its JSON type.

#### Scenario: Last path wins

- **WHEN** an event has `path` values `/repo/morphir.toml` and then `/repo/app/morphir.toml`
- **THEN** `record.properties.path` is `/repo/app/morphir.toml`

### Requirement: Duplicate property history

A JSON Lines record with repeated property names SHALL include a `duplicateProperties` object. Each repeated name
SHALL map to an array of all its values in original per-name order, including the winning value, with their JSON
types preserved. Names occurring once SHALL NOT appear in this object. When no names repeat, the record SHALL
omit `duplicateProperties`.

#### Scenario: All repeated values retained

- **WHEN** an event has `path` values `/repo/morphir.toml` and then `/repo/app/morphir.toml`, and one `command` value
  `project.list`
- **THEN** `record.duplicateProperties.path` is `["/repo/morphir.toml", "/repo/app/morphir.toml"]`
- **AND** `record.duplicateProperties` has no `command` field

#### Scenario: Repeated structured values retain their types

- **WHEN** an event has `value` occurrences `null`, `[1, 2]` and then `{"enabled": true}`
- **THEN** `record.properties.value` is `{"enabled": true}`
- **AND** `record.duplicateProperties.value` is `[null, [1, 2], {"enabled": true}]`

#### Scenario: No repeated names

- **WHEN** every event property name occurs once
- **THEN** the record has no `duplicateProperties` field

### Requirement: Telemetry stays separate

The `--log`, `--log-file`, `--log-format` and `--otel-*` options SHALL keep their current meaning and formats.
Diagnostic log settings SHALL NOT change telemetry output.

#### Scenario: Telemetry with diagnostic logging

- **WHEN** a command runs with `--log --log-format ion-binary --log-level debug`
- **THEN** the telemetry file has the same Ion binary observations as without `--log-level`, and the debug records go
  only to the diagnostic outputs
