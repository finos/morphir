# Node process workers

`finos/morphir-host/worker/process/node` runs process workers for the npm CLI
through Node's `child_process` (design decision PROC-2). It builds only for the
js target. The native CLI uses `worker/process/native`. Both launchers share the
framing, the stderr tail, the stop bounds and the staging rules of
`worker/process`, and both pass the same
[conformance suite](../conformance/README.md).

## Example

```moonbit
let spec = @worker.WorkerSpec::new(artifact, Process(platform~, args~))
let channel = @node.NodeProcessLauncher::new().launch(spec, limits)
channel.send(request)
let response = channel.receive()
channel.send(exit)
let stop = channel.close()
```

`launch` refuses a WASM runtime and an artifact in memory with
`RuntimeUnavailable`, and a platform that the machine cannot run with
`PlatformMismatch`. `host_machine` finds the machine as the native launcher
does: Node's operating system and architecture, and on Linux each C library
whose dynamic loader is present, whatever Node itself links. Then it stages the artifact and starts the verified copy.
The channel checks frames against the session's `limits`.

## How a worker starts

1. Staging opens the artifact with `O_NOFOLLOW` and `O_NONBLOCK`, checks with
   `fstat` that it is a regular file of at most 512 MiB, and reads it through
   the same descriptor. It uses `fs.promises`, so a large artifact does not
   block the event loop. A link gives `ArtifactUnreadable(SymbolicLink)`, a
   directory or FIFO `NotRegularFile`.
2. `VerifiedArtifact::check` hashes the bytes that were read and compares them
   with the specification. A mismatch gives `DigestMismatch`, and no process
   starts.
3. Staging writes the bytes to a new private directory (mode 0700) in the
   shared staging layout (`VerifiedArtifact::stage_in`): the copy is
   `bin/<file name>`, a file that only its owner can read and execute (mode
   0500), and `work` is an empty directory. Both subdirectories have mode 0700.
   On Windows a file name without an extension gets `.exe`
   (`VerifiedArtifact::copy_name`), because libuv starts a file without an
   extension only as `<name>.com` or `<name>.exe`. The copy has its own
   directory, so an artifact named `work` cannot collide with the working
   directory. The worker runs that copy, so a later change to
   the original path does not change what runs.
4. `spawn` starts the copy with `detached: true` (a new process group on Unix),
   three pipes, `windowsHide: true`, `work` as its working directory and the
   argument array unchanged.

A cancelled launch stops what it already started. Staging and the spawn
finish even when the task is cancelled, because Node cannot take back a
started process. A launch that is cancelled before the spawn removes the
private directory and starts nothing. A launch that is cancelled during the
spawn aborts the new channel at a checkpoint after it: the host stops the
tree, confirms the stop and removes the directory before the cancellation
leaves `launch`.

The worker's environment is empty on Linux and macOS. macOS adds
`__CF_USER_TEXT_ENCODING` to every process that has none; the host does not
pass it.

On Windows the launcher passes only `SystemRoot`, which Windows programs need
to load system libraries. libuv, which starts Node's child processes, then
adds these variables from the host's environment when the host has them, even
to an empty environment. So the npm CLI's worker environment on Windows is at
most this list, and nothing else:

| Variable | Added by |
| --- | --- |
| `SystemRoot` | the launcher |
| `HOMEDRIVE`, `HOMEPATH`, `LOGONSERVER`, `PATH`, `SYSTEMDRIVE`, `TEMP`, `USERDOMAIN`, `USERNAME`, `USERPROFILE`, `WINDIR` | libuv |

The native CLI on Windows passes only `SystemRoot`. The conformance case
"environment holds only documented variables" checks this list on Windows.

## Channel

- `send` encodes one frame with `FrameWriter` and writes it to stdin with a
  promise-based write through `@js_async.run_promise`. The request limit
  (4 MiB by default) counts the framed bytes, header included: a larger frame
  gives `FrameLimit(direction=Request)`, and nothing is written.
- `receive` reads stdout through `@js_async.ReadableStream` (`Readable.toWeb`)
  and decodes frames with `FrameReader`. The response limit (16 MiB by
  default) counts the body that `Content-Length` declares: the reader refuses
  a larger declared body with `FrameLimit(direction=Response)` before it reads
  it. The reader checks each header line when its CRLF arrives, so text that
  is not a frame, such as the bare LF of `console.log`, gives `FrameInvalid`
  at once.
