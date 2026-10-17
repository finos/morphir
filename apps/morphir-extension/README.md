# MoonBit MEP process extension

Native stdio adapter for the existing pure MoonBit generator. Protocol output is
reserved for Content-Length framed JSON-RPC messages. Transport errors go to
stderr, and the process writes no generated files itself.

The first backend accepts target `moonbit` and checked Morphir JSON in the IR 4
family. It does not accept generation options. The generator retains its normal
unsupported-input diagnostics and emits its Ion metadata sidecar unchanged as a
base64 binary artifact under the existing MEP artifact contract.

MEP `0.1` and claims `0.1.0-draft.2` are supported. Hosts can explicitly opt into
MEP `0.2.0-draft.1` with a `modelTransport` offer to use
`morphir.backend.generateModel`. The extension advertises backend generation,
without frontend compilation, streaming or cancellation.

## Rich model generation

Initialization intersects complete transport tuples and takes the lower value
of each peer's resource limits. The selected support is frozen for the session.
The two supported generation tuples use envelope `0.1.0-draft.1` and draft IR
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

Use the repository's pinned MoonBit 0.10.15 toolchain:

```text
mise run build:extension
mise run test:mep-process
```

The second command runs the pure protocol tests on the native target and starts
real guest processes to check lifecycle messages, rich generation, bad-digest
recovery, exact Ion retention, legacy compatibility and malformed-frame refusal.
Native CI runs it on Linux and macOS. Receipts under `.dev/mep-process/` default to
Ion binary and Ion text, with a JSON view. Process-only receipts explicitly say
that installation was not exercised. Rich process fixtures are retained as
`rich-model.ionb`, `rich-model-request.json` and `rich-model-offer.json`.

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
single native target's receipt does not qualify other operating systems, rich
frontend transport, WASM or component guests.

## Bundle an already-built guest

Set `MORPHIR_MEP_HOST`, `MORPHIR_MEP_PLATFORM` and `MORPHIR_MEP_BUNDLE`, then run:

```text
mise run bundle:extension
```

The bundle output must name a new directory whose parent exists. The canonical
host probes the guest and stages the existing per-artifact release descriptor,
executable and checksum. Publication and installation remain explicit actions.
Native processes run with ambient process rights.
