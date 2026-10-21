# MoonBit MEP process extension

Native stdio adapter composing the pure MoonBit frontend and generator. Protocol output is
reserved for Content-Length framed JSON-RPC messages. Transport errors go to
stderr, and the process writes no generated files itself.

The first backend accepts target `moonbit` and checked Morphir JSON in the IR 4
family. It does not accept generation options. The generator retains its normal
unsupported-input diagnostics and emits its Ion metadata sidecar unchanged as a
base64 binary artifact under the existing MEP artifact contract.

MEP `0.1` and claims `0.1.0-draft.2` are supported. Hosts can explicitly opt into
MEP `0.2.0-draft.1` with a `modelTransport` offer to use
`morphir.frontend.compileModel` and `morphir.backend.generateModel`. The extension
advertises rich frontend compilation and backend generation. Legacy frontend
`compile`, incremental compilation, fragments, streaming and wire cancellation
remain unavailable. The frontend language is `moonbit`; its typed library
profile is a separate capability, not a language name.

## Rich source compilation

The application supplies a typed frontend provider to the protocol session.
`pkgs/morphir-moonbit` has no dependency on the frontend or engine. Backend-only
embedders can continue using `Session::new()`; the native executable supplies
`frontend=Some(...)`. Compilation and generation tuples are negotiated separately:
permission for one operation never authorizes the other.

The default source profile is `moonbit-model-stable-v1`; explicit
`moonbit-model-experimental-v1` adds capabilities awaiting promotion. The vendor root
capability `moonbitFrontendProfiles` describes it alongside the canonical
frontend language capability. Keeping the vendor declaration at the capability
root lets the typed SDK retain it as an extension member. A host that only knows
legacy MEP must not infer legacy compile support from the frontend type.

Compile requests use the canonical `languageId`, `sources`, `package`, `options`,
`contextDigest` and `output` fields. Exactly one `moonbit` document is accepted,
with a nonnegative integer version and its complete text. External dependencies,
imports and incremental baselines are refused. Supported options are
`typesOnly=false`, `irVersion="4.0.0"` and an optional `profile` selecting the
typed library profile, which is also the default. Unknown options fail.

When supplied, `sources.root` must be absolute. Relative document paths retain
their nesting; absolute `.mbt` document paths are resolved relative to that root.
Without a root, supply a relative path. A URI is accepted beneath an explicit matching root;
it is never opened or fetched. Traversal, encoded path segments and ambiguous
identities are refused. `package.exposedModules` may be omitted or contain exactly
that one module. Empty/private or other exposure selections are refused rather
than ignored.

Successful Ion compilation returns a `MorphirModel` with the semantic IR, the
versioned node carrier described below, source annotations and frontend provenance.
Additional compilation provenance records document URI/version, source root,
package, options and the declared context digest. That attribution establishes no
remote guarantee or host authority. The stable model ID binds package and document
URI. Its logical revision binds source content/version, options and context using
canonical object ordering, independently of the chosen payload codec or bytes.

Both compile codecs use the same negotiated limits as generation. Explicit JSON
compilation runs a loss check: the real frontend's source/naming provenance cannot
be represented by plain Morphir JSON, so it returns `data.lossy_conversion`.
No metadata is discarded and no Ion retry happens implicitly. A plain injected
provider with no extra metadata can produce checked JSON successfully. Existing
JSON generation remains supported.

Compilation is a result sum. Success always includes a model; every compilation
failure, including source errors, lossy export, cancellation and output limits,
omits the model entirely. Malformed or unsupported protocol context returns a
JSON-RPC error. Refusals preserve the session. Source diagnostics retain URI and
zero-based ranges. Embedded callers may supply a cooperative `cancelled` callback;
the sequential stdio guest does not advertise wire cancellation.

## Rich model generation

Initialization intersects complete transport tuples and takes the lower value
of each peer's resource limits. The selected support is frozen for the session.
The two codecs for each supported model operation use envelope `0.1.0-draft.1` and draft IR
`4.0.0`: profile `morphir-model` with `ion-binary`, and profile `morphir-ir` with
`morphir-json`. Target language remains `moonbit`. The JSON payload is a complete
UTF-8 Morphir JSON document; both codecs use canonical padded base64 on the wire.
Legacy initialization grants no rich operations.

The adapter checks payload length, SHA-256, the exact selected tuple and critical
envelope paths. Model and optional evidence payloads share encoded-byte,
decoded-byte and value-node budgets. The defaults are 5,592,408 encoded bytes,
4,194,304 decoded bytes, depth 128 and 100,000 value nodes. MEP counts the root
as depth one and excludes annotations and field names from node counts.

