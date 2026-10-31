# Native process workers

This package runs a Morphir extension as a separate operating system process,
from the native CLI on Linux, macOS and Windows. The session core in
`finos/morphir-host/worker` sees only a `Channel` that carries whole MEP
messages. This package supplies that channel for an executable artifact: it
checks the bytes, starts them in an isolated process, frames messages on the
process's stdin and stdout, keeps the end of its stderr, and stops the whole
process tree when the session ends.

The rules come from `specs/extensions/process-workers` in the OpenSpec change
`host-extensions-as-workers`, and from its design decision PROC-1. The Node
launcher for the npm CLI is a separate package, `process/node`.

## A worker from start to stop

Assume that the host must run the Elm extension executable for
`aarch64-apple-darwin`. The pin gives its path and its SHA-256, and the runtime
`Process(platform=Aarch64AppleDarwin, args=[])`.

1. `ProcessLauncher::launch` makes sure that the runtime is a process for a
   platform that the machine runs. Otherwise it refuses with
   `RuntimeUnavailable` or `PlatformMismatch`. `host_machine` takes the
   operating system and the architecture from this executable. On Linux it
   finds the C libraries from their dynamic loaders, for example
   `/lib64/ld-linux-x86-64.so.2` for glibc and `/lib/ld-musl-x86_64.so.1` for
   musl, and runs no program. A static musl host on a glibc machine therefore
   runs `x86_64-unknown-linux-gnu` artifacts.
2. `stage` opens the artifact without following a symbolic link, reads it and
   hashes the bytes that it read. If the hash is not the one in the
   specification, it refuses with `DigestMismatch` and no process starts. It
   writes the same bytes to a new private directory, as `bin/<name>`, which only
   the host's user can read and run, and makes an empty `work` directory. On
   Windows a name without an extension gets `.exe`
   (`VerifiedArtifact::copy_name`), the same rule as in the Node launcher.
3. The launcher starts `bin/<name>` with the specification's arguments,
   unchanged, `work` as the working directory and an empty environment. The
   worker inherits only its three standard streams.
4. The session core sends and receives messages. The channel writes each one as
   a Content-Length frame and reads frames from stdout. While any call runs, it
   also reads stderr, so that a worker that writes much to stderr cannot block.
5. After `exit`, `close` closes the worker's stdin and gives it 2 seconds to
   stop. Then it stops the whole tree and confirms that no process from it
   runs. Only then does it remove the private directory and return.

On Linux an exec of a file that a process holds open for writing fails with
`ETXTBSY`. While the host stages one worker, the child of another spawn can
inherit the write descriptor of that copy and hold it until its own exec. The
launch therefore tries again for up to 1 second while the copy is busy.

A later change to the original file does not change what runs: the process
runs the private copy of the bytes that the host hashed. The read of the
artifact is a blocking read on the event loop's thread, so other tasks of the
host wait while it runs: for the largest artifact, 512 MiB, as long as the
disk takes to supply it. A launch that is
cancelled leaves no process and no private directory. The private directories
are in the system's temporary directory, or in the `staging_root` given to
`ProcessLauncher::new`.

## Isolation

| Rule | Unix | Windows |
| --- | --- | --- |
| Environment | Empty | Only `SystemRoot`, which Windows system libraries need |
| Working directory | Empty private `work` directory | The same |
| Arguments | Forwarded as an array, unchanged, including empty values and `--` | Quoted with the Microsoft C runtime rules, so the worker gets the same array |
| Open handles | Three pipes; every other descriptor is closed: `POSIX_SPAWN_CLOEXEC_DEFAULT` on macOS, `closefrom` on glibc 2.34 and later, and on musl and older glibc a scan with `fcntl` that adds a close action for each descriptor that is not close-on-exec | Three pipes, through `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` |
| Process tree | A new process group, with the worker as its leader | A new job object with kill-on-close; the worker joins it before it runs code |

## Stopping the tree

The host owns the worker's whole tree, not only the process that it started.

- On Unix the worker leads a new process group. A stop sends `SIGTERM` to the
  group and waits 200 ms for the leader. When the leader has exited, the
  host gives the rest of the group 200 ms more to exit. Then, if a process
  remains, it sends `SIGKILL` to the group.
- On Windows a stop terminates the worker's job object.
- In both cases the host then confirms that the tree is gone: no live process
  remains in the group, or the job has no active process. A process that has
  exited but that its parent has not reaped yet runs no code, so it does not
  count. The confirmation has a bound of 5 seconds. The pause between two
  checks starts at 5 ms and doubles to at most 50 ms: on Linux each check
  reads the status of every process in `/proc`.

