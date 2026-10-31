# WASM workers

These packages run a Morphir extension that is a WASM module as a worker of the
CLI. The session core in `finos/morphir-host/worker` sees only a `Channel` that
carries whole MEP messages; these packages supply that channel for a module, on
the native CLI and on the npm CLI. The rules come from
`specs/extensions/wasm-workers` in the OpenSpec change
`host-extensions-as-workers`, and from its design decisions WASM-1 to WASM-4.

| Package | Targets | Holds |
| --- | --- | --- |
| `worker/wasm` | all | The import and export reader, the ABI classifier, the memory-maximum rewrite. |
| `worker/wasm/guest` | native, js | The `morphir-bytes-v1` and Extism adapters over the `moonrockz/extism` engine, and the worker report. |
| `worker/wasm/native` | native | The `morphir extension worker` mode and the native WASM launcher. |
| `worker/thread` | js | The Node worker-thread launcher. |
| `worker/thread/entry` | js | The entry module of a worker thread, shipped as `dist/wasm-worker.js`. |
| `worker/browser` | js | The browser Web Worker launcher and the message-port channel (BRW-1, a feasibility proof). |
| `worker/browser/entry` | js | The entry module of a browser Web Worker. Nothing ships it yet. |
| `worker/browser/proof` | js | The proof program that `tests/wasm-host/worker-proof.mts` runs on Node and in Chromium. |
| `worker/wasm/fixtures` | all | Crafted modules for the tests. |

The design puts all of the WASM code in one package. It is split because the
engine of `moonrockz/extism` builds only on native and js, while the reader and
the classifier build on all four targets.

## A guest from start to stop

Assume that the native CLI must run the Python extension `0.4.2`, a module of
4.7 MB that imports eight Extism kernel functions.

1. `WasmModule::read` reads the type, import, function, memory and export
   sections. `classify` finds imports from `extism:host/env`, so the profile is
   `extism-kernel-v1`. Every import must be in that profile's import surface,
   with the surface's type, and the module must export `handle` as
   `() -> i32`. An import outside the surface, such as `env.open_socket`, is
   refused with `extension.abi_unsupported` and its name; a module without
   that export is refused with the same code and the message "the module
   does not export handle as () -> i32". A declared ABI that differs is
   refused with `extension.abi_mismatch`.
2. `with_memory_ceiling` sets the memory maximum to 256 MiB, because the module
   declares none. A shared, 64-bit or second memory is refused with
   `extension.wasm_feature_unsupported`; a memory section with no memories is
   a module without memory. An initial memory above the ceiling fails with
   `extension.memory_limit` before any instantiation. The engine's pure feature scan refuses
   any other feature that the engine does not have, by its name.
3. When the process first needs a WASM worker, the native launcher reads the
   CLI's own executable (through `/proc/self/exe` on Linux; on macOS and
   Windows the real path must be a regular file), hashes the bytes it read and
   writes a private copy. It keeps the copy and its digest until the CLI is
   done, and every worker runs that copy. Each worker gets its own private
   directory with the module and an empty `work` directory. It starts the copy
   as a process worker:
   `morphir extension worker --abi extism-kernel-v1 --module <path>
   --build-identity <hex> --request-bytes <n> --response-bytes <n> --json`.
4. The worker checks the build identity, loads the module with the Extism
   adapter, reports `started` on stderr, and answers each Content-Length frame
   on stdin with a frame on stdout, until `exit`.
5. When stdout ends early, the launcher's channel reads the last `fault` or
   `refused` event of the report and raises `GuestFailed` or `Refused`, so the
   session ends with the guest's own code.

Steps 1 and 2 run before any process or thread starts, so a refusal costs
nothing.

## Profiles and adapters

`morphir-bytes-v1` imports exactly `morphir_bytes_v1.input_len`,
`input_byte` and `output_byte`. The result of `handle` is the length of the
response when it is positive, exit when it is 0, a notification when it is -2
and a failure when it is -1. -2 for a request, a message with an `id`, is a
failure, not a wait: the host would wait for a response that the guest does
not give. Requests and responses must be valid UTF-8.

`extism-kernel-v1` may import the Extism kernel and host functions
(`extism:host/env`), the four Morphir host functions (`extism:host/user`) and
any WASI preview 1 function with its witx type. The adapter keeps one plugin
instance for the session and calls `handle` once per request. It delivers no
notification, and `exit` ends the instance. The host functions follow WASM-4:

