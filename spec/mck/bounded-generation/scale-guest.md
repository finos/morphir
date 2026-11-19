# Portable Orders scale guest source checkpoint

`scale-guest.c` is an additive, freestanding `extism-kernel-v1` guest for the
recipe in `scale.md` at finos/morphir commit
`d2804e50be4512907391aa20b6b289471f63eff0`. It does not replace the frozen
Orders guest, controls, recipe or expected inventory. Its JSON exchange,
canonical padded base64 and SHA-256 helpers are adapted from that commit's
`fixtures/wasm/orders-generator.c`. No WASI or runtime library is required.

The guest admits the plain JSON v4 document-tree tuple and target `text`.
It requests pages of at most 16 entries. It retains one root page, one member
page, the current document and fixed-size identity buffers. It follows live
root cursors across modules, ignores the dependent SDK specification, validates
the alias type before values, and consumes every payload body and signature in
inventory order. Module and value names follow the recipe's ordinal naming.
The tiny test equivalent permits 2 through 64 payloads per module. A missing
terminal `total-in-USD` entry is rejected.

Each payload emits its UTF-8 string and LF as one artifact chunk. The final
reference triggers a member inventory rescan using the live member selection.
Only a matching value entry supplies the document ID for the referenced body;
the same-name type cannot satisfy it. References within the current module may
redirect to an earlier payload. The independent artifact comparison must catch
such changes. The resolved string and LF close the artifact with `end: true`.
Offsets are contiguous, and each chunk has a SHA-256 over its exact decoded
bytes. The host remains responsible for full artifact and inventory digests.

Malformed advances return `-32602` without consuming the round or retained
operation state. Opaque identities are decoded and echoed, including escaped
quotes, backslashes and UTF-8. Individual identities are bounded to 256 UTF-8
bytes. There are at most eight distinct sessions per initialized instance.

## Build and focused verification

Run from the repository root with installed Bun, Clang and `wasm-ld`:

```powershell
bun test tools/orders-scale-guest.test.ts
```

The test builds with the commands below in a private scratch directory.
Use these commands from the repository root to retain a module for host runs.
Place the installed Clang and its matching `wasm-ld` on PATH.
The test skips the WASM cases when the compiler or its matching linker is absent.

```powershell
clang --target=wasm32 -O2 -fno-builtin -nostdlib -Wall -Wextra -Werror -c spec/mck/bounded-generation/scale-guest.c -o .dev/scale-guest.o
wasm-ld --no-entry --export-memory -z stack-size=262144 --initial-memory=1048576 --max-memory=1048576 -o .dev/scale-guest.wasm .dev/scale-guest.o
Get-FileHash .dev/scale-guest.wasm -Algorithm SHA256
```

Direct linking avoids optional optimizer invocations. The module exports
`memory` and `handle` and imports the five kernel byte-exchange functions.
Record the toolchain versions and module digest with each host run.

The test shim uses a tiny recipe equivalent with three generated modules,
64 payloads per module and 48-byte payloads. It deliberately returns short root
pages and five member pages per module. Assertions compare complete independent
formula-derived bytes, every chunk digest and offset, the exact artifact path
set, and exactly one closing marker per artifact. Controls cover reference
redirects, a late payload mutation, a 16,384-byte payload, missing final pages,
missing reference targets, type/value order and alias/signature rejection.
Wrong document, request and snapshot identities, stale rounds, wrong byte
lengths, digests and noncanonical base64 are rejected before a valid retry.

Local verification on Windows with Bun 1.4.2 and Clang 23.1.5 passed all ten
guest tests, four recipe tests, and TypeScript checking. The guest tests check
the advertised memory size and verify negotiation of the 2,181,171,200-byte
artifact budget and 4 GiB session disk budget before the tiny trials.

## Qualification still required

The Windows ARM64 development .NET CLI also used its configured WASM worker
with Wasmtime 50.0.1 to process the materializer's three-module tree. The
recorded input contained 204 documents and 47,206 source bytes. Generation
exited 0, reported the WASM transport and published all three expected paths.
Each artifact matched the formula-derived digest, covering 9,555 output bytes.

| Evidence | SHA-256 |
| --- | --- |
| Built scale guest | `5d378059a78c20853545a989907de969c013083e888c815fcf2a0200fe2b75e0` |
| Development `morphir.dll` | `aac58f8a8f86b258bcf48f3e1e9e4b88f79c456195c70ef6a3bf71be3ac8e626` |
| Development `Morphir.Tooling.dll` | `5005c3ff57bb9e18b483f8bd1500a227135617d2b0a6ebd1892802302922274c` |
| Tiny fixture source inventory | `01fd7006cdb04c4d3a5b55cb1bec730c2d72d2170f8e80db7748282b059db158` |
| Independent artifact inventory | `f1e53c6d3d21983b66ca2638e3dfcb6da7582e0495a420f43fa62cfd3d49b0c4` |

Task 7.2 still requires both production scales. The shim retains test output
to compare complete bytes. The tiny .NET run exercises delivery and
publication with the development binary identified above.

The guest has fixed buffers and the test links a fixed 1 MiB linear memory.
Negotiated bounds constrain documents, chunks, cumulative artifact bytes and
rounds. This checkpoint does not establish enforcement of cumulative work,
deadlines, host cache, snapshot disk or every negotiated frame budget. Those
remain host/qualification work. The guest cannot detect a host omitting whole
root modules without the independent expected inventory. An invalid delivery
leaves staged chunks unpublished; the caller must cancel or terminate on an
unrecoverable failure. No scale qualification or task completion is claimed.