When the worker exits during the grace period, the host still stops anything
that the worker left in its tree. The report then gives the exit status and the
stop method `GroupSignal` or `JobTermination`. When nothing was left, the stop
method is `ExitedAfterExit`. On Windows the host decides by the job's active
process count when the leader exits: above 0, it terminates the job, reports
`JobTermination` and confirms that the count reaches 0. The worker starts with
`CREATE_NO_WINDOW`, so it gets no console window.

On Windows the host quotes an argument on the worker's command line only when
it needs quotes: when it is empty or holds a space, a tab, a newline, a vertical
tab or a double quote, by the rules of the Microsoft C runtime. A program such
as `cmd.exe` that reads its switches from the raw command line then sees `/c`,
not `"/c"`.

| Event | Stop status |
| --- | --- |
| The worker exits within 2 seconds of `close` | `Exited(code)` or `Signalled(signal)` |
| The worker does not exit within 2 seconds | `Terminated(GraceExpired)` |
| `abort(Deadline)`, `abort(Cancelled)` or `abort(Fault)` | `Terminated(reason)`, at once |
| The caller of `close` is cancelled during the grace period | `Terminated(Cancelled)`, at once |
| A frame from the worker is not valid or is too large | `Terminated(Fault)`, at once, and `receive` raises the fault |
| The host cannot confirm that the tree is gone | `Unconfirmed(reason)`; the host keeps the private directory |
| The host cannot remove the private directory within 2 seconds | `Unconfirmed(reason)` |

The first stop wins. An `abort` during the grace period of `close` stops the
tree at once, and both calls return that stop. After a stop, and in a
`receive` that a stop overlaps, `send` and `receive` raise `Stopped`. During
the grace period the host reads and drops stdout, so a worker that writes
after `exit` cannot block on a full pipe.

The end of the worker's stdout, and a write to a worker that has closed its
stdin, raise `WorkerClosed`. A `receive` also watches for the exit of the
worker's leader. After the exit, the bytes that the leader wrote are in the
pipe already, so a read that gets no bytes for 200 ms is the end of stdout.
A grandchild that keeps stdout open thus cannot hold a `receive` until the
session's deadline. Any other read or write fault on the three pipes
raises `TransportFailed` with the operating system's message.

If the host itself exits, the system closes its end of each worker's stdin, so
the worker reads end of file. On Windows the job handle also closes, and
kill-on-close terminates the job.

A process that leaves its process group on Unix, with `setsid` or `setpgid`,
is outside the tree that the host can stop. This is a limit of process groups:
any process can start a new session or join another group, and the host does
not see it after that. Windows jobs do not allow breakaway in this package.

The C stub makes the three pipes itself, not `@pipe.pipe()` (a deviation
from PROC-1). The stub registers no worker end and the host wraps only its own
ends, one at a time, with `@raw_fd.RawFdStream`. If a wrap fails, the host
closes the streams that it made and the ends that are left, and stops the
worker. On Linux the stub also makes each pipe atomically close-on-exec (see
below).

