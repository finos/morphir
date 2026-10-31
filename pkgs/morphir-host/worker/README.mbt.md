# Worker host

`finos/morphir-host/worker` runs Morphir extensions as MEP workers. Extension
acquisition uses it to look at a downloaded artifact and to run an installed
one. The CLI uses it for `morphir extension compile` and `generate`. This page
is for those callers.

The host starts a worker from a typed worker specification, talks MEP to it
through a channel that carries whole messages, and stops it. The same session
logic serves every worker kind: native and Node processes, WASM in a worker
runtime, and Web Workers in a browser. A worker kind does not change which
messages the host sends, which checks apply, or how a result is classified.

## From a catalog entry to a result

Acquisition records an artifact, its SHA-256 and its runtime in the installed
catalog. The `runtime` object has the same form as the `runtime` object of an
extension pin, so both go through one decoder.

A process runtime names a platform and an argument array. The host passes the
arguments to the worker unchanged, including delimiters and empty values. A
WASM runtime may declare its ABI, `extism-kernel-v1` or `morphir-bytes-v1`. A
runtime that mixes the members of both kinds, an artifact without a digest,
an artifact object with members other than `path` and `sha256`, and an
unknown platform are refused.

```mbt check
///|
test "decode a catalog entry" {
  let entry : Json = {
    "artifact": {
      "path": "/home/user/.morphir/extensions/elm/morphir-elm",
      "sha256": "6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6",
    },
    "runtime": {
      "kind": "process",
      "platform": "aarch64-apple-darwin",
      "args": ["mep", "--stdio"],
    },
  }
  let spec = @worker.WorkerSpec::from_json(entry, Posix)
  assert_eq(spec.runtime.to_json(), {
    "kind": "process",
    "platform": "aarch64-apple-darwin",
    "args": ["mep", "--stdio"],
  })
  // A browser host offers WASM artifacts only.
  assert_false(@worker.HostPlatform::Browser.supports(spec.runtime))
  assert_true(
    @worker.HostPlatform::Native(Aarch64AppleDarwin).supports(spec.runtime),
  )
}
```

The platform is a Rust and LLVM target triple, the same names that release
descriptors and `MORPHIR_MEP_PLATFORM` use. The decoder accepts exactly these
eight names:

| Platform | Name |
| --- | --- |
| `Aarch64AppleDarwin` | `aarch64-apple-darwin` |
| `X86_64AppleDarwin` | `x86_64-apple-darwin` |
| `Aarch64UnknownLinuxGnu` | `aarch64-unknown-linux-gnu` |
| `X86_64UnknownLinuxGnu` | `x86_64-unknown-linux-gnu` |
| `Aarch64UnknownLinuxMusl` | `aarch64-unknown-linux-musl` |
| `X86_64UnknownLinuxMusl` | `x86_64-unknown-linux-musl` |
| `Aarch64PcWindowsMsvc` | `aarch64-pc-windows-msvc` |
| `X86_64PcWindowsMsvc` | `x86_64-pc-windows-msvc` |

Paths follow the path style of the host platform: a POSIX path starts with
`/`; a Windows path has a drive or names a server.

## Probe, activate, call, close

The host API has five operations for acquisition:

1. `Host::probe` starts a worker, sends `morphir.extension.describe` and
   `exit`, and returns the extension's identity, version and claims. A probe
   result grants no execution authority, and the host does not keep it.
2. `Host::activate` starts a worker from the stored artifact, its recorded
   runtime and its recorded claims. It sends `initialize` and compares the
   identity and capabilities in the answer with the recorded claims before any
   operation. A drift is `extension.claims_mismatch`.
3. `Session::compile` and `Session::generate` send the one operation of the
   session, with the method of the negotiated protocol line. `Session::close`
   sends `shutdown` and `exit` and reports how the worker stopped.
4. `Host::with_session` activates a worker, runs a function with its session
   and always ends the session: it closes the session when the function
   returns or raises, and aborts the worker when the task is cancelled.
5. `Host::supports` and `Host::runtimes` tell which runtimes the host can
   start.

A session must be closed: until then its worker runs. Use `with_session`
unless you need the session outside one function. The function can close the
session itself to read its report; a second close returns the same report.

