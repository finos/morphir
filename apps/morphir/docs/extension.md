# Extension commands on the worker host

`morphir extension describe`, `compile` and `generate` run one Morphir extension
that you select with an explicit pin. The CLI runs the extension itself, on its
own worker host. You do not need Node, a helper module, a services pin or a Rust
build. The native CLI and the npm CLI run the same session code.

The worker host knows no list of languages or extensions. It reads what the
extension claims when it describes itself: its identity, its protocol lines, its
operations, its languages with their file extensions, its targets and its model
tuples. Any extension that conforms to the Morphir Extension Protocol (MEP) and to
a supported runtime runs with no change to the CLI.

This version runs **process workers**: native executables that speak
Content-Length framed MEP on stdio, such as the native MoonBit guest or the Elm
extension executables. It also runs **WASM workers**: a WASM module with the
`extism-kernel-v1` ABI, such as the Python extension, or the `morphir-bytes-v1`
ABI, such as the portable MoonBit guest. The native CLI runs each WASM guest in a
worker process of its own executable, through the internal subcommand
`morphir extension worker`, which users do not run. The npm CLI runs it in a Node
worker thread. The rules are in `pkgs/morphir-host/worker/wasm/README.mbt.md`.

## An example with the native MoonBit guest

The native MoonBit guest in `apps/morphir-extension` is a process worker. Build it
and the native CLI, then write a pin over the bytes that you built. Set
`PLATFORM` to the release platform of your host, for example
`aarch64-apple-darwin` or `x86_64-unknown-linux-gnu`.

```sh
mise run build:extension
moon build apps/morphir --target native --release
guest="$PWD/_build/native/release/build/finos/morphir-extension/morphir-extension.exe"
morphir="$PWD/_build/native/release/build/morphir/morphir/morphir.exe"
digest=$(shasum -a 256 "$guest" 2>/dev/null || sha256sum "$guest")
digest=${digest%% *}
PLATFORM=aarch64-apple-darwin
mkdir -p .dev/extension-example && cd .dev/extension-example
cat > pin.json <<EOF
{
  "contractVersion": "0.2.0",
  "artifact": { "path": "$guest", "sha256": "$digest" },
  "runtime": { "kind": "process", "platform": "$PLATFORM", "args": [] },
  "origin": "local build of apps/morphir-extension"
}
EOF
printf 'pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }\n' > main.mbt
```

Then describe the guest, compile the source and generate a library from the
model. Each operation writes to a new output directory:

```sh
"$morphir" extension describe --extension-pin pin.json
"$morphir" extension compile main.mbt --package acme/rules --output model --extension-pin pin.json
"$morphir" extension generate model/model-envelope.json --output generated --extension-pin pin.json
```

`describe` prints the identity and claims of the guest:

```text
morphir-moonbit 0.1.0: process worker; MEP 0.1, 0.2.0-draft.1; morphir.backend.generate, morphir.frontend.compileModel, morphir.backend.generateModel
```

`compile` writes `model/model-envelope.json`, the model envelope as the guest
returned it, and `model/model.ionb`, its decoded payload. `generate` sends that
envelope back unchanged and writes every returned artifact, including the guest's
sidecars `mep/source-model.ionb` and `mep/source-envelope.json`. With the npm
CLI, use `node apps/morphir/bin/morphir.js` (after `bun run --cwd apps/morphir
build`) or the installed `morphir` command with the same arguments.
`MORPHIR_EXTENSION_PIN` can name the pin instead of `--extension-pin`.

## The pin

A pin is a JSON object with contract `0.2.0`. It names an artifact and its
runtime, which is the same shape that the installed extension catalog records, so
a pin and a catalog entry are read by one decoder.

| Field | Required | Meaning |
| --- | --- | --- |
| `contractVersion` | Yes | `"0.2.0"` |
| `artifact` | Yes | `{"path": <absolute path>, "sha256": <64 hex digits>}` of the executable or WASM module |
| `runtime` | Yes | `{"kind": "process", "platform": <release platform>, "args": [...]}` or `{"kind": "wasm", "abi": "extism-kernel-v1" \| "morphir-bytes-v1"}`; `abi` is optional |
| `descriptor` | No | `{"path": <absolute path>, "sha256": <64 hex digits>}` of a release descriptor (`release.json`) |
| `origin` | Yes | Where the bytes came from, 1 to 2048 characters; the report repeats it |

The CLI refuses a pin with `extension.pin_invalid` when it has an unknown field
(the message names the field), a relative path, a missing digest, a runtime that
mixes process and WASM members, or a platform that is not a release platform.
Process `args` are forwarded to the worker unchanged, as an array, including
empty values and `--`.

The CLI hashes the bytes that it reads and runs a private copy of those bytes, so
a later change to the original file cannot change what runs. A digest that
differs from the pin is refused with `extension.digest_mismatch` and no process
starts.

