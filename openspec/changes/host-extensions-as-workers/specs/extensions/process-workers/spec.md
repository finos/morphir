# Spec Delta

## Purpose

Defines how the MoonBit CLI runs an extension as an out-of-process worker on native and Node hosts: verified
staging, environment, process tree ownership, framed stdio, deadlines, cancellation, stderr and cleanup.

## ADDED Requirements

### Requirement: Run verified copies
Before it starts a process worker, the host SHALL read the artifact through a no-follow descriptor, hash the bytes
it read, compare the hash with the worker specification, write those bytes to a private directory, make that copy
executable for its owner only and start it. A later change to the original path SHALL NOT change what runs.

#### Scenario: Artifact replaced after verification
- **WHEN** the original executable is replaced while the worker starts
- **THEN** the worker runs the verified copy, or the start is refused, never the replacement

#### Scenario: Digest mismatch
- **WHEN** the artifact's SHA-256 differs from the specification
- **THEN** the host refuses with `extension.digest_mismatch` and starts no process

### Requirement: Isolated environment
A process worker SHALL start with an empty environment except for variables the host documents, an empty private
working directory, and the specification's argument array forwarded unchanged, including empty strings and
delimiters. It SHALL inherit no other open file descriptors or handles.

#### Scenario: User environment
- **WHEN** the user has `MORPHIR_HOME` and a token variable set
- **THEN** the worker's environment contains neither

#### Scenario: Environment of the npm CLI on Windows
- **WHEN** the npm CLI starts a process worker on Windows
- **THEN** the worker's environment holds only variables from the list that the Node process worker README
  documents: `SystemRoot`, which the launcher passes, and `HOMEDRIVE`, `HOMEPATH`, `LOGONSERVER`, `PATH`,
  `SYSTEMDRIVE`, `TEMP`, `USERDOMAIN`, `USERNAME`, `USERPROFILE` and `WINDIR`, which libuv adds when the host has them

### Requirement: Framed stdio
The host SHALL write MEP messages to the worker's stdin and read them from its stdout with Content-Length framing,
headers of at most 8 KiB, and a frame no larger than the message limit. The host SHALL treat stderr as diagnostics
only and SHALL never parse it as protocol.

#### Scenario: Log on stdout
- **WHEN** a worker writes text that is not a valid frame to stdout
- **THEN** the session fails with `extension.frame_invalid` and the worker is stopped

### Requirement: Bounded stderr
The host SHALL drain stderr concurrently with stdout and SHALL keep at most the last 64 KiB. The report SHALL say
when stderr was truncated.

#### Scenario: Noisy worker
- **WHEN** a worker writes 10 MiB to stderr during a successful compile
- **THEN** the compile succeeds, the report keeps the last 64 KiB and marks stderr as truncated

### Requirement: Process tree ownership on Unix
On Linux and macOS the host SHALL start each process worker as the leader of a new process group and SHALL stop the
worker by signalling the whole group. Processes that the worker starts SHALL stop with it.

#### Scenario: Worker with a child process
- **WHEN** a worker starts a child process and the session deadline passes
- **THEN** both the worker and its child are terminated before the command returns

### Requirement: Process tree ownership on Windows
On Windows the native CLI SHALL assign each process worker to its own job object before the worker runs any code,
with kill-on-close set, and SHALL stop the worker by terminating its job. The npm CLI on Windows SHALL stop the
worker by terminating its whole process tree and SHALL confirm that the root process has exited.

#### Scenario: Cancellation in the native CLI on Windows
- **WHEN** the user presses Ctrl+C during a compile in the native CLI on Windows
- **THEN** the worker's job is terminated and no process from it remains

#### Scenario: Deadline in the npm CLI on Windows
- **WHEN** a session deadline passes in the npm CLI on Windows
- **THEN** the worker's process tree is terminated and the report names tree termination as the method

### Requirement: Stop and confirm
After `exit`, the host SHALL wait at most 2 seconds for the worker to stop, then terminate its process tree. On
deadline, cancellation or a transport fault it SHALL terminate the tree at once. In all cases it SHALL confirm the
tree has stopped before it removes the private directory and returns.

#### Scenario: Worker ignores exit
- **WHEN** a worker stays alive after `exit`
- **THEN** the host terminates its tree after the grace period and reports a forced stop

#### Scenario: Tree does not stop
- **WHEN** the host cannot confirm that the tree stopped within its bound
- **THEN** the outcome is failed with `execution.tree_termination_failed` and no output is published

### Requirement: Host exit
If the host exits, the worker's stdin SHALL close, and on Windows the worker's job SHALL be terminated. A worker
that reads end of file on stdin before `exit` SHALL be treated by the host as stopped by the host, not as a result.

#### Scenario: CLI killed
- **WHEN** the CLI process is killed with SIGKILL during a session
- **THEN** the worker sees end of file on stdin; the MoonBit and Elm guests exit

### Requirement: Process worker hosts
Process workers SHALL be available in the native CLI on Linux, macOS and Windows and in the npm CLI on Node, with no
Node executable, helper module or Rust helper supplied by the user.

#### Scenario: Elm extension from the native CLI
- **WHEN** the native CLI runs the Elm extension `v0.4.1` executable for the host platform
- **THEN** the compile runs as a process worker and Node is not needed on PATH

#### Scenario: MoonBit guest from the npm CLI
- **WHEN** the npm CLI runs the native MoonBit guest
- **THEN** it starts the guest through Node's process support with the same tree ownership and limits