`Offer::select(claims, operation, profile?, codec?)` picks what activation
offers from the probed claims: MEP `0.1` for the legacy `compile` and
`generate` methods, or MEP `0.2.0-draft.1` with exactly one model tuple for
`compileModel` and `generateModel`. When several claimed tuples match, the
host's preference decides, Ion and then JSON, not the order in which the
worker declared them. It raises `Refusal` when the claims cannot serve the
operation. The worker must return the offered tuple unchanged.

Activation compares the claims only within the offered protocol line. The
extension ID and version always count. On MEP `0.1` the legacy operations,
the languages with their file extensions, the targets and the IR versions
count. On MEP `0.2.0-draft.1` the languages count for a `compileModel` tuple
and the targets for a `generateModel` tuple. A recorded entry that is missing
or changed is a drift. An offer whose tuple is not in the recorded claims is
`extension.claims_mismatch` before any worker starts. A claim set whose
`critical` member names a path that the host does not read is refused.

The example runs a fake legacy guest on the in-memory channel. A real host
uses the process or WASM launcher instead of `MemoryLauncher`. The example
needs the async event loop, so wasm-gc does not build it (see
[Targets](#targets)).

```mbt check
///|
/// A fake legacy guest: it answers every request, and exits on `exit`.
#cfg(not(target="wasm-gc"))
async fn fake_guest(worker : @worker.MemoryWorker) -> Unit {
  let info : Json = {
    "id": "morphir-elm",
    "name": "Morphir Elm",
    "version": "2.1.0",
  }
  let capabilities : Json = {
    "frontend": {
      "languages": [{ "id": "elm", "fileExtensions": [".elm"] }],
      "irVersions": ["3"],
      "compile": true,
    },
  }
  while true {
    let message = worker.receive() catch { _ => return }
    guard message.json() is Object({ "method": String(name), .. } as fields) else {
      continue
    }
    if name == "morphir.exit" {
      worker.exit(code=0)
      return
    }
    let result : Json = match name {
      "morphir.extension.describe" =>
        {
          "protocolVersions": ["0.1"],
          "extension": info,
          "capabilities": capabilities,
        }
      "morphir.initialize" =>
        {
          "protocolVersion": "0.1",
          "extension": info,
          "capabilities": capabilities,
        }
      "morphir.shutdown" => {}
      _ => { "success": true, "diagnostics": [] }
    }
    if fields.get("id") is Some(id) {
      worker.send(
        @worker.Message::new({ "jsonrpc": "2.0", "id": id, "result": result }),
      )
    }
  }
}

///|
#cfg(not(target="wasm-gc"))
async test "probe, activate, compile and close" {
  let spec = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(b"guest"), @worker.Sha256::of(b"guest")),
    Process(platform=Aarch64AppleDarwin, args=[]),
  )
  // A probe on one worker.
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(Aarch64AppleDarwin),
  )
  let claims = @async.with_task_group(group => {
    group.spawn_bg(() => fake_guest(worker))
    host.probe(spec).claims
  })
  assert_eq(claims.extension_id.to_string(), "morphir-elm")
  // An operation session on a fresh worker.
  let offer = @worker.Offer::select(claims, Compile)
  let (channel, worker) = @worker.MemoryChannel::pair()
  let host = @worker.Host::new(
    @worker.MemoryLauncher::new(channel),
    Native(Aarch64AppleDarwin),
  )
  let request = @worker.CompileRequest::new({
    "languageId": "elm",
    "sources": { "documents": [] },
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => fake_guest(worker))
    host.with_session(
      spec,
      expected=claims,
      offer~,
      deadline=@worker.Deadline::of_ms(30000),
      session => {
        let outcome = session.compile(request)
        assert_true(outcome.class is Completed(_))
        // Close here to read the report; with_session would close it too.
        let report = session.close()
        guard report.stop is Some(stop) else { fail("no worker stop") }
        assert_eq(stop.status, Exited(code=0))
      },
    )
  })
}
```

## Outcomes and errors

Every call returns an `Outcome` with one of six classes. Each class keeps the
guest's diagnostics and the worker's stderr tail.

| Class | Meaning |
| --- | --- |
| `Completed(value)` | The guest answered with `success: true`. |
| `Unsuccessful` | The guest answered with `success: false`, for example for source errors. |
| `Failed(fault)` | A protocol, transport or worker fault, or a JSON-RPC error from the guest. |
| `Refused(code~, message~)` | A check failed before the operation was sent. |
| `Deadline` | The session deadline passed. |
| `Cancelled` | The caller's stop signal fired. |

A diagnostic keeps its severity, code, message, location, related information
and the guest's own data. A malformed diagnostic does not drop the valid ones:
the outcome keeps them and adds a host warning with the code
`extension.unexpected_response` that names the malformed entry by its index. While the worker still runs after a call, the stderr
tail of the outcome is empty; the final tail is in the `WorkerStop` of the
close report. When the worker stops during the call, the outcome has that
final tail.

`probe` and `activate` raise `HostError::Ended` with the early end and a
`SessionReport`. A second call on a session, or a call after it ended, raises
`SessionUnavailable`.

Refusal codes: `extension.request_limit`, `extension.protocol_unavailable`,
`extension.tuple_unavailable`, `extension.claims_mismatch`,
`extension.capability_unavailable`, `extension.platform_mismatch`,
`extension.runtime_unavailable`, `extension.digest_mismatch`,
`extension.abi_unsupported`, `extension.abi_mismatch` and
`extension.wasm_feature_unsupported`.

Fault codes: `extension.incomplete_session`, `extension.frame_invalid`,
`extension.unexpected_response`, `extension.response_limit`,
`extension.describe_failed`, `extension.memory_limit`, `extension.guest_trap`
and `execution.tree_termination_failed`.

A launcher that cannot read the artifact, or cannot start the worker for a
reason without its own code, gives `extension.incomplete_session`.

`Launcher::launch(spec, limits)` receives the limits of the session, so that
the transport applies the frame limits. A frame over a limit raises
`ChannelError::FrameLimit` with its direction. A request frame is refused with
`extension.request_limit`, because the worker never received it; a response
frame fails the session with `extension.response_limit`.

## Limits

The host enforces a 4 MiB framed request, a 16 MiB response, and model
payloads of 2 MiB decoded and 2,796,204 encoded bytes. A `CompileRequest` or
`GenerateRequest` over 4 MiB is refused when it is made, so no worker starts.
When a worker declares smaller model limits, the effective limits are the
smaller of each pair, and a model request is checked against them before it
is sent. The host derives a payload's decoded length from its base64 content
and refuses a payload whose `decodedByteLength` differs: a request with
`extension.request_limit`, a result with `extension.response_limit`.

The host also negotiates depth 128 and 100,000 nodes, but it does not decode
models, so it does not enforce them. The party that decodes the model does:
the guest for a request, the CLI's model decoder for a result. A MEP `0.1` WASM guest also has the restricted Extism
profile: a 256 MiB memory ceiling, 1,000,000,000 instructions and 30,000 ms for
each guest call. The WASM launcher enforces those three. The session report
states the limits that applied.

## Deadlines and cancellation

Every session has a deadline, 60,000 ms by default and at most 594,000 ms. It
covers the start of the worker, activation, the call and the close. When the
deadline passes, or when the caller's `StopSignal` fires, the host stops the
worker without waiting for its reply. The deadline and the signal interrupt a
pending launch, send or receive. `StopSignal::of_token` reads a Moon-Lander
stop token, which SIGINT triggers in the CLI. A stop token has no
asynchronous wait, so the driver reads the signal every 10 ms while it waits.
The host never sends `$/cancelRequest`; the report states `wireCancellation:
false`.

When the task that runs a probe, an activation or a call is cancelled, the
host aborts the worker at once and the cancellation continues. A session that
waits between calls has no running task, so close it, or use `with_session`.

## Targets

The types, the decoders and the pure session state machine (`Conversation`)
build on native, js, wasm and wasm-gc. The `Channel` and `Launcher` traits,
the in-memory channel, the host driver (`Host`, `Session`) and their tests need
the `moonbitlang/async` event loop, which wasm-gc does not have. They build on
native, js and wasm. The browser host uses the js target.
