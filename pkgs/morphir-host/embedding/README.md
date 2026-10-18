# Embedded MoonBit tooling

## Supplied library assembly

`pinPackage`, `assemblyIdentity` and `executeAssembly` build an explicitly supplied
package graph. The packaged pure MoonBit planner validates every package, even
unused packages, and returns dependency order. The asynchronous host adapter
checks the actual content pins and compiler/core/SDK context, builds source
packages, reuses matching prebuilt interfaces/cores, then links each core once.
No registry resolver, installed compiler process or synchronous engine wait is
involved. Node workers and browser workers use the same executor.

```ts
import {pinPackage, assemblyIdentity, executeAssembly, compilerVersion}
  from '@morphir/moonbit-toolchain';

const library = await pinPackage({
  name: 'example/library', role: 'library', dependencies: [],
  input: {kind: 'source', files: [['library.mbt',
    'pub fn twice(n : Int32) -> Int32 { n * 2 }']]},
});
const root = await pinPackage({
  name: 'example/main', role: 'library',
  dependencies: [{name: 'math', pin: library.pin}],
  input: {kind: 'source', files: [['main.mbt',
    'pub fn answer() -> Int32 { @math.twice(21) }']]},
});
const packages = [root, library];
const result = await executeAssembly(tools, {
  root: root.pin, packages, target: 'wasm', exports: ['answer'],
  identity: await assemblyIdentity(compilerVersion, packages),
}, {signal});
```

`tools` is an acquired toolchain and `signal` is an optional cancellation signal.
Its owner disposes it. Explicit exports are retention roots in the selected
package; define exported wrappers for required registrations. Required package
initialization remains the linker's responsibility. `optimized` is the default;
`unoptimized` passes the pinned compiler's `noOpt` setting through both stages.
It does not claim that all linker elimination is disabled.

Package content hashes use the versioned `morphir-assembly-package-v1` canonical
JSON tuple encoded as UTF-8: name, role, sorted exact imports and sorted source
files, or prebuilt interface/core bytes plus build context. Core/SDK set hashes
use `morphir-assembly-set-v1` over sorted names, import names/targets and actual
assets, excluding their context assertions to avoid circular hashes. Every
prebuilt context must separately match those verified set hashes, compiler
revision, target and optimization. Empty sets are explicit hashes, suitable for
programs that require no standard-library assets. These identities establish
content consistency, not authorship or execution authority.

Low-level providers also expose `build` and `link`. Existing `compile` continues
to build and link one package. The assembly executor retains package-scoped
diagnostics and refuses partial outputs or a missing retained export. Worker
cancellation and disposal retain the lifecycle rules below.

`@morphir/moonbit-toolchain` embeds the pinned MoonBit package compiler and a Wasm
execution adapter in browser and non-browser applications. It requires no system
MoonBit installation or Morphir CLI. Morphir owns these host adapters;
`finos/morphir` has its own Rust CLI and separate integration work.

```js
import {createNodeToolchain} from '@morphir/moonbit-toolchain/node';

const tools = createNodeToolchain();
try {
  const compiled = await tools.request({
    operation: 'compile',
    package: 'example/math',
    files: [['math.mbt', 'pub fn answer() -> Int { 42 }']],
    target: 'wasm',
    exports: ['answer'],
  });
  if (!compiled.successful) throw new Error(JSON.stringify(compiled.diagnostics));
  const result = await tools.request({
    operation: 'run', artifact: compiled.artifact, export: 'answer',
  });
  console.log(result.value); // 42
} finally {
  tools.dispose();
}
```

For browsers, import `createBrowserToolchain` from the `./browser` export. Serve
the packaged `dist/browser-worker.js` as a module worker; bundler users can pass
its resolved URL as `workerURL`. The worker is compiled ahead of time and does
not use runtime `eval`. Each compiler invocation has isolated state, preventing
failed diagnostics from leaking into later compilations.

## Host contract

Providers describe `protocolVersion`, `mode`, supported `operations` and `targets`.
The embedded provider supports `info`, `compile` and `run` for `wasm` and `wasm-gc`.
The process provider in the MoonBit `morphir-host/toolchain` package implements
the same request boundary and adds `setup`, `build` and `exec`. Its compile
operation builds an on-disk project; the embedded operation builds in-memory
packages. Choose a provider by its capabilities.

The JS API is asynchronous and transports binary assets as `Uint8Array`. The
MoonBit host boundary is synchronous and uses JSON. Hosts bridging these APIs
must schedule asynchronous work and encode binary assets or use host-owned
handles explicitly; a worker is not implicitly blocked inside the synchronous
engine. Both APIs expose the same operation/capability vocabulary.

Compilation returns diagnostics, an artifact containing `Uint8Array` Wasm bytes,
the package interface and core. Hosts provide dependency interfaces through
`interfaces`, `indirectInterfaces` and `standardInterfaces`, as `[name, bytes]`
pairs, and linked dependencies through `cores`. The compiler and these assets
must match the pinned revision. This package does not implement `moon`'s package
resolver or build graph; callers compile and link their dependency graph explicitly.

For execution imports, use `createInProcessToolchain({imports})` from `./node`,
or inject a compiler factory with `createEmbeddedToolchain(factory, {imports})`
from the root export. The root module has no Node imports or asset downloads.
The factory returns a fresh compiler exposing `buildPackage` and `linkCore`.
Hosts can supply their own workers with `createWorkerToolchain(worker)` and
configure runtime imports inside those workers. JavaScript functions cannot be
transferred through `postMessage`; built-in workers accept cloneable requests.

Worker requests accept `{signal}`. Cancellation terminates the worker and rejects
every outstanding request; create a new provider to resume. `dispose()` does the
same cleanup. Workers can interrupt synchronous compilation and running Wasm.
In-process cancellation checks between stages; it cannot interrupt synchronous
compiler or Wasm execution. User-defined executable code should run in a worker
with the host's limits and import policy.

## Pin and tests

The adapter pins `@moonbit/moonc-worker@0.1.202610123`, compiler revision
`0.10.15+943464bfa`. Compiler APIs are defined by the
[MoonBit worker package](https://www.npmjs.com/package/@moonbit/moonc-worker).
The [upstream toolchain documentation](https://www.moonbitlang.com/blog/moonbit-wasm-toolchain)
also describes matching compiler/core versions.

```sh
# From the repository root.
bun install --frozen-lockfile
bun install --frozen-lockfile --cwd pkgs/morphir-host/embedding
bun run --cwd pkgs/morphir-host/embedding build
bun run --cwd pkgs/morphir-host/embedding test
bun run --cwd pkgs/morphir-host/embedding playwright install chromium
bun run --cwd pkgs/morphir-host/embedding test:browser
```

Tests compile real source and execute it in Node and Chromium, report type errors,
recover after failed compilations, supply host imports, and cancel running workers.
The browser fixture demonstrates a host with no CLI. Node demonstrates general
application embedding. `bun run test` also checks the installed package.