The deviation started as a workaround for moonbitlang/async#571. Before
moonbitlang/async 0.22.6, `@pipe.pipe()` registered both ends of a pipe with
the host's event loop. When the worker's end was shared with the child,
closing the host's copy left its epoll registration alive, and a later pipe
that reused the descriptor number got false readiness: its reads failed with
`EAGAIN`. Version 0.22.6 removes each registration before it closes a
descriptor (moonbitlang/async#663). The stub-made pipes stay for the reasons
above, and the regression test "many concurrent sessions see no transport
fault" stays too.

The worker's own spawn passes only its three ends, so a worker never inherits
another worker's pipes or any other descriptor of the host. Other programs
that the host starts at the same time are a different case:

- On Linux the stub makes each pipe with `pipe2` and `O_CLOEXEC`, so no end is
  ever open without close-on-exec.
- macOS has no atomic `pipe2` with `O_CLOEXEC`. The stub sets the flag just
  after `pipe()`. A program that another thread starts in that short window,
  through an API that does not close other descriptors, can inherit an end.
  `@process.spawn` in moonbitlang/async is such an API: it spawns in a
  thread-pool thread. Only processes that the host starts through such APIs
  during the window are affected; the workers that this package starts are
  not. An inherited end of a worker's stdin pipe delays the end of file that
  the worker reads until that other program exits; an inherited end of its
  stdout pipe has the same effect as a grandchild that keeps stdout open
  (see above).
- On Windows the worker's ends of its pipes must be inheritable while
  `CreateProcessW` runs. From the call that makes them inheritable until the
  stub closes them after `CreateProcessW`, another thread's `CreateProcess`
  with `bInheritHandles` and no handle list can inherit them too, with the
  same effects. The stub keeps this window to a few calls.

On macOS, the system can take more than a second to authorize an `exec` when
many processes start at the same time. The 2 second grace period begins at
`close`, so a worker that is still starting then can be stopped by the grace.

## Limits

| Limit | Value |
| --- | --- |
| Artifact size | 512 MiB |
| Frame header | 8 KiB |
| Request frame (host to worker) | `request_bytes` of the limits that the session passes to `launch`; 4 MiB in the host limits |
| Response body (worker to host) | `response_bytes` of the same limits, checked against the declared length before the body is read; 16 MiB in the host limits |
| Stderr kept | The last 64 KiB; the tail says when bytes were dropped |
| Grace period after `exit` | 2 seconds |
| Leader time between `SIGTERM` and `SIGKILL` | 200 ms, then 200 ms for the rest of the group |
| Wait for more stdout after the leader exits | 200 ms |
| Retries while the staged copy is busy (`ETXTBSY`) | Up to 1 second |
| Confirmation that the tree is gone | 5 seconds |

The tests below check that these values are the ones the code uses.

```mbt check
///|
test "the documented bounds are the bounds in the code" {
  assert_eq(@shared.ARTIFACT_LIMIT_BYTES, 512 * 1024 * 1024)
  assert_eq(@shared.EXIT_GRACE_MS, 2000)
  assert_eq(@shared.STOP_CONFIRM_MS, 5000)
  assert_eq(@native.TERM_GRACE_MS, 200)
  assert_eq(@native.EXITED_READ_MS, 200)
  assert_eq(@native.TEXT_BUSY_RETRY_MS, 1000)
  let limits = @worker.Limits::host()
  assert_eq(limits.request_bytes, 4 * 1024 * 1024)
  assert_eq(limits.response_bytes, 16 * 1024 * 1024)
}

///|
test "the stderr tail keeps 64 KiB and marks a truncation" {
  let stderr = @shared.StderrBuffer::new()
  stderr.write(Bytes::make(64 * 1024, b'a'))
  assert_true(!stderr.tail().truncated())
  stderr.write(b"b")
  assert_eq(stderr.tail().bytes().length(), 64 * 1024)
  assert_true(stderr.tail().truncated())
}

///|
test "a frame header above 8 KiB is refused" {
  let reader = @shared.FrameReader::new(limit=1024)
  let refused = try {
    ignore(reader.feed(Bytes::make(8 * 1024 + 1, b'x')))
    false
  } catch {
    @worker.FrameInvalid(_) => true
    _ => false
  }
  assert_true(refused)
}
```

## Tests

`process_test.mbt` turns each scenario of the process-worker spec, except the
Node and npm ones, into a test on Linux and macOS. It uses the POSIX sh fixture
`fixtures/worker.sh`, which needs no other tool than the base system: it echoes
frames, reports its environment and descriptors, starts a grandchild, ignores
`exit` and `SIGTERM`, writes 10 MiB to stderr, and writes text that is not a
frame to stdout. `conformance_test.mbt` runs the shared launcher conformance
suite of `worker/process/conformance`, the same cases as the Node launcher,
with `fixtures/conformance.sh`, a POSIX sh version of the suite's fixture
protocol. The white-box tests check the parts that the scenarios cannot
reach: `unix_wbtest.mbt` the clean-up after a failed wrap of a pipe end, the
artifact read limit and the retry of a busy copy; `tree_wbtest.mbt` the stop
steps and the confirmation with simulated trees.

On Windows, `conformance_windows_test.mbt` runs the same suite with `node.exe`
as the staged artifact and the Node fixture
`worker/process/node/fixtures/worker.mjs`, because the sh fixture needs a
POSIX shell. It finds Node through `MORPHIR_TEST_NODE`, or else the first
`node.exe` on `PATH`. `windows_wbtest.mbt` runs the system's `cmd.exe` with
two `ping` grandchildren and checks that a cancellation leaves no process of
the job and no new `PING.EXE`. It also checks that a copy of `cmd.exe` whose
name has no extension is staged as `bin\<name>.exe` and runs, and that a
private directory that the host cannot remove, because the test holds a file
in it open with no sharing, makes the stop `Unconfirmed(GraceExpired)`. `windows_test.mbt` checks the command-line
quoting on every host.

Run them from the repository root:

```bash
moon test --target native pkgs/morphir-host/worker/process/native
```
