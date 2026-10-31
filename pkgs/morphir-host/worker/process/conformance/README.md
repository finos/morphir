# Process launcher conformance suite

`finos/morphir-host/worker/process/conformance` is one suite of transcripts and
fault cases that every process launcher must pass. The native launcher
(`worker/process/native`) and the Node launcher (`worker/process/node`) run the
same cases, so a session behaves the same way on each host.

## How a target runs the suite

A target package implements the `Fixture` trait for its launcher and calls
`check` from a test:

```moonbit
async test "process launcher passes the launcher conformance suite" {
  @conformance.check(MyFixture::{ })
}
```

`check` runs every case in `cases()`, aborts every channel that a case started,
and fails with the name and error of each failed case. A case has 30 seconds.

The `Fixture` trait has four methods:

| Method | What it supplies |
| --- | --- |
| `start(flags, args, limits)` | Starts the fixture worker through the launcher with the limits. The worker's argument array is the flags, then `args`, unchanged. |
| `alive(pid)` | Whether a process with that ID still runs on the host. |
| `ownership()` | How the launcher owns the worker's tree: `Group` (Unix process group), `Job` (Windows job object) or `RootTree` (`taskkill /T` from the root). |
| `documented_environment()` | The environment variables that a worker may see: those that the launcher passes and those that the platform adds to every process. |
| `held_open()` | Optional. Files that the host holds open while it starts workers, as `device:inode`. The default is none. The Node test keeps a marker file open. |

## The fixture worker protocol

A fixture worker reads Content-Length framed JSON-RPC messages on stdin and
writes framed responses on stdout. The Node fixture is
`worker/process/node/fixtures/worker.mjs`. A native fixture must behave the same
way.

Start flags:

| Flag | Behaviour |
| --- | --- |
| `--grandchild` | At start, the worker starts a grandchild that runs until it is killed. The grandchild stays in the worker's process group and tree. On Windows the Node fixture starts it detached, because libuv puts a child that is not detached in its own kill-on-close job, which would stop the grandchild with the worker; a detached child stays in the host's job object. |
| `--ignore-exit` | The worker stays alive after `exit` and after the end of its stdin. |
| `--ignore-stdin` | The worker never reads its stdin and stays alive. |
| `--flood-on-exit` | At `exit` or the end of its stdin, the worker writes 1 MiB to stdout and exits after the write. |

A request is `{"jsonrpc":"2.0","id":N,"method":M}`, with `params` for some
methods. A response is `{"jsonrpc":"2.0","id":N,"result":R}`.

| Method | Worker behaviour |
| --- | --- |
| `echo` | Responds with `params` as the result, or `null`. |
| `argv` | Responds with `{"args":[...]}`: every argument after the program and, for an interpreter, its script. |
| `env` | Responds with `{"names":[...]}`: the sorted names of its environment variables. |
| `cwd` | Responds with `{"entries":N,"mode":M,"ownedByWorker":B}`: the number of entries in its working directory, the directory's permission bits and whether the worker's user owns it. On Windows `mode` and `ownedByWorker` are `null`. |
| `fds` | Responds with `{"descriptors":[{"fd":N,"id":"device:inode"},...]}`: its open descriptors, from `/dev/fd`. On Windows `descriptors` is `null`: the case does not apply. |
| `console` | Writes `x` and a bare LF with `console.log`, then does not respond. |
| `pids` | Responds with `{"worker":P,"grandchild":G}`. `G` is `null` without `--grandchild`. |
| `hang` | Does not respond. |
| `stderr` | Writes `params.bytes` bytes of `e` and then `\nstderr end\n` to stderr, then responds with `{"written":N}`. |
| `log` | Writes `worker log line\r\n\r\n` to stdout, which is not a frame. Does not respond. |
| `oversized` | Writes the header `Content-Length: 16777217` and no body. Does not respond. |
| `crash` | Exits with code 3 at once. |

The notification `exit` (no `id`) makes the worker exit with code 0, and so
does the end of its stdin. `--ignore-exit` disables both.

## Cases

| Case | What it checks |
| --- | --- |
| echo round trip and exit | Two requests and responses, `exit`, then `close` reports `Exited(0)` by `ExitedAfterExit` with an empty stderr tail. |
| arguments forwarded unchanged | Empty strings, spaces, `--`, a leading `-` and quotes reach the worker unchanged. |
| environment holds only documented variables | The worker sees no variable of the host's environment. The Node test sets `MORPHIR_HOME` and a token variable on the host first. |
| working directory is empty and private | The working directory has no entries. On Unix its mode is 0700 and the worker's user owns it. The Node fixture runs every case on the output of the launcher's own staging. |
| worker inherits no descriptor that the host holds | The worker has descriptors 0, 1 and 2, and no other descriptor is a file in `held_open()`. Not applicable on Windows. |
| log on stdout is an invalid frame | A log line on stdout gives `FrameInvalid`; `abort(Fault)` stops the tree. |
| console output before a frame is an invalid frame at once | `console.log("x")` and then a hang give `FrameInvalid` within 5 seconds, not a deadline. |
| oversized response is refused at its declared size | With the host limits, a declared 16 MiB + 1 frame gives `FrameLimit(direction=Response, declared=16777217, limit=16 MiB)` before any body. |
| launch limits apply to requests and responses | With a 256 byte request limit and a 128 byte response limit, a large response gives `FrameLimit(direction=Response)`, and a large request gives `FrameLimit(direction=Request)` before it is written. |
| noisy stderr keeps the last 64 KiB | 10 MiB of stderr during a successful call; the stop keeps the last 64 KiB and marks it truncated. |
| early exit closes the stream | A worker that exits before it responds gives `WorkerClosed`; `close` reports `Exited(3)`. |
| deadline stops the worker and its grandchild | A timed-out `receive` passes the cancellation through; `abort(Deadline)` reports `Terminated(Deadline)` by the tree method, and neither process runs after it. |
| cancellation stops the worker and its grandchild | The same for a cancelled task and `abort(Cancelled)`. |
| worker that ignores exit is stopped after the grace | `close` waits the 2 second grace, then reports `Terminated(GraceExpired)` by the tree method; neither process runs after it. |
| abort during the grace wait wins | An `abort(Deadline)` during the grace wait ends the wait at once; `close` and `abort` return the same stop. |
| first stop is kept and later calls are refused | Later `close` and `abort` calls return the first stop; `send` and `receive` raise `Stopped`. |
| end of stdin stops the worker | `close` without `exit` ends stdin, and the worker exits. |
| worker that writes after its input ends exits within the grace | The host drains stdout during the grace, so a worker that writes 1 MiB after `exit` reports `Exited(0)` by `ExitedAfterExit` before the grace ends. |
| send to a worker that does not read stdin passes the deadline | A 2 MiB request to a worker that never reads stdin blocks; a timeout passes the cancellation through, and `abort(Deadline)` reports `Terminated(Deadline)` by the tree method. |
| receive that overlaps an abort raises Stopped | A `receive` that waits while `abort(Fault)` runs raises `Stopped`, not `WorkerClosed`. |
| descendants stop after the worker exits | For `Group` and `Job` only: after a clean exit, the host also stops the grandchild. `RootTree` cannot reach it (see the Node package README). |
