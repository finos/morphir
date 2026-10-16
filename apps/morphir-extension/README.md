# MoonBit MEP process extension

Native stdio adapter for the existing pure MoonBit generator. Protocol output is
reserved for Content-Length framed JSON-RPC messages. Transport errors go to
stderr, and the process writes no generated files itself.

The first backend accepts target `moonbit` and checked Morphir JSON in the IR 4
family. It does not accept generation options. The generator retains its normal
unsupported-input diagnostics and emits its Ion metadata sidecar unchanged as a
base64 binary artifact under the existing MEP artifact contract.

MEP `0.1` and claims `0.1.0-draft.2` are supported. The extension advertises only
backend generation, without frontend compilation, streaming or cancellation.
Rich `MorphirModel` operations and negotiated Ion input remain separate work.

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
real guest processes to check lifecycle messages and malformed-frame refusal.
Native CI runs it on Linux and macOS. Receipts under `.dev/mep-process/` default to
Ion binary and Ion text, with a JSON view. Process-only receipts explicitly say
that installation was not exercised.

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
