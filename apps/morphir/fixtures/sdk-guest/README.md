# SDK conformance fixture guest

This WASM guest shows that the CLI's worker host runs an extension from another
toolchain with no change made for it. It is built in Rust with
`morphir-extension-sdk` from finos/morphir-rust at revision
`de35f596a07deb8a3ba25b0f2988b217d111fecf`, for `wasm32-wasip1`. It is a test
fixture, not a published extension.

The guest claims a language that no host knows, `morphir-fixture-flags`, with the
file extension `.flags`. A `.flags` document holds one Boolean constant per line:

```text
# comment
ready = true
blockedNow = false
```

Compile writes one Morphir IR 3 module for each document. Generate (target
`morphir-fixture-flags`) writes the constants back as `.flags` documents, so the
generated files compile back to the same IR.

The module imports the Extism kernel (`extism:host/env`), all four Morphir host
functions (`extism:host/user`: `morphir_get_workspace_info`, `morphir_cache_ir`,
`morphir_get_cached_ir`, `morphir_log`) and WASI preview 1 functions through the
Rust standard library. On each compile the guest uses them and reports the
answers in one `fixture.host` info diagnostic, for example:

```json
{"cacheRoundTrip":true,"morphirLog":true,"wasiArguments":0,"wasiClock":true,"wasiEnvironment":0,"wasiRandomSeed":true,"workspaceRoot":true}
```

`build-receipt.json` records the toolchain, the SDK revision, the source digests,
the full import list and the SHA-256 of `morphir-sdk-fixture-guest.wasm`. To build
it again and compare:

```sh
cd apps/morphir/fixtures/sdk-guest
cargo +1.98.1 build --release --locked --target wasm32-wasip1
shasum -a 256 target/wasm32-wasip1/release/morphir_sdk_fixture_guest.wasm
```

`mise run test:extension-conformance` runs the guest through the native and npm
CLIs and checks its imports, claims, compile, generate and host function answers.
No shared MEP kit profile fits this guest: the shared kits qualify the MoonBit
Boolean library and the Python JSON library profiles, and both name their own
extension. A generic kit profile is follow-up bead `morphir-ukvn.5.64.36.15`.
