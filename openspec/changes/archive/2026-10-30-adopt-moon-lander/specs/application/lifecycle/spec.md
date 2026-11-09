# Spec Delta

## Purpose

Defines how a Morphir CLI or Workbench run starts its work, reacts to cancellation and stop signals, releases its
resources, and chooses its exit code, so that scripts and hosts can rely on the same behavior from every command.

## ADDED Requirements

### Requirement: Exit codes

A CLI run SHALL exit with 0 on success, 1 when compilation, execution or publication fails, 2 for an invalid
invocation or configuration, 130 when it is cancelled by SIGINT, a cancel file or a host cancellation, and 143 when it
is stopped by SIGTERM. A delivered Quit uses 131. Windows Moonx follows the separately specified stock-runtime
signal exception below.

#### Scenario: Successful command

- **WHEN** `morphir project list` succeeds
- **THEN** the exit code is 0

#### Scenario: Unknown option

- **WHEN** a command is given an option that it does not declare
- **THEN** the exit code is 2

#### Scenario: Interrupted evaluation

- **WHEN** SIGINT arrives while `morphir worksheet worksheet.scm` evaluates
- **THEN** the run stops the evaluation and exits with 130

#### Scenario: Terminated run

- **WHEN** SIGTERM arrives while a command runs on native
- **THEN** the run stops its work, cleans up and exits with 143

### Requirement: Moonx preserves host behavior with the approved Windows signal limitation

The published Node-backed Moonx entry SHALL preserve opaque arguments, bytes, output channels, JSON schemas and
owned-child cleanup. It SHALL preserve original SIGINT/SIGTERM delivery on POSIX. On supported stock Windows
Moonrun, it SHALL report delivered reasons and full process statuses under the approved Ctrl+C-to-Ctrl+Break
limitation. Neither layer SHALL infer an unavailable original signal. Native and npm entry contracts SHALL remain
unchanged.

#### Scenario: POSIX Moonx interruption

- **WHEN** SIGINT or SIGTERM arrives while the actual packaged Moonx entry runs on a supported POSIX host
- **THEN** the Node child receives that original signal, finishes its owned cleanup and reports 130 or 143
- **AND** the launcher completes finalization and retains the corresponding signal status

#### Scenario: Windows Moonx Ctrl+C on the stock runtime

- **WHEN** a real Windows console delivers Ctrl+C to the packaged entry under a supported stock Moonrun runtime
- **THEN** qualification records that the Node child receives Ctrl+Break and reports Quit with 131
- **AND** the launcher retains the actual Windows cancellation status `0xC000013A`, without POSIX normalization
- **AND** the child is reaped, owned payload files are removed, and the limitation is documented

#### Scenario: Windows Moonx forced cleanup

- **WHEN** the owned Node child ignores the delivered Windows break event
- **THEN** the launcher applies its bounded escalation, reaps the child and removes its owned payload
- **AND** qualification retains the actual child outcome and full launcher status instead of claiming original
  Ctrl+C preservation

#### Scenario: Moonx archive and registry qualification

- **WHEN** the entry is prepared for release
- **THEN** its actual packaged archive and fresh public-registry consumer run on the minimum and pinned MoonBit
  runtimes, with finite results, JSON failures, opaque arguments and exact byte transport checked
- **AND** Windows signal qualification uses real console delivery; synthetic Node events alone do not satisfy it

### Requirement: Cancellation reaches running work

A cancellation request SHALL reach the running command, its child processes and its evaluation through one
cancellation state. Long-running work SHALL check it and stop at the next safe point.

#### Scenario: Cancel file

- **WHEN** a command runs with `--cancel-file stop.flag` and the file `stop.flag` is created
- **THEN** the command stops and exits with 130

#### Scenario: GC cancel file during idle stdin

- **WHEN** a Wasm-GC command has a selected cancel file and waits for stdin that remains open without bytes
- **THEN** the host polls the registered path during its bounded input waits, requests the same hosted stop and
  finishes cleanup with one command-owned cancellation result and exit 130, without waiting for EOF
- **AND** a stop observed by the host remains requested even if the marker is subsequently removed

#### Scenario: GC registration capability is unavailable

- **WHEN** a GC invocation selects a cancel file but its host does not support registration
- **THEN** it refuses before command execution with a clear capability error and exit 2, preserving the existing
  JSON failure schema when selected

#### Scenario: Child process

- **WHEN** SIGINT arrives while a metadata provider child process runs
- **THEN** the child process is interrupted and the run exits with 130

### Requirement: Ordered cleanup

The services that a run starts SHALL start in registration order and stop in reverse order. Stop steps SHALL run
after success, after a failure and after cancellation. A run SHALL end within its shutdown time limit after a stop
request.

#### Scenario: Cleanup after a failure

- **WHEN** a command fails after its telemetry session and its log session have started
- **THEN** the log session stops first, then the telemetry session, and the telemetry is flushed before exit

#### Scenario: GC registration is cleared on every owned path

- **WHEN** a GC invocation successfully registers its cancel file
- **THEN** it attempts to clear that registration after success, failure, cancellation or a startup error, including
  a stop before any hosted service starts
- **AND** the `morphir_host_v1` response envelope, parent/worker messages and shared-buffer layout remain unchanged

#### Scenario: GC registration cleanup fails

- **WHEN** clearing a GC cancel-file registration fails after an otherwise successful command
- **THEN** the existing stdout result remains a single document, stderr reports `cancellation.cancel_file_cleanup_failed`,
  and the CLI exits with 1
- **AND** a preceding command failure or cancellation retains its selected exit code if cleanup also fails

#### Scenario: Stop step that hangs

- **WHEN** a stop step does not finish within the shutdown time limit
- **THEN** the run reports the timed-out step on standard error and exits with the code of its stop reason

### Requirement: Failure reports keep the output contract

When a run fails, its error report SHALL use the output mode that the command line selects, on the channels that the
command documents. In JSON mode, the failure SHALL be the documented JSON failure on standard output.

#### Scenario: JSON failure

- **WHEN** `morphir project list --json` fails because the configuration is invalid
- **THEN** standard output holds one JSON failure document, diagnostics go to standard error and the exit code is 2

### Requirement: Hosts without signals

On embedded hosts without an interruption capability, a run SHALL keep the same exit codes for success and
failure, and commands that need interruption SHALL refuse to start with a documented error. The WASI entry
retains this refusal. A capable Wasm-GC host retains its documented interruption support. The Moonx launcher
qualifies its owned Node host separately and SHALL follow the Moonx requirements above.

#### Scenario: Worksheet on WASI

- **WHEN** `morphir worksheet worksheet.scm` runs on the WASI build
- **THEN** it refuses with the `worksheet.interruption_unavailable` error and exits with 2

### Requirement: Workbench desktop shutdown

When the desktop Workbench quits, it SHALL stop its native services in reverse start order and SHALL end running
host executions before the process ends.

#### Scenario: Quit during an execution

- **WHEN** the user quits the desktop Workbench while a host execution runs
- **THEN** the execution is cancelled, the native services stop in reverse order, and the process ends