- Each pipe has an `error` listener, so a pipe fault cannot crash the host.
  The channel keeps the first fault, and the next `send` or `receive` raises
  `TransportFailed("the worker's <stream> pipe failed: <message>")`. The
  session ends with `extension.incomplete_session` and aborts the tree. A
  write to an input that the worker has closed (`EPIPE`) is the end of the
  worker's stream, `WorkerClosed`, not a fault.
- Once a stop has started, `send` and `receive` raise `Stopped`, also when
  the stop overlaps a write or a read in progress.
- Node drains stderr while the worker runs into a `StderrBuffer`, which keeps the
  last 64 KiB. The stop carries the tail and marks it truncated when bytes were
  dropped.
- A cancelled `send` or `receive` passes the cancellation through unchanged.

## Stop

`close` ends stdin and waits at most 2 seconds for the worker to exit. During
the wait the host reads and discards stdout, so a worker that writes after
the end of its input does not block on a full pipe. An `abort` during that
wait ends it at once. `abort` stops the tree at once. Both
run their cleanup under `protect_from_cancel` and return the first stop on
every later call.

| Host | Tree | Stop | Confirmation | Method |
| --- | --- | --- | --- | --- |
| Linux, macOS | process group (`detached: true`) | `process.kill(-pid, 'SIGKILL')` | the `exit` event, then `process.kill(-pid, 0)` until `ESRCH` | `GroupSignal` |
| Windows | the root's process tree | `taskkill /PID pid /T /F` | the root's `exit` event | `TreeTermination` |

A worker that exits by itself reports `ExitedAfterExit`. On Unix the `exit`
listener sends SIGKILL to the worker's group in the same tick as Node reaps the
worker. While a member of the group remains, the system cannot reuse the group
ID, so the signal cannot reach another process. If the signal found members,
the stop reports `GroupSignal` with the exit status. After the exit the host
never signals the group again: it only probes it with signal 0 until the
first `ESRCH`, and only when the sweep found members. macOS refuses a signal
to a group that holds only zombies (`EPERM`); the probe then decides.

Each confirmation step has a 5 second bound (`STOP_CONFIRM_MS`). When the host
cannot confirm the stop, the status is `Unconfirmed(reason)`, the host keeps
the private directory, and it releases the worker's pipes and handle so that
the CLI can still exit. Otherwise it removes the private directory before it
returns. On Windows a file stays in use for a short time after its process has
exited, so the host retries the removal for at most 2 seconds
(`REMOVE_RETRY_MS`). A directory that it still cannot remove means that a file
in it is in use, so the stop is `Unconfirmed(reason)` with the method of the
stop. The failure is never silent. After a worker that exited by itself, the
reason is `GraceExpired`.

## Differences from the native launcher

- **Windows tree termination.** Node cannot create a job object without the
  PowerShell and C# bridge that this change retires. The npm CLI on Windows
  stops a worker with `taskkill /T /F` from its root and reports
  `TreeTermination`, not `JobTermination`. `taskkill /T` follows parent process
  IDs, so it reaches descendants only while the root runs. A descendant that
  outlives a worker which exited by itself is not stopped. The conformance case
  "descendants stop after the worker exits" applies only to `Group` and `Job`
  ownership for this reason.
- **Host exit.** On Windows the native CLI's job object kills the worker when the
  CLI dies. The npm CLI has no job: when it dies, the worker's stdin closes, and
  a conformant worker exits at the end of its input.
- **Environment on Windows.** libuv adds up to ten variables to the worker's
  environment; see [How a worker starts](#how-a-worker-starts). The native CLI
  passes only `SystemRoot`.
- **Links on Windows.** Windows has no `O_NOFOLLOW`. There the host refuses a
  link that `lstat` reports before it opens the artifact, so a link that is
  created between the two calls is not detected.
- **Signals.** The Node launcher sends SIGKILL to the group at once. It does not
  send SIGTERM first.

## Tests

`moon test --target js -p finos/morphir-host/worker/process/node` runs the
conformance suite against the Node fixture worker
(`fixtures/worker.mjs`), the staging tests and the stop decision tests. The
tests need Node to run the fixture worker; the launcher itself does not need a
Node executable from the user. On Linux and macOS the staging tests use a small
`/bin/sh` wrapper as the artifact. The conformance suite stages a copy of the
fixture worker that starts with `#!` and the Node executable, so the launcher's
own staging runs for every case and no shell adds environment variables. On Windows, where Node cannot start a script
without a shell, the artifact is the Node executable. The same test file covers
the Windows `taskkill` path when it runs on Windows.
