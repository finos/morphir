# Wasm host qualification

This opt-in suite builds a real component from MoonBit source and WIT. It supplies
repeatable evidence for `morphir-ukvn.5.55.7` and its host-specific route decisions. The fixture's `morphir:host-probe` interface is a test contract. It is not
a new MEP binding or a capability advertised by the CLI.

Run from the repository root:

```console
mise run setup:wasm-hosts
mise run test:wasm-hosts
```

Setup installs the frozen test dependencies and Chromium. The check acquires
released tools through mise, builds the production embedding runtimes from frozen dependencies, generates bindings beneath `.dev/`, builds the
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

## Current evidence audit, 22 October 2026

At MoonBit-repo source `4af58d0d3b320c4b81c3212aeff449d8abd02b08`, the clean-checkout
runner needed the embedding build prerequisite added in this change. The completed
rerun uses MoonBit `0.10.16+b1a0e846e`, Node `24.22.0`, Chromium `156.0.8078.4`,
jco `1.39.0`, Wasmtime `49.0.3` and the tool pins above. Node and Chromium pass the
value, callback, guest-resource, refusal, trap, fresh-instance and worker cases.
Browser termination is a request, not an acknowledged exit. This rerun did not
supply the optional native Wasmoon checkout, so that result is **not-run**. The
native unsupported diagnostics above are historical evidence at their exact pin.

The actual components from this rerun have SHA-256 identities:

| Fixture | SHA-256 |
| --- | --- |
| Values | `4d9a5fd82743fabdd89be1f2405a427f39c22229cabed3bdac23200d569947a8` |
| Guest resources | `231718a3dd2fc3accbe039ee653e32ccd4b76fafad16bffede322e5c852a0c10` |
| Host callbacks | `40fa2815b74338f1fb188e5158aab98e61b36902d3be9487d16505e94304f414` |

Required first-delivery evidence is the saved core-Wasm/Node process route, already
qualified by the separate portable MEP adapter suite. Direct Component Model
integration in the canonical CLI and primary MoonBit CLI remains open work.
Browser and native component-runtime candidates are optional for that first route.

| Actual boundary | Component status | Evidence and remaining gap |
| --- | --- | --- |
| Wasmtime reference CLI, 49.0.3 | Demonstrated bounded record invocation | This is a reference engine, not either production Morphir CLI. |
| jco 1.39.0 in Node/Chromium | Demonstrated adaptation and fixture lifecycle | Generated JS bindings coordinate the core modules. This is not direct component acceptance by `WebAssembly.instantiate`. |
| Production JS embedding in Node/Chromium | Direct components refused | The suite passes actual component bytes to `createEmbeddedToolchain().request({operation:'run', ...})` and requires `WebAssembly.CompileError`. |
| Wasmoon public native facade, pin 5490d6b | Historical values pass; resource/callback gaps | This current run is not-run for native. Do not apply the historical result to another checkout/version/platform. |
| Canonical Extism public loader, Extism 1.30.0 / Wasmtime 43.0.2 | Components refused during module parsing | The same fixture component is validated and runs in the reference host. A core control reaches the separate missing Extism guest-info export. This does not qualify the core fixture as an Extism guest. |
| Primary MoonBit CLI, source 4af58d0 | Component binding not integrated | `apps/morphir/arguments.mbt` registers no component/extension loader. `toolchain run` calls the process provider's `moon run`; the CLI's own Wasm target is a separate fact. |
| Workbench/Proton application paths | Not qualified for components by this suite | The Chromium fixture is a harness, not the shipped desktop/web application's load/invoke path. |

The shared canonical host is inspected independently at finos/morphir
`ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409`, with morphir-rust submodule
`73965e04fc19005f1725d09f95f2dc042d42734a`. Its lockfile uses Extism `1.30.0`
and Wasmtime `43.0.2`. Its installed Wasm activation path calls
`morphir-host-native/src/activate.rs` and the public
`extism::ExtensionContainer` loader. This configuration is distinct from the
reference engine above. The opt-in `canonical-host-probe.rs` fixture tests that
actual public loader; it never labels Extism as a component binding.

A complete matrix must retain the open production-host, native callback/resource
and installed CLI qualification gaps. The guide and this evidence audit do not
close those implementation tasks or claim all intended hosts support components.

### Reproduce the canonical loader refusal

Use an isolated finos/morphir checkout at the exact canonical commit above and
initialize its pinned `ecosystem/morphir-rust` submodule. Keep its root
`Cargo.lock` and normal default feature selection, with no `http` feature.
Copy this directory's `canonical-host-probe.rs` to
`ecosystem/morphir-rust/crates/morphir-host-native/examples/component-host-probe.rs`
in that isolated checkout. Do not modify a shared or dirty checkout. After the
MoonBit suite has generated and validated the fixtures, run:

```console
cargo run --manifest-path /isolated/morphir/Cargo.toml --locked \
  -p morphir-host-native --example component-host-probe -- \
  /moonbit-checkout/.dev/wasm-host-qualification/probe.component.wasm \
  /moonbit-checkout/.dev/wasm-host-qualification/probe.core.wasm
```

On the pinned host this prints:

```text
unsupported: Failed to create plugin: failed to parse WebAssembly module
```

The probe accepts only that exact component refusal, after requiring the core
control to reach `morphir_extension_info` lookup. Unexpected errors and an
unexpected component success fail the probe, prompting a new host assessment.
The test is opt-in and does not add Rust or a component runtime to routine CLI CI.
This execution qualified the loader refusal on Linux ARM64, not every platform.