Ion binary passes an iterative length/depth/node scan before the Ion library
constructs values. System values have a separate aggregate node budget equal to
the selected node budget, and are also subject to the selected depth bound.
Shared symbol imports are refused because this transport negotiates no catalog;
local tables and append operations remain supported. The Ion library performs
the full scalar and stream validation. Its fixed 128-container reader ceiling
still applies. Upstream [issue #87](https://github.com/moonrockz/ion/issues/87)
tracks stack-safe parsing without that fixed ceiling.

Rich Ion must contain `morphir_model::{ir, enrichments, provenance}`. An engine
`morphir_pipeline` checkpoint is a different contract and is refused. Only the
semantic `ir` member passes through the IR's JSON-shaped codec. Unknown Ion
enrichments, annotations, numeric precision and decimal scale stay in the
original payload bytes. Successful rich generation returns two retention
artifacts alongside the generator's ordinary artifacts:

- `mep/source-model.ionb`, or `mep/source-model.json` for the JSON tuple, contains
  the exact decoded input bytes as a binary artifact.
- `mep/source-envelope.json` retains the envelope, optional unknown members and
  evidence payloads. Its JSON formatting is not preserved.

The MoonBit adapter recognizes the vendor enrichment owner
`urn:finos:morphir-moonbit:node-metadata:v1`. This is an adapter-specific vocabulary,
not a canonical MEP registration. Its `data` has this layout:

```text
{
  sourceUnitId: "source.mbt",
  sourceAnnotations: [morphir_moonbit_frontend],
  nodes: [{nodeId: "value:example:main#ready", data: /* existing Ion metadata */}]
}
```

Each `nodeId` is explicit and unique. The source unit identity must match frontend
provenance for original spelling hints to apply. Unknown enrichment owners stay
opaque and are never converted to node identities. A duplicate recognized carrier
is refused. Existing generator checks reject unknown source nodes.

Remote required guarantees are refused under the current evidence policy.
Optional evidence is retained and bounded, without establishing a guarantee.
Linked target-name facts require authenticated metadata capabilities supplied by
the embedding host through `Session::new(metadata_capabilities=...)`. The native
stdio executable supplies none and reports `metadata.provider_unavailable` when
such facts require a provider. Wire metadata, provenance and evidence grant no
capabilities.

Frames are limited to 16 MiB and headers to 8 KiB. Partial frames at EOF, duplicate
Content-Length headers and invalid lengths fail the transport. Describe does not
initialize a session. Failed initialization leaves the session uninitialized;
shutdown prevents further requests, and an exit notification terminates it.

## Build and qualify

Use the repository's pinned MoonBit 0.10.16 toolchain:

```text
mise run build:extension
mise run test:mep-process
```

The second command runs the pure protocol and application-provider tests on the
native target and starts real guest processes to check lifecycle messages, rich
compilation and generation, bad-digest recovery, exact Ion retention, checked JSON
refusal, legacy compatibility and malformed-frame refusal. It compiles source,
passes the returned model to generation in the same framed session, then builds
and invokes a generated consumer with the checked-in SDK. The guest writes no
files; only the acceptance host publishes returned artifacts in its scratch space.
Native CI runs it on Linux and macOS. Receipts under `.dev/mep-process/` default to
Ion binary and Ion text, with a JSON view. Process-only receipts explicitly say
that installation was not exercised. Rich process fixtures are retained as
`rich-model.ionb`, `rich-model-request.json` and `rich-model-offer.json`. The source
flow also retains `compiled-model.ionb`, `compiled-envelope.json` and
`compiled-symbols.ionb`.

For the installed flow, set these environment variables before running
`mise run test:mep-process`:

| Variable | Value |
| --- | --- |
| `MORPHIR_MEP_HOST` | Explicit canonical Morphir executable with `extension bundle`, such as a build containing finos/morphir #1050 |
| `MORPHIR_MEP_HOST_SHA256` | Expected SHA-256 of those executable bytes |
| `MORPHIR_MEP_PLATFORM` | Host build target, such as `aarch64-apple-darwin` |
| `MORPHIR_MEP_EVIDENCE` | Optional evidence directory, default `.dev/mep-process` |

Qualification creates a fresh temporary Morphir home and local extension
repository. It bundles, publishes locally, installs and activates the guest, then
checks every returned artifact against the pure generator. It compiles and runs
a Boolean consumer with the checked-in SDK as an explicit workspace member, and
checks that unknown generation options fail through the host. Temporary host and
consumer state is removed afterward. The receipt records source revision and
dirty state, executable digests and the actual target; retained descriptor,
catalog and Ion sidecar evidence accompany a successful installed run.

This gate acquires no host or SDK release and publishes nothing publicly. A
legacy installed-generation receipt does not qualify the installed rich frontend
flow, other operating systems, WASM or component guests. The source-to-consumer
process checks establish the native framed adapter independently of installation.

## Bundle an already-built guest

Set `MORPHIR_MEP_HOST`, `MORPHIR_MEP_PLATFORM` and `MORPHIR_MEP_BUNDLE`, then run:

```text
mise run bundle:extension
```

The bundle output must name a new directory whose parent exists. The canonical
host probes the guest and stages the existing per-artifact release descriptor,
executable and checksum. Publication and installation remain explicit actions.
Native processes run with ambient process rights.

## Portable MEP extension

The portable entry point composes the same session, Boolean frontend and
generator as the native process. It is packaged as `model.wasm` plus binary
`manifest.ion`, with the full referenced dependency graph and pinned compiler,
core, SDK and package identities. Its execution profile is separate from the
source language profile and negotiated operation/model tuples.

```text
bun install --frozen-lockfile
bun install --frozen-lockfile --cwd pkgs/morphir-host/embedding
mise run package:mep-extension
mise run test:portable-mep
node pkgs/morphir-host/embedding/node-mep-cli.mjs .dev/portable-mep/extension
```

Use Node 24.22.0 and pinned MoonBit 0.10.16. Packaging uses Moon to acquire an
explicit build recipe and checked core, then the packaged compiler builds the
complete graph with empty PATH and no MOON_HOME. Its build worker uses a 32 MiB
stack for the upstream parser/compiler. Saved-artifact execution needs no
installed compiler and does not reuse that worker or its stack settings.

The launcher accepts existing Content-Length JSON-RPC on stdin. It loads a fresh
saved instance and serves describe, initialize, `compileModel`, `generateModel`,
shutdown and exit. It advertises `moonbit`, the existing Boolean-library source
profile, exact MEP/model drafts and qualified Ion/JSON tuples. Ion preserves
annotations, source/target names and exact retained payload sidecars. A JSON
conversion that would lose required information returns `data.lossy_conversion`.
IR 4.0.0 remains draft.

The host permits only the three declared byte callbacks. It checks a finite
256 MiB Wasm memory maximum, 16 MiB messages and a 10-second worker call timeout.
Traps, timeouts and infrastructure failures terminate the session and await
worker release. Ordinary protocol refusals preserve it. Unknown notifications
produce no response. Wire cancellation is explicitly unsupported. Infrastructure
diagnostics use stderr, and this profile enables no file logging. There is no
publisher authentication or signed-registry prerequisite for explicit selection.

`MORPHIR_MEP_ARTIFACTS` changes the publication root, default `.dev/portable-mep`.
Publication refuses an existing `extension` directory. Choose a new root to
repackage without overwriting previous evidence. `MORPHIR_MEP_EVIDENCE` changes
the local acceptance evidence directory, default `.dev/portable-mep-acceptance`.
Both acceptance and shared qualification refuse an existing evidence directory
before writing results. Select a new directory for every run, including retries,
to keep reports, outputs and completion receipts from different runs separate.
Local acceptance uses a fresh process and runs the generated Boolean consumer;
it retains the source request, model, complete generated output, consumer source,
result and artifact/host receipts. Its guest runs with empty PATH and MOON_HOME;
the separate acceptance host uses the pinned compiler to build the consumer.
Native acceptance uses the same checks with
its native executable. These local checks supplement the independent shared MEP
runner and do not establish installed canonical CLI qualification.

For independent qualification, select the shared Rust CLI containing
`morphir mck mep guest-run` and `report-check`, with its independently authored
`spec/mep/mck/guest-moonbit-bool.json` kit. Set explicit file and SHA-256 pins:

| Variable | Input |
| --- | --- |
| `MORPHIR_MCK_BIN` | Absolute shared CLI executable |
| `MORPHIR_MCK_SHA256` | Expected executable SHA-256 |
| `MORPHIR_MEP_KIT` | Independent guest kit file |
| `MORPHIR_MEP_KIT_SHA256` | Expected kit SHA-256 |
| `MORPHIR_MEP_MCK_EVIDENCE` | Optional report directory, default `.dev/portable-mep-mck` |

Run `mise run test:portable-mep-mck`. The shared runner launches both native and
saved portable guests with empty PATH/MOON_HOME, owns fixed expectations and
verdicts, and rechecks each report. It records the runner, kit, host executable,
argument vector and exact guest/host-module bytes. The gate builds each exact
returned library and runs the consumer source and assertions supplied by the
shared kit with the pinned compiler and declared SDK. It retains the source
request, generated files, consumer source and result beside each report. Choose
a fresh evidence directory for another run to preserve earlier consumer evidence.
A completion receipt appears only after both reports and consumers pass and the
selected independent inputs remain intact.
The broader shared MEP host suite remains separate from this guest qualification.

The route specification and sequence diagram are stored in shared bead
`morphir-ukvn.5.55.7.3`. Recover them with:

```text
moonx scripts/beads-companion.mbtx design export morphir-ukvn.5.55.7.3
```

This first portable route is core Wasm through the process binding. Direct
Component Model input is unsupported by the production JS loader; the existing
WIT frontend contract does not yet carry this rich model flow. Browser,
desktop, Extism and component bindings retain their own qualification work.
