# Spec Delta

## Purpose

Defines how a Morphir CLI or Workbench run starts its work, reacts to cancellation and stop signals, releases its
resources, and chooses its exit code, so that scripts and hosts can rely on the same behavior from every command.

## ADDED Requirements

### Requirement: Exit codes

A CLI run SHALL exit with 0 on success, 1 when compilation, execution or publication fails, 2 for an invalid
invocation or configuration, 130 when it is cancelled by SIGINT, a cancel file or a host cancellation, and 143 when it
is stopped by SIGTERM.

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

### Requirement: Cancellation reaches running work

A cancellation request SHALL reach the running command, its child processes and its evaluation through one
cancellation state. Long-running work SHALL check it and stop at the next safe point.

#### Scenario: Cancel file

- **WHEN** a command runs with `--cancel-file stop.flag` and the file `stop.flag` is created
- **THEN** the command stops and exits with 130

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

On hosts that cannot deliver signals (wasm and wasm-gc), a run SHALL keep the same exit codes for success and
failure, and commands that need interruption SHALL refuse to start with a documented error, as they do today.

#### Scenario: Worksheet on WASI

- **WHEN** `morphir worksheet worksheet.scm` runs on the WASI build
- **THEN** it refuses with the `worksheet.interruption_unavailable` error and exits with 2

### Requirement: Workbench desktop shutdown

When the desktop Workbench quits, it SHALL stop its native services in reverse start order and SHALL end running
host executions before the process ends.

#### Scenario: Quit during an execution

- **WHEN** the user quits the desktop Workbench while a host execution runs
- **THEN** the execution is cancelled, the native services stop in reverse order, and the process ends