When the pin names a descriptor, the CLI reads it before it starts any worker: it
checks its digest, finds the one entry in its `artifacts` list with the pinned
artifact's SHA-256 and decodes the `claims` of that entry. A descriptor that
fails one of these checks is refused with `extension.digest_mismatch` or
`extension.descriptor_invalid` and exit status 2, and no process starts. After
the probe, the recorded claims must equal the live claims of the worker. Drift
is refused with `extension.claims_mismatch` and exit status 2, before any
operation.

## What one command does

Consider `extension compile main.mbt --package acme/rules --output model`:

1. The CLI checks its local inputs: the options, the timeout, that `model`
   and `model.morphir-partial` do not exist (the message names the one that
   exists; `extension.output_exists`), and that the parent directory of
   `model` exists (`extension.input_invalid`). It reads and decodes the pin, and
   reads and checks the descriptor when the pin names one.
2. **Probe.** It starts a first worker, sends `morphir.extension.describe`,
   offering MEP `0.2.0-draft.1` and `0.1`, then `morphir.exit`, and stops the
   worker. The answer gives the claims. The descriptor's claims, when the pin
   names a descriptor, are compared with them.
3. **Offer.** The protocol line comes from the claims, not from the pin. A
   frontend that claims `morphir.frontend.compileModel` compiles on MEP
   `0.2.0-draft.1`. The CLI offers every model tuple that it supports, in its
   order of preference: `morphir-model` with `ion-binary` (the default), then
   `morphir-ir` with `morphir-json`. The extension agrees on the offered tuples
   that it supports, in the CLI's order, and the session uses the first agreed
   tuple. Thus an extension that supports only JSON compiles with JSON, with no
   error. `--model-format` requires one tuple, so the CLI then offers only that
   tuple. Only an empty agreement is refused, with
   `extension.tuple_unavailable`. An agreement that holds a tuple that the CLI
   did not offer, or that does not keep the CLI's order, is refused with
   `extension.agreement_mismatch`. Both refusals send no operation and exit
   with status 2. A frontend that claims only
   `morphir.frontend.compile` compiles on MEP `0.1`. An operation that the
   extension does not claim is refused with `extension.capability_unavailable`
   and exit status 2.
