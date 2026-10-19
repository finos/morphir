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
revision and target. Each prebuilt package retains its own optimization setting
in the manifest; the selected assembly setting controls source builds and the
final link. Empty sets are explicit hashes, suitable for
programs that require no standard-library assets. These identities establish
content consistency, not authorship or execution authority.

Low-level providers also expose `build` and `link`. Existing `compile` continues
to build and link one package. The assembly executor retains package-scoped
diagnostics and refuses partial outputs or a missing retained export. Worker
cancellation and disposal retain the lifecycle rules below.

## Persisted artifacts

`prepareArtifact` creates a draft manifest from an assembly result, including the
complete graph, exact compiler/core/SDK and package pins, selected exports, actual
Wasm imports, execution-profile identity, optimization setting, byte length and
SHA-256. An optional identified Morphir model contributes a digest computed from
its supplied bytes. This local manifest schema does not stabilize draft IR 4.0.0.

```ts
import {prepareArtifact, publishArtifact, loadArtifact}
  from '@morphir/moonbit-toolchain';
import {createDirectoryArtifactStore, readDirectoryArtifact}
  from '@morphir/moonbit-toolchain/node';

const saved = await prepareArtifact(result, profile, {
  metadataIon: 'source::{language:"MoonBit", precision:128}',
});
await publishArtifact(createDirectoryArtifactStore(destination), saved, {signal});

// A separate process needs only the saved pair and explicitly selected host services.
const loaded = await loadArtifact(await readDirectoryArtifact(destination), {
  targets: ['wasm'], profiles: [profile], encodings: ['ion'], imports: {},
});
try { console.log(loaded.invoke('answer')); }
finally { loaded.dispose(); }
```

`profile` is an explicit `{id, sha256}` execution-interface contract selected by
the producer and consumer. `destination` is an explicit output directory. Hosts
can supply other transactional stores through `ArtifactStore`; their commit must
expose the complete set atomically. The Node store writes and flushes both files
in private sibling staging, then renames the directory. It uses an exclusive
cooperative-writer lock and refuses existing destinations. A crash may leave a
`.publish.lock` file; inspect its owner before removing a stale lock. Failed or
cancelled writes clean up their staging. Cancellation is checked before commit.

Binary Ion is the default, using the pinned MoonBit Ion codecs. Ordered
annotations, repeated metadata fields, exact integers, decimals, typed nulls and
binary values stay in Ion. Metadata crosses the JavaScript boundary as Ion text.
`encoding: 'json'` explicitly selects a checked JSON manifest; it refuses metadata
that would lose Ion meaning or integer precision. Read it with
`readDirectoryArtifact(destination, 'json')` and permit `json` in the host policy.
This restriction concerns this manifest's JSON encoding; Morphir JSON models
remain supported inputs.

The loader checks the schema, full graph/order, artifact checksum and length,
target, encoding, exact profile contract and actual imports/retained exports.
`WebAssembly.compile` checks the actual module's instruction/proposal support
before instantiation. Required services must already have matching host bindings.
No compiler, registry, source files or build cache is consulted. Integrity and
capability checks do not authenticate the publisher or provide a sandbox.

Loaded artifacts expose only declared exports and release their instance on
`dispose`. In-process Wasm cannot be interrupted during a synchronous export or
start function; use an isolated worker when interruption is required. Disposal
does not dispose host-owned imported resources. Component/native ABIs and shared
MEP/MCK integration remain separate work.

## Generated-library qualification

After installing the build dependencies below, run `mise run test:assembly`.
The MoonBit script prepares a three-module Morphir model, runs the production
generator, and reads Moon's dry-run SDK build recipes and pinned core graph.
It executes none of the compiler commands printed by those recipes. Actual
assembly uses only the packaged compiler with an empty `PATH` and no `MOON_HOME`.

The fixture supplies every selected source file from the real root, integer,
list and basics SDK packages, and the exact prebuilt interface/core bytes for
their complete standard-library closure. The current pin produces 44 packages,
including 38 core packages. It exercises a cross-module reference and an external
SDK addition, then saves each optimization variant and runs it in a fresh process.
Both runs check results, selected exports and exactly-once initialization through
an explicit host import. They also check missing-library and corrupted-core
refusal, and absence of a deliberately unreachable payload.

Source build and linker `noOpt` settings vary while the same pinned prebuilt core
bytes remain optimized. With compiler `0.10.15+943464bfa`, the initial measured
sizes were 17,282 and 18,476 bytes. Both modes removed the unreachable payload;
`noOpt` is not a promise to disable every linker elimination pass. Results are
fixture-specific. They establish this supplied-graph/core-Wasm path, without
extending the production CLI or shared MEP/MCK runner.

Successful temporary publications are cleaned after independent consumption.
Failed workspaces are retained at the printed path. The diagnostic report at
`.dev/assembly-qualification-report.json` explicitly uses JSON, as do Moon's
fixture/build-plan boundaries. The actual model and persisted manifests use
binary Ion. The lightweight qualification also runs in the embedding CI job;
the optional component/native host qualification stays separate.

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

## Bounded byte adapters

`loadByteAdapter(saved, host)` reuses the independent artifact loader for a
versioned byte-exchange execution profile. Select `{profile: 'bytes-v1'}` or
`{profile: 'bytes-diagnostics-v1', diagnostics(event) { ... }}`. Requests and
responses are copied UTF-8 bytes; guest pointers do not cross the boundary.
`exchange` returns a response or terminal exit. Dispose explicitly; traps and
infrastructure failures require a fresh instance. These local draft core-Wasm
profiles are separate from language profiles and MEP/WIT bindings.

The production Workbench codec example, complete assembly task, process bridge
and shared MCK qualification are documented in
[`mck/packaged`](../../../apps/morphir-workbench/mck/packaged/README.md).

## Portable MEP process host

`loadNodeMepAdapter(saved)` loads the separate
`morphir/mep-bytes-v1/v1-draft` execution profile in a Node worker. It accepts
existing MEP JSON-RPC bodies and returns a response, notification silence, or
terminal exit. Use the Node adapter for bounded execution. The lower-level
`loadMepAdapter` is synchronous and cannot interrupt a running guest.

The profile requires one unshared wasm32 memory with a maximum of 4,096 pages,
256 MiB. Requests and responses are limited to 16 MiB. The Node host applies a
10-second timeout per load/call and awaits worker termination on timeout, trap,
exit or disposal. Concurrent requests are refused. Protocol refusals from the
guest leave its negotiated session usable; infrastructure failures are terminal.
Wire cancellation is unsupported and is not advertised.

```ts
import {loadNodeMepAdapter, readDirectoryArtifact} from '@morphir/moonbit-toolchain/node';
const adapter = await loadNodeMepAdapter(await readDirectoryArtifact('./extension'));
try {
  const response = await adapter.exchange(new TextEncoder().encode(requestJson));
  // Preserve the returned JSON-RPC body and its ID.
} finally {
  await adapter.dispose();
}
```

The executable `node-mep-cli.mjs` adds existing Content-Length framing with
backpressure and strict byte limits. Importing `runMepExtension` starts no I/O;
call it explicitly to serve stdin/stdout. The guest has only indexed byte input
and output callbacks, with no filesystem, network, browser or WASI services.
Infrastructure diagnostics go to stderr; no file logging is enabled by this
profile. The host process itself has ordinary Node process access.

See the [portable extension instructions](../../../apps/morphir-extension/README.md#portable-mep-extension)
for packaging and operation qualification. This profile is core Wasm. It does
not claim Component Model, browser, installed CLI or additional source support.
