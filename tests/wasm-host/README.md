# Wasm host qualification

This opt-in suite builds a real component from MoonBit source and WIT. It supplies
repeatable evidence for `morphir-ukvn.5.55.7` before we choose the portable MEP
adapter. The fixture's `morphir:host-probe` interface is a test contract. It is not
a new MEP binding or a capability advertised by the CLI.

Run from the repository root:

```console
mise run setup:wasm-hosts
mise run test:wasm-hosts
```

Setup installs the frozen test dependencies and Chromium. The check acquires
released tools through mise, generates bindings beneath `.dev/`, builds the
MoonBit guest, validates/packages it, invokes the component in Wasmtime, and
tests jco's generated bindings in Node and Chromium. It does not build Rust.
This task is not added to routine CLI CI or the installed qualification gate.

| Tool | Pin |
| --- | --- |
| MoonBit | `0.10.16+b1a0e846e`, repository toolchain |
| wit-bindgen | `0.63.0` |
| wasm-tools | `1.259.0` |
| Wasmtime | `49.0.3` |
| jco | `1.39.0`, frozen Bun lockfile |
| Playwright | `1.64.1`, frozen Bun lockfile |

The generated canonical ABI uses UTF-16, matching MoonBit strings. Generated
bindings are rebuilt from `probe.wit`; `guest.mbt` replaces their implementation
stub. Separate `resources` and `callbacks` worlds in `lifetimes.wit` exercise
ownership and host imports independently. The runner retains generated resource
helpers and replaces only their implementation declarations with `resources.mbt`.
`callbacks.mbt` forwards to the explicitly supplied host import. Generated files
and reports remain beneath `.dev/wasm-host-qualification/`.

## What the checks establish

| Route | Checks |
| --- | --- |
| Wasmtime CLI, reference host | MoonBit-produced component loads; a record containing Unicode, an enum and Ion binary bytes returns through `result`. |
| jco bindings in Node and Chromium | Non-BMP/combining/NUL text; empty, 64 KiB and arbitrary byte lists; exact Ion and explicit JSON bytes; retained output after subsequent calls and canonical post-return; 105 accepted calls; typed refusal and recovery; idempotent application close; closed result; fresh instance isolation; trap isolation. |
| jco resources in Node and Chromium | Constructor and method; 100 borrowed calls preserve ownership; own transfer invalidates the previous wrapper and destroys exactly once; explicit disposal is idempotent; consumed/disposed handles and cross-instance borrowed/owned use are refused without changing either owner. |
| jco callbacks in Node and Chromium | Explicit host injection; exact Unicode/Ion bytes and empty inputs; host return value; typed host error and recovery; retained callback input after later calls; missing host import refused at instantiation. |
| Node worker | A ready component enters an infinite loop; terminating its worker completes with the expected exit. |
| Chromium worker | A ready component enters an infinite loop; the host requests worker termination and a fresh instance works. Browser workers do not expose an exit acknowledgement. |
| Existing production embedding API, Node and Chromium | Direct component input is rejected with `WebAssembly.CompileError`. It remains a core-Wasm API; jco hosting is not already integrated into it. |

The Ion fixture is a valid IVM plus integer 42. This test transports bytes; it does
not validate or evaluate a MorphirModel. JSON remains explicitly supported and
receives its own byte-preservation case. These tests do not establish MEP
negotiation, compile/generate behavior, host-defined resources, asynchronous
callbacks, reentrancy, memory leak freedom, sandbox enforcement, or production
Workbench/Proton integration. Destruction checks use explicit ownership transfer
and disposal; they do not depend on garbage collection or finalizer timing.
Worker termination is host isolation/cancellation, not component-level interruption.

The guest's borrowed resource method receives a representation, while an `own`
argument receives a handle. The fixture uses representations starting at 1001
to expose confusion between those values. Generated canonical ABI helpers are
not patched.

## Optional native MoonBit embedding

Supply an explicit Wasmoon checkout at
`5490d6bf1cc293c1a3adc42dd3583e607b1ec631`:

```console
MORPHIR_WASMOON_CHECKOUT=/absolute/path/to/wasmoon mise run test:wasm-hosts
```

The suite creates its own workspace referencing that checkout's modules. It does
not clone dependencies, edit the checkout or install a probe inside it. Upstream
native build prerequisites must already work. In the local study, its Python
prebuild selected system Python 3.9; an explicit Python 3.14.7 build-rule path
was needed. The report records the checkout's tracked diff, so such a local
change stays visible. Native runtime semantics were not patched.

The native interpreter checks Unicode/Ion bytes, 101 repeated calls, argument
type refusal, closed result, fresh instance state, an infinite loop stopped by
an execution budget, and refusal after runtime destruction. It does not run the
entire Node/browser case set. An omitted checkout is recorded as `not-run`.

On the pinned source revision, the new fixtures expose two native gaps:

| Fixture | Public facade result |
| --- | --- |
| Guest-owned resource | The constructor's returned value is rejected with `component returned a value incompatible with Own({ identity: "type[0]" }) at result`. Resource methods, borrowing and destruction are **unqualified** for this route. |
| Host callback | Instantiation refuses `morphir:lifetime-probe/host@0.1.0`. The public `ComponentHostInstaller` has no general installer constructor; its published installer is WASI-specific. Callback invocation remains **unsupported** through this public facade. |

Each fixture uses a separate runtime to keep interruption and resource failures
isolated. The native report records these cases as `unsupported`, with the
specific operation and diagnostic. Unexpected failures still fail the task.
The runner does not patch the external runtime or use its private implementation
API to bypass a public-facade gap. Successful completion of the study is distinct
from support for every fixture on every host.

## Evidence and next use

`run.ion` records versions and completed host results. Its spelling is JSON,
which is valid Ion text; the individual JS reports intentionally use JSON for
JavaScript test tooling. Node records all three input components' SHA-256. The old
completion record is removed before each run, and a failed run does not publish
a new one. Logs and individual reports may still exist after a failed run.

The test contract separates tool acquisition from component invocation. `moonx`
can supply a process ToolHost for registry tools and `.mbtx` scripts. An Extism
adapter can reuse the official C/JS SDKs. Neither route is implicitly qualified
by this component fixture. Their separate study evidence lives in the design of
`morphir-ukvn.5.55.7`.

Next qualification should compare a native host with working public callback and
resource APIs, or resolve the pinned facade gaps, before selecting a direct native
component route. Actual MEP model operations and the production JS adapter can
advance using the demonstrated JS route. Keep per-host evidence and capability
claims separate.