4. **Sources.** The CLI selects the language from the claims. When the
   extension claims one language, the CLI uses it. When it claims several,
   `--language` must name one of them. Without `--language`, the command is
   refused with `extension.input_invalid`, and the message names the claimed
   languages. A `--language` that the extension does not claim is refused with
   `extension.capability_unavailable`. Then the CLI reads a bounded snapshot of
   the source file or directory. It reads only the files with the file
   extensions of the selected language, and it sends that language ID at the
   top of the request and in each document. Each document URI is the file's
   path relative to the source base, with percent-encoded segments, and the
   documents are in URI byte order (see
   [Source trees and document URIs](#source-trees-and-document-uris)). A
   frontend that does not claim `multiDocument` compiles one document for each
   request, so a snapshot with more than one source file is refused with
   `extension.capability_unavailable`. The walk skips hidden directories (names
   that start with `.`) and the build and dependency directories `.git`,
   `.mooncakes`, `_build`, `node_modules` and `.venv`. Every refusal in this
   step exits with status 2 and starts no operation session.
5. **Session.** It starts a fresh worker from the same verified bytes and sends
   `morphir.initialize`. It requires the returned identity and capabilities to
   equal the probed claims, then sends `morphir.initialized` and the operation.
   It checks the reply's ID, shape and size, then sends `morphir.shutdown` and
   `morphir.exit`.
6. **Stop.** The host confirms that the worker's whole process tree has stopped.
7. **Publish.** Only then does it write the files into `model.morphir-partial`
   and rename that directory to `model` without replacement.
8. **Report.** It writes the summary or the JSON report.

`generate` follows the same steps. Its input selects the line: a model envelope
(with `envelopeVersion`) is sent on MEP `0.2.0-draft.1` with the envelope's
tuple; plain Morphir IR JSON is sent to `morphir.backend.generate` on MEP `0.1`.

### Source trees and document URIs

A Gleam project keeps its modules in a tree under `src`, and the modules import
one another by their path below `src`:

```text
/work/shop/
  gleam.toml
  src/
    app/money.gleam       import shared/numbers
    app/orders.gleam      import app/money
    shared/numbers.gleam
```

Run the compile from the project directory and name `src`:

```sh
cd /work/shop
morphir extension compile src --package acme/shop --output model --extension-pin pin.json
```

The request holds the whole tree as three documents. Each URI is the file's path
relative to the **source base**. Without `--source-base`, the source base is the
directory that you name, here `src`:

```json
{
  "languageId": "gleam",
  "sources": {
    "documents": [
      { "uri": "app/money.gleam", "languageId": "gleam", "version": 0, "text": "..." },
      { "uri": "app/orders.gleam", "languageId": "gleam", "version": 0, "text": "..." },
      { "uri": "shared/numbers.gleam", "languageId": "gleam", "version": 0, "text": "..." }
    ]
  }
}
```

The Gleam guest names the modules `app/money`, `app/orders` and
`shared/numbers` from these paths. It also removes a leading path up to a `src`
segment, so `compile .` from `/work/shop` sends `src/app/money.gleam` and gives
the same module names. The current directory has no effect on the URIs:
`compile /work/shop/src` from any directory sends the same request. The request
has no `sources.root` and no absolute host path, so the model's source
provenance is the same on every machine.

The default suits the published Elm and Python extensions, which also name a
module from its path below the source directory. For example, the Elm
extension requires the module `Acme.Rules.Main` in `Acme/Rules/Main.elm`, so
`compile generated/src` must send `Acme/Rules/Main.elm`, not
`generated/src/Acme/Rules/Main.elm`.

When you name a directory below the root of the module paths, give that root
with `--source-base`. Then each URI is the path relative to the source base, and
the module names do not depend on the directory that you name. This command
sends `src/app/money.gleam` and `src/app/orders.gleam`, so the Gleam guest names
the modules `app/money` and `app/orders`, as for `compile src`:

```sh
morphir extension compile /work/shop/src/app --source-base /work/shop --package acme/shop --output model --extension-pin pin.json
```

Without `--source-base`, the same input sends `money.gleam` and `orders.gleam`,
and the modules are `money` and `orders`.

The input must be the source base or a path below it. The CLI compares the two
paths after it makes them absolute against the current directory and removes
`.` and `..`; it does not resolve symbolic links. An input outside the source
base, such as `/other/src` with `--source-base /work/shop`, is refused with
`extension.input_invalid`, and the message names the source base. A single
file without `--source-base` keeps the earlier rule, so a MoonBit request does
not change: a clean relative path such as `src/main.mbt` keeps its nesting, and
an absolute path or a path with `..` keeps only its file name. A single file
with `--source-base` takes its path relative to the source base.

Each URI segment is encoded as an RFC 3986 path segment. Letters, digits, `-`,
`.`, `_` and `~` stay as they are, so a plain path does not change. Each other
byte of the UTF-8 name is written as `%` and two uppercase hexadecimal digits:
`src/my module.gleam` becomes `src/my%20module.gleam`, and `café.gleam` becomes
`caf%C3%A9.gleam`. Thus a URI never holds a raw `%`, `?`, `#`, `\`, `:`, space,
control character or non-ASCII character. An entry name that is empty, `.` or
`..` is refused, and two files that give the same URI are refused, both with
`extension.input_invalid`.

The documents are sorted by the whole URI in byte order, so `a-c.gleam` comes
before `a/b.gleam` (`-` is `0x2D` and `/` is `0x2F`). Two compiles of the same
tree with the same options send byte-identical `compileModel` requests. The
`contextDigest` is the SHA-256 of the package name and the options only, so
other trees with the same package and options have the same `contextDigest`.

The CLI checks these limits before it starts the operation session. Each refusal
has the code `extension.input_invalid`, exit status 2, and a message that names
the limit and its value, a relative path or a URI:

| Check | Limit | Message |
| --- | --- | --- |
| Documents | 1,024 | `the sources have 1025 documents, more than the limit of 1024 documents` |
| One file | 1 MiB | `the source file src/big.gleam is larger than the limit of 1048576 bytes for one file` |
| All files | 2 MiB | `the sources are larger than the limit of 2097152 bytes of source text in total` |
| Directory entries | 16,384 | `the source directory has more entries than the limit of 16384 entries` |
| Directory depth | 32 | `the source directory src/a/... is deeper than the limit of 32 directories` |
| Links and special files | none allowed | `src/vendor is a link or a special file` (the path relative to the source base) |
| UTF-8 text | every file | `the source file src/my%20latin.gleam is not UTF-8 text` (the URI) |
| No document | at least one | `no source file in docs has a claimed file extension (.gleam)` |

The walk does not follow symbolic links. After these checks, the framed request
must still fit in 4 MiB, because JSON escaping can make a request larger than its
sources; a larger request is refused with `extension.request_limit`.

## Compile and generate options

| Option | Commands | Meaning |
| --- | --- | --- |
| `--extension-pin FILE` | all | The pin; or `MORPHIR_EXTENSION_PIN` |
| `<source>` | compile | A source file, or a directory snapshot of claimed source files |
| `--language ID` | compile | One of the claimed languages; required when the extension claims more than one |
| `--source-base DIR` | compile | The directory that document URIs are relative to; by default a directory source is its own base. The source must be this directory or below it |
| `<model>` | generate | A model envelope, or plain Morphir IR JSON |
| `--package NAME` | compile | The package name; required |
| `--model-format ion\|json` | compile | The one model tuple that the CLI offers on the model line. Without it, the CLI offers Ion, then JSON, and uses the first tuple that the extension agrees on. MEP `0.1` compiles return Morphir JSON and refuse `ion` |
| `--frontend-profile ID` | compile | The frontend profile option on the model line |
| `--ir-version V` | compile, generate | Compile on MEP `0.1`: one of the claimed frontend IR versions; required when the extension claims more than one. An exact claimed name comes first. A major-only name such as `4` selects the highest claimed version with that major (`4.1.0` before `4.0.0`, by number). A full name that is not claimed, such as `4.2.0` or `4.0.0` for a claim of `4`, is refused with `extension.capability_unavailable`. Generate: optional, a check of the model's IR version by the same rule: the model's version equals `V`, or `V` names only its major. On the model line, it checks the IR version of the tuple: `4` or `4.0.0` for `4.0.0` |
| `--target ID` | generate | One of the claimed targets; required when the extension claims more than one |
| `--output DIR` | compile, generate | A new output directory; required |
| `--timeout MS` | all | The deadline for the whole command, from 1 to 594000 ms; 60000 ms by default |
| `--cancel-file PATH` | all | The command stops with exit status 130 when this file exists |

Compile on the model line writes `model-envelope.json` and `model.ionb` or
`model.json`, by the agreed tuple. The CLI checks the payload's tuple, length and SHA-256 before it
publishes. Compile on MEP `0.1` sends the selected IR version as
`options.irVersion` and writes the guest's IR as `morphir-ir.json`. Before it
publishes, the `irVersion` that the result reports and the IR's
`formatVersion` must agree with the selected version, and the IR must decode
with the versioned Morphir IR JSON codec of that version. Otherwise the CLI
refuses the result with `extension.result_invalid` and exit status 1, and
publishes nothing.

Generate on MEP `0.1` takes the IR version from the model's `formatVersion`,
because on MEP `0.1` `irVersion` is a frontend compile option and a backend reads
the version from the IR. The request carries empty `options`, never
`options.irVersion`. Before the session, the backend must claim the model's IR
version (an exact claimed name, or for a major-only `formatVersion` the highest
claimed version with that major), or the CLI refuses with
`extension.capability_unavailable`. An `--ir-version` is optional and acts as a
check: when it is not the model's `formatVersion` or its major only, the CLI
refuses the model with `extension.ir_version_mismatch`. Both refusals exit with
status 2.
Generate on the model line offers and sends the envelope's own tuple, which the
extension must claim (`extension.tuple_unavailable`), and refuses an
`--ir-version` that differs from the envelope's `irVersion` with
`extension.ir_version_mismatch`.
Generate writes the returned artifacts at their relative paths; an absolute,
traversing or repeated path, or a path that is also a directory, is refused with
`extension.result_invalid`. Paths are compared by a key that is
NFC-normalized and case-folded, so `README.md` and `Readme.md`, two Unicode
forms of `café.txt`, or a file `docs` and a directory `Docs/` collide and are
refused, because a case-insensitive or normalizing file system would write them
to one name.

## Report and exit status

In human mode, stdout holds one summary line. Diagnostics, the guest's stderr and
the failure message go to stderr. With `--json`, stdout holds exactly one
`morphir/command-result` `0.1.0` object; `--json-lines` wraps it in
`{"type": "result", "data": ...}`. Progress, diagnostics and the guest's stderr
still go to stderr, so a guest that writes to stderr cannot corrupt stdout. The
report is written after the output is published.

Every report has `profile`, `contractVersion`, `command` (`extension.describe`,
`extension.compile` or `extension.generate`), `state`, `exitCode` and
`diagnostics` (the guest's diagnostics). Success has `state: "succeeded"` and
`result`; failure has `state: "failed"` and `error: {code, message}` instead.

| `result` member | Content |
| --- | --- |
| `worker` | `kind` (`process`), `runtime`, `artifact` (`path`, `sha256`), `origin` and, with a descriptor, `descriptorSha256` |
| `extension` | `id` and `version` from the claims |
| `claims` | describe only: protocol versions, operations, languages, IR versions, the frontend flags (`frontendFlags`: `incremental`, `multiDocument`), targets and model tuples |
| `protocolVersion` | compile and generate: the negotiated line, `0.1` or `0.2.0-draft.1` |
| `negotiated` | `protocolVersion`, the `tuple` on the model line, and the negotiated model `limits`: `maxEncodedBytes`, `maxDecodedBytes`, `maxDepth`, `maxNodes` |
| `bounds` | The enforced bounds: `requestBytes`, `responseBytes`, `deadlineMs`, `stderrTailBytes`, and for compile `sourceFiles` and `sourceBytes`; WASM workers add `memoryCeiling`, `instructionBudget` and `callDeadline`, each `{"enforced": true}` or `{"enforced": false, "reason": ...}` |
| `output` | `directory` and `files`, each with `path`, `bytes` and `sha256` |
| `lifecycle` | `probe`, `shutdown`, `workerStopped`, `wireCancellation: false`, and `worker`: the stop `status`, `code` or `signal`, and `stopMethod` |
| `stderr` | The guest's stderr tail as `text`, and `truncated` |

The exit status is the same in human mode and in JSON mode:

| Exit | Meaning | Examples of `error.code` |
| --- | --- | --- |
| 0 | The operation succeeded and the output is published | |
| 1 | The guest answered `success: false`, the session failed, or the output could not be published | `extension.operation_unsuccessful`, `extension.incomplete_session`, `extension.unexpected_response`, `extension.response_limit`, `extension.guest_error`, `extension.result_invalid`, `extension.output_failed`, `extension.budget_exhausted` (WASM workers) |
| 2 | A pin, identity, claim, negotiation or local input check refused the work before an operation | `extension.pin_required`, `extension.pin_invalid`, `extension.pin_retired`, `extension.option_retired`, `extension.runtime_unavailable`, `extension.platform_mismatch`, `extension.digest_mismatch`, `extension.descriptor_invalid`, `extension.claims_mismatch`, `extension.capability_unavailable`, `extension.protocol_unavailable`, `extension.tuple_unavailable`, `extension.agreement_mismatch`, `extension.request_limit`, `extension.worker_runtime_mismatch` (WASM workers), `extension.ir_version_mismatch`, `extension.input_invalid`, `extension.output_exists` |
| 124 | The `--timeout` deadline passed | `extension.deadline` |
| 130 | SIGINT, the `--cancel-file` or a cancellation of the command's task stopped the command | `extension.cancelled` |
| 143 | SIGTERM stopped the command | `extension.cancelled` |

A cancellation is never reported as `extension.host_failed`: the host stops the
worker's whole process tree, publishes nothing and reports `extension.cancelled`.

Parser errors keep the CLI's syntax status 2 and its existing error output.
`--help` and `--help --json` print the command help and run nothing. The host never
sends MEP wire cancellation; a deadline or a cancellation stops the worker's whole
process tree. A failure leaves no output directory and no
`<output>.morphir-partial`.

## Limits

| Bound | Value |
| --- | --- |
| Pin file | 64 KiB |
| Descriptor file | 1 MiB |
| Artifact | 512 MiB |
| Request frame, host to worker | 4 MiB |
| Response body, worker to host | 16 MiB |
| Frame header | 8 KiB |
| Offered model limits | 2,796,204 encoded bytes, 2 MiB decoded, depth 128, 100,000 nodes; the worker's smaller values apply |
| Generate input | 4 MiB, depth 128, 100,000 nodes |
| Compile sources | 1,024 files, 1 MiB for one file, 2 MiB in total, 16,384 directory entries, depth 32 |
| Guest stderr kept | The last 64 KiB |
| Deadline | 60,000 ms by default, at most 594,000 ms, for the probe and the session together |
| Grace after `exit` | 2 seconds, then the host stops the tree |
| Confirmation that the tree stopped | 5 seconds |

Each process worker runs a private copy of its artifact in a new process group
(Unix), with an empty environment and an empty private working directory, and it
inherits only its three standard streams. A process that leaves its process group
with `setsid` or `setpgid` is outside the tree that the host can stop. Native
process workers have no sandbox beyond this isolation. The rules are in
`pkgs/morphir-host/worker/process/native/README.mbt.md` and
`pkgs/morphir-host/worker/process/node/README.md`.

## Platforms

| CLI | Process workers | WASM workers |
| --- | --- | --- |
| Native, macOS and Linux | Supported | Supported, in a worker process of the CLI (`morphir extension worker`) |
| npm package on Node, macOS and Linux | Supported, through Node `child_process` | Supported, in a Node worker thread |
| Native and npm on Windows x64 and arm64 | Not qualified: the job-object stop is not complete (tasks 2.3, 3.2 and 7.5) | Not qualified, for the same reason |
| WASI builds (`wasm`, `wasm-gc`) | Refused: `extension.runtime_unavailable` | Refused: `extension.runtime_unavailable` |

A process artifact that the machine cannot run is refused with
`extension.platform_mismatch`. The host checks the machine at run time, not
the target of the CLI executable: the operating system and the architecture
must match, and on Linux the artifact's C library must be present. The CLI
finds glibc and musl from their dynamic loaders, for example
`/lib64/ld-linux-x86-64.so.2` and `/lib/ld-musl-x86_64.so.1`, so the static
musl CLI on a glibc machine runs a `x86_64-unknown-linux-gnu` artifact. The
message names what the host has, for example `this host runs x86_64 Linux
with glibc; the artifact needs musl`. Help is available on every build.

## Migrate a pin

The refusal messages point to this section by its URL,
<https://github.com/finos/morphir-moonbit/blob/main/apps/morphir/docs/extension.md#migrate-a-pin>,
because the npm package does not ship the docs.

### BREAKING: retired pins and options

Contracts `0.1.0` and `0.1.0-draft.1` are retired. The CLI refuses them with
`extension.pin_retired`, and refuses `--extension-helper` and `--node` with
`extension.option_retired`, both with exit status 2. `MORPHIR_EXTENSION_HELPER`,
`--services-pin` and `--services-helper` are not read by these commands. Rewrite
the pin as follows; the host, helper and Node runtime fields have no replacement,
because the CLI runs the worker itself.

**Native process (`native-process`, contract 0.1.0).** Before:

```json
{
  "contractVersion": "0.1.0",
  "binding": "native-process",
  "host": { "executable": "/work/adapter", "sha256": "<adapter SHA-256>", "sourceRevision": "fc9f723a…" },
  "artifact": {
    "executable": "/work/morphir-moonbit",
    "sha256": "<guest SHA-256>",
    "extensionId": "morphir-moonbit",
    "version": "0.1.0",
    "args": []
  },
  "origin": "local build"
}
```

After: `artifact.executable` becomes `artifact.path`, `artifact.args` moves to
`runtime.args`, and the runtime names the platform. The identity comes from the
live describe, or from a descriptor.

```json
{
  "contractVersion": "0.2.0",
  "artifact": { "path": "/work/morphir-moonbit", "sha256": "<guest SHA-256>" },
  "runtime": { "kind": "process", "platform": "aarch64-apple-darwin", "args": [] },
  "origin": "local build"
}
```

**Portable core-Wasm guest (`core-wasm-process`, contract 0.1.0-draft.1).**
Before, the pin named a Node runtime, twelve host modules, an execution profile
and an artifact directory with `model.wasm` and `manifest.ion`. After, it names
the WASM module and its ABI:

```json
{
  "contractVersion": "0.2.0",
  "artifact": { "path": "/work/extension/model.wasm", "sha256": "<model.wasm SHA-256>" },
  "runtime": { "kind": "wasm", "abi": "morphir-bytes-v1" },
  "origin": "mise run package:mep-extension"
}
```

**Python Extism bundle (`extism-wasm`, contract 0.1.0).** Before, the pin named a
host executable, a Node runtime, three helper modules and a bundle directory with
`descriptorSha256` and `wasmSha256`. After, it names the WASM file and the
descriptor, each with its own digest:

```json
{
  "contractVersion": "0.2.0",
  "artifact": { "path": "/work/python/morphir-python-binding-0.4.2.wasm", "sha256": "10acafa0f0282c5240e9620a5f2bb21629cc7580b9add528e7b77c7e54db22b5" },
  "runtime": { "kind": "wasm", "abi": "extism-kernel-v1" },
  "descriptor": { "path": "/work/python/release.json", "sha256": "72770f73f05a72535fd8c86ad4629175019037441a758b827c1ba47cc9a52ebd" },
  "origin": "finos/morphir-python extension/python/v0.4.2"
}
```

The two WASM pins run on the native and npm CLIs. The WASI builds refuse them with
`extension.runtime_unavailable`.

### BREAKING: the report schema

All three commands now write one `morphir/command-result` `0.1.0` report and use
one exit table. The portable route wrote `morphir/cli/extension-command`
`0.1.0-draft.1`; the native and Extism routes wrote `morphir/command-result`
with route-specific `result` members and exited 1 on an expected refusal. This
table gives where each old member is now.

| Old member | Where it is now |
| --- | --- |
| `profile: "morphir/cli/extension-command"`, `contractVersion: "0.1.0-draft.1"` | `profile: "morphir/command-result"`, `contractVersion: "0.1.0"` |
| `operation` (`describe`, …) | `command` (`extension.describe`, …) |
| `state`: `completed`, `refused`, `failed`, `cancelled` | `state`: `succeeded` or `failed`; the kind of failure is in `exitCode` and `error.code` |
| `exitCode` | `exitCode`, with the same table in human and JSON mode; refusals now exit 2 on every route |
| `binding` (the verified pin) | `result.worker`: `kind`, `runtime`, `artifact`, `origin`, `descriptorSha256` |
| `access` (`guestImports`, `wireCancellation`, `hostCancellation`, `fileLogging`) | `result.lifecycle.wireCancellation` and `result.bounds`; there is no file logging |
| `extension` | `result.extension` (`id`, `version`) |
| `negotiated` (`protocolVersion`, `tuple`, `limits`) | `result.protocolVersion` and `result.negotiated` (`tuple`, `limits` with `maxDepth` and `maxNodes`) |
| `result` (the guest's raw result) | The published files are in `result.output`; the guest's diagnostics are in `diagnostics`; describe claims are in `result.claims` |
| `output` (`directory`, `files`) | `result.output` (`directory`, `files` with `path`, `bytes`, `sha256`) |
| `lifecycle` (`process`, `exitCode`, `shutdown`, `workDirectoryEmpty`) | `result.lifecycle` (`worker.status`, `worker.code`, `worker.stopMethod`, `shutdown`, `workerStopped`) |
| `stderr` (text) | `result.stderr` (`text`, `truncated`); the guest's stderr is also copied to stderr |
| `error` (text) | `error` (`code`, `message`), on failure only |
| Native/Extism `result.binding`, `result.session`, `result.outputs`, `result.outputDirectory`, `result.access` | `result.worker`, `result.negotiated` and `result.bounds`, `result.output`, `result.output.directory`, `result.lifecycle` |
| JSON-lines record type `extension` | Record type `result` |

Some error codes changed with the new host: `extension.invalid_pin` is now
`extension.pin_invalid`, `extension.explicit_pin_and_helper_required` is
`extension.pin_required`, `extension.identity_mismatch` and
`extension.integrity_mismatch` are `extension.digest_mismatch`,
`extension.unsupported_binding` is `extension.pin_retired` or
`extension.pin_invalid`, `extension.unsupported_target` is
`extension.runtime_unavailable`, `execution.cancelled` is `extension.cancelled`
and `execution.deadline` is `extension.deadline`.

### BREAKING: `--log-file` and `--log-format` are removed

`extension describe`, `compile` and `generate` no longer accept `--log-file` and
`--log-format`; the parser refuses them with its syntax status 2. The guest's
stderr is in the report and on stderr, and the CLI's `--log-level` diagnostics
still apply. Remove the two options from scripts that call these commands.

## Qualification

The routine CLI tests (`mise run test:cli`) run the commands with the native
MoonBit guest from the native CLI, the Node CLI and the installed npm package, on
macOS and Linux: describe, compile and generate into fresh output directories,
with the published digests checked against the files. They also check the
refusals for an existing output, a retired option, a retired pin and descriptor
drift, a guest that writes to stderr in JSON mode, and a cancel file. The CLI
unit tests drive the same command code against scripted in-memory workers for the
session cases: MEP `0.1` compile from claimed sources, an unclaimed operation, an
unsuccessful answer, a failed shutdown, cancellation during generate and the
deadline.

### Published extensions and fixture guests

The published extensions are examples of conformant extensions, not the
definition of support. `scripts/extension-qualification.mbtx` runs them, and an
independent fixture guest, from the native CLI and from the npm CLI, as a user
installs it (an unpacked `npm pack` of `apps/morphir`). Every task accepts
`--json`:

| Task | Suite | What it checks |
| --- | --- | --- |
| `mise run test:cli-extension-elm` | `elm` | Elm extension executables `v0.4.1` and elm-classic `v0.5.1` (process workers): describe with the release descriptor, compile of `apps/morphir/fixtures/elm-extension/v1/src`, and no `node` on the PATH of the native run. Elm `v0.5.0-preview.2` (one WASM module, `morphir-bytes-v1`): describe, compile of `v1/package` on the model line, generate, and recompile of the generated sources to the same model |
| `mise run test:cli-extism-python` | `python` | Python extension `0.4.1`: one document for IR 3 and 4, and the refusal of two documents. `0.4.2`: compile of the two-module fixture for IR 3 and 4, generate, a consumer check of the generated Python, recompile of the generated files to the same IR, and the IR version check |
| `mise run test:cli-native-prerequisites` | `moonbit-native` | The native MoonBit guest as a process worker: the shared kit's source, consumer and JSON artifacts through both CLIs, and the shared MEP kit run against the guest |
| `mise run test:portable-mep-cli` | `moonbit-portable` | The portable MoonBit guest (`morphir-bytes-v1`): the same checks, with the shared kit run through `morphir extension worker` of the native CLI |
| `mise run test:extension-conformance` | `conformance` | The `morphir-extension-sdk` fixture guest in `apps/morphir/fixtures/sdk-guest` (see its README): build receipt, WASI and Morphir host function imports, claims of a language that no host knows, compile, generate, recompile, host function answers and guest diagnostics |
| `mise run test:extension-qualification` | `all` | All five suites |

Each run builds the CLIs and the guests that it needs. It downloads each
pinned artifact of `apps/morphir/fixtures/qualification/published.json` into a
new, empty directory under `.dev/extension-qualification/downloads` and uses it
only when its SHA-256 equals the pin. It writes one receipt for each suite,
`.dev/extension-qualification/evidence/<suite>.json` (`--evidence DIR` selects
another directory). A receipt names the platform, the CLI build (commit, a dirty
flag and the program SHA-256) and one row for each operation: extension,
version, CLI (`native`, `npm` or `mck` for the shared kit runner), operation,
result, guest SHA-256, descriptor SHA-256 and the digests of the published
files. With `--json`, stdout is one `morphir/command-result` with `result.suites`
(state and row counts of each receipt) and `result.receipts`; build and driver
output goes to stderr. A failed suite exits 1 with `qualification_failed`.

A row is `passed`, `failed` or `known-failure`. A known failure is an operation
that fails for a recorded cause outside the host, with its finding and
follow-up bead. It does not fail the suite, and it fails the suite when it
passes, so the record is removed. The current known failures are:

- Elm extension `v0.4.1` compile. The extension requires
  `package.exposedModules` in `morphir.frontend.compile`; the MEP model makes it
  optional and the host, which conforms, does not send it. Describe passes.
  Bead `morphir-ukvn.5.64.36.16`: elm-classic `v0.5.1` (the same JavaScript
  extension, renamed) fixes it, and its compile passes.
- The shared MEP kit against the MoonBit guest. The kit
  `spec/mep/mck/guest-moonbit-bool.json` asks for the frontend profile
  `moonbit-model-bool-library-v1`, which the guest retired, so the case
  `compile-ion` fails after describe, initialize and the notifications pass.
  Follow-up: bead `morphir-ukvn.5.64.36.17` (finos/morphir). For the same
  reason `mise run test:portable-mep-mck` does not pass.

No shared kit profile fits the SDK fixture guest, because each shared profile
names its own extension. The `conformance` suite is therefore a local check. A
generic kit profile is bead `morphir-ukvn.5.64.36.15`.

These tasks are manual. No pull request or merge-queue job runs them, because
they download published releases and build several guests. The workflow
`.github/workflows/extension-qualification.yml`, started only by
`workflow_dispatch`, runs one suite on one runner through
`scripts/extension-qualification-run.mbtx`, which saves the JSON result for the
artifact and keeps the qualification's exit status.

## Controlled local repositories

These commands require `--services-pin host-pin.json` and
`--services-helper /work/apps/morphir/build-provider/native-services.mjs`.
Use `--home /isolated/morphir-home` to isolate state. Otherwise `MORPHIR_HOME`, then
the user's `.morphir` directory, supplies the home. Canonical directory layouts,
release descriptors, digests, locks, catalogs and installation transactions belong
to the shared distribution library.

```sh
morphir extension repository init /work/local-repository
morphir extension repository add local --directory /work/local-repository
morphir extension bundle --executable /work/guest --sha256 <SHA-256> --extension-id morphir-moonbit --short-id moonbit --version 0.1.0 --platform aarch64-apple-darwin --output bundle
morphir extension repository publish bundle --repository local
morphir extension search moonbit
morphir extension install morphir-moonbit --repository local --version 0.1.0
morphir extension list
morphir extension update morphir-moonbit --repository local --version 0.1.1
morphir extension uninstall morphir-moonbit
```

The example omits the common explicit service controls for readability. Repository
`list`, `inspect <name>`, `enable <name>`, `disable <name>`, `verify <name>` and
`remove <name>` complete the lifecycle. Disable excludes a repository from search,
resolution and publication. Bundle accepts an already-built native executable,
probes its declared identity/version and validates the canonical descriptor before
publication. Its current bounded byte bridge accepts artifacts up to 11 MiB and
requires the probing host's exact Rust target triple. Larger bundles, remote
repositories, channels, Wasm installation and cross-platform probing are outside
this adapter. Unsupported syntax is refused, never ignored.

Publish and fresh install use canonical describe probes. Update probes an isolated
materialization of the selected digest before the shared replacement installer
rehashes that digest and atomically replaces state. Its canonical lock retains the
repository claim record; the command also returns its separate probe evidence.
Corrupt bundles, failed probes and corrupt/disabled update selections leave the
previous active installation intact. `extension list` revalidates installed bytes
offline without executing them or reopening the repository. Uninstall removes
active state and retains the shared content-addressed cache. No signed registry or
authenticated publisher chain is required for this explicit local workflow.

Every lifecycle command accepts `--json` and writes one `morphir/command-result`
`0.1.0` object; expected failures exit 1. Diagnostics and child logs go to stderr; successful output appears only
after required writes. These commands do not automatically join installed
selection to invocation. That downstream acceptance remains morphir-ukvn.5.64.30.

`mise run test:cli-native-prerequisites` used to test these commands with the
retired helper route. It now qualifies the native MoonBit guest on the worker
host; see [Qualification](#qualification). The Rust adapter acceptance stays
available as `moon run scripts/native-services.mbtx -- --acceptance --shared
/path/to/finos/morphir --json` until the helper routes are removed.