| Imports | Policy |
| --- | --- |
| `config_get` | No configuration. |
| `var_get`, `var_set` | A store of at most 1 MiB that lives only for the session. |
| `log_*`, `morphir_log` | Guest output, in the report. `get_log_level` gives `info`, and `trace` and `debug` messages are dropped. |
| `http_request` | Refused: the call fails and the report records the method and URL. |
| `morphir_get_workspace_info` | `{"root": <private working directory>, "output_dir": ""}`. |
| `morphir_cache_ir`, `morphir_get_cached_ir` | A cache of at most 16 MiB, keys and values, and 1,024 entries, that lives only for the session; a store over either limit fails the call. |
| WASI preview 1 | No preopens, arguments, environment or stdin; clocks and random bytes; stdout and stderr as guest output; other calls return an error code. The monotonic clock never moves backwards, also when the wall clock does. `random_get` of more bytes than the memory ceiling returns an error code before the random source runs. |

## Bounds

| Bound | Native worker mode | Node worker thread | Browser Web Worker |
| --- | --- | --- | --- |
| Memory ceiling, 256 MiB | Enforced by the engine | Enforced: the rewritten maximum | Enforced: the rewritten maximum |
| Instruction budget, 1,000,000,000 per call | Enforced by WAMR metering | Not enforced: the js engine has no metering | Not enforced: the js engine has no metering |
| Call deadline, 30 s Extism and 10 s bytes | Enforced: the engine interrupts the call | Enforced: the channel terminates the thread | Enforced: the channel terminates the Web Worker |
| Session deadline and cancellation | The process group is stopped | The thread is terminated, and the host waits until it has terminated | The Web Worker is terminated, which is final at once |

`Channel::bounds` states these bounds, and the session report keeps them. An
exhausted budget fails the session with `extension.budget_exhausted`, a passed
call deadline ends it as a deadline, a refused memory growth fails it with
`extension.memory_limit`, and a trap with `extension.guest_trap`.

## The worker mode

`morphir extension worker` is an internal subcommand of the native CLI. The
native entry runs it before it prepares the CLI host, so nothing but MEP frames
reaches stdout.

- stdout carries only Content-Length framed MEP messages.
- stderr carries the report. With `--json`, each event is one line:

```json
{"profile":"morphir/command-event","contractVersion":"0.1.0","command":"extension worker","sequence":3,"event":"fault","fault":{"kind":"trap","message":"Unreachable"}}
```

| Event | Members |
| --- | --- |
| `started` | `abi`, `moduleSha256`, `buildIdentity`, `bounds` |
| `output` | `output`: a guest output as text; or the count of dropped output, with `droppedBytes` |
| `fault` | `fault.kind`: `trap`, `memory-limit`, `call-deadline`, `budget-exhausted` or `failure`; `fault.message` |
| `refused` | `error.code`: an `extension.*` refusal code; `error.message` |
| `exited` | `exitCode` |

A message in an event, of a fault, a refusal or an output, is cut to 4 KiB of
JSON text and ends with `…`, so that the last fault line always fits whole in
the host's 64 KiB stderr tail.

The engine call of a guest blocks the worker, so the worker cannot write while
a call runs. It keeps the call's guest output in a tail: the newest outputs, at
most 64 KiB of reported text, as much as the host's stderr tail keeps. When
the call ends, whatever ended it (a response, a trap, a budget fault or the
engine's call deadline), the worker reports the tail, then one `output` event
with `droppedBytes`, the UTF-8 bytes of guest output that it did not report.
The engine's 30-second call deadline ends a runaway call before the 60-second
session deadline, so its output is still reported. Only a kill of the worker's
process tree at the session deadline loses the output of the call that runs.

Without `--json` the same events are text lines. `--help` writes the help to
stdout and serves nothing; `--help --json` writes a `morphir/command-result`
with `result.help` and `result.buildIdentity`. With `--json`, a usage error is
one `morphir/command-result` failure on stderr, with `error.code` `usage` and
exit status 2, because stdout is the frame stream; without it the error is one
text line on stderr.

| Exit status | Meaning |
| --- | --- |
| 0 | The guest served until `exit`. |
| 1 | A guest fault, an invalid frame, or stdin ended before `exit`. |
| 2 | Invalid arguments. |
| 3 | A refusal before any request: another build identity, an ABI or a WASM feature. |

The build identity is a SHA-256 over the worker contract version
(`morphir-wasm-worker/0.1.0`), the host version, the build stamp, the SHA-256
of the Extism kernel and the engine's features. A worker of another identity
refuses with `extension.worker_runtime_mismatch`.

The build stamp is the CLI version from `apps/morphir/moon.mod` and the git
commit. The pre-build step of `apps/morphir` runs `scripts/build-stamp.mbtx`,
which writes them into the generated file `apps/morphir/build_stamp.mbt`; the
file is not committed, and git's absence gives the commit `unknown`. The
native entry gives the stamp to the launcher and to the worker mode.

The identity has a remaining limit. Two builds of the same commit share an
identity, also when one of them has uncommitted changes, and the pre-build step
runs again only when `moon.mod` changes or the file is missing, so an
incremental local build keeps the commit of its checkout's first build. CI and
release builds start from a clean checkout, so their stamps are exact. Because
every worker runs the copy that the launcher hashed once, a CLI replaced on
disk while it runs does not change its workers. The CLI removes the copy when
it is done; a process that ends abnormally leaves it in its temporary
directory.

## The Node worker thread

The npm CLI runs each guest in a Node worker thread from
`dist/wasm-worker.js`, the entry module that `worker/thread/entry` builds.
`ThreadLauncher::bundled` finds it beside the CLI bundle: it reads the first
frame of a stack trace that names a script, decodes a `file:` URL with
`fileURLToPath` (so spaces, non-ASCII characters and Windows drives work) and
accepts only an absolute path. A launch with an entry path that is not
absolute fails and says so. The thread has an empty environment and writes
nothing to stdout; it posts responses and the same report events through its
port. Node delivers the messages that a thread posts before `process.exit`
before the thread's `exit` event, so the last `fault` or `exited` event
arrives (checked with Node 24: 50 runs of 2,000 messages each lost none).

As on native, the guest's workspace is a private, empty directory: the
launcher makes it in the system's temporary directory, readable only by the
user, gives it to the thread and removes it when the thread has stopped.

## The browser Web Worker

`worker/browser` proves that the same session code runs a guest in a browser
(BRW-1). `BrowserLauncher::new` takes the absolute `EntryUrl` of the entry
module that `worker/browser/entry` builds. Before it starts a Web Worker, the
launcher makes the same checks as the thread launcher: digest, profile,
features and memory ceiling. It refuses a process runtime with
`RuntimeUnavailable` and names WASM as the runtime it supports, and it refuses
a file artifact, because a browser host has no file system. The host refuses
a process runtime first, so a process pin starts no worker.

`PortChannel` is the message-port channel. Its first message gives the guest
its module and limits. These are options of the launcher, not MEP messages;
the MEP messages that follow travel whole and unchanged. The guest posts
responses, the same report events as the Node thread, and an `exit` message
before it closes its scope. A Web Worker has no exit event, so a termination
is final when `terminate()` returns. The guest has no file system and its
workspace has no root. The stop method is `thread-termination`, as for a Node
worker thread.

`tests/wasm-host/worker-proof.mts` runs the proof in Chromium:
`mise run test:wasm-workers -- --target js --scope browser`. The package's
unit tests run each guest at the other end of a `MessageChannel` in the same
thread, so they need no browser.

## Dependency on moonrockz/extism

The engine, the Extism kernel and the plugin API come from the published
Mooncakes package `moonrockz/extism@0.1.0`, which `pkgs/morphir-host/moon.mod`
names. The workspace has no local copy of it.

## Tests with real guests and executables

The package tests run crafted modules on every target. Tests with real guests
and built executables read these variables. Outside CI a missing one skips the
test; with `CI=true` it fails the test:

| Variable | Names |
| --- | --- |
| `MORPHIR_PORTABLE_GUEST` | `model.wasm` of the portable MoonBit guest (`mise run package:mep-extension`) |
| `MORPHIR_NATIVE_GUEST` | The native MoonBit guest (`moon build --target native --release` in `apps/morphir-extension`) |
| `MORPHIR_PYTHON_EXTENSIONS` | A directory with `0.4.1/` and `0.4.2/` release assets of the Python extension |
| `MORPHIR_CLI` | A native CLI build (`moon build --target native --release` in `apps/morphir`) |
| `MORPHIR_WASM_THREAD_ENTRY` | The built entry module (`moon build --target js --release pkgs/morphir-host/worker/thread/entry`) |

`mise run test:wasm-workers -- --target native` (or `js`) builds all of them,
downloads the pinned Python releases and checks their SHA-256, sets the
variables and `CI=true`, and runs `moon test --target <t>` for the workspace.
CI's package tests of the native and js targets run this task, so the
end-to-end tests run there for real. `--scope workers` tests only the worker
package of the target, and `--json` writes one `morphir/command-result`.

```bash
mise run test:wasm-workers -- --target native --scope workers
mise run test:wasm-workers -- --target js --scope workers
```
