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

The test compiles C to a WASM object with `--target=wasm32 -O2 -fno-builtin
-nostdlib -c`, then invokes the Clang installation's `wasm-ld` directly with
`--no-entry --export-memory -z stack-size=262144 --initial-memory=1048576
--max-memory=1048576`. This avoids an optional `wasm-opt` invocation by some
Clang drivers. Build products stay under ignored `.dev/scale-test/`. The module
exports `memory` and `handle` and imports only the five kernel byte-exchange
functions. The test does not need WABT or downloaded dependencies.

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
tests. A separate compile with `-Wall -Wextra -Werror` passed. TypeScript static
checking was unavailable: this worktree has no `tools/node_modules/typescript`,
and the installed `tsc` shim has no configured version. Nothing was installed.

## Qualification still required

This is a source and tiny correctness checkpoint for task 7.2. No A/B scale
tree was generated, and no actual host, process adapter, resource receipt or
measured scale run was exercised. The test shim is deliberately independent
of a host implementation and retains test output to compare complete bytes.
Its memory behavior is not host resource evidence.

The guest has fixed buffers and the test links a fixed 1 MiB linear memory.
Negotiated bounds constrain documents, chunks, cumulative artifact bytes and
rounds. This checkpoint does not establish enforcement of cumulative work,
deadlines, host cache, snapshot disk or every negotiated frame budget. Those
remain host/qualification work. The guest cannot detect a host omitting whole
root modules without the independent expected inventory. An invalid delivery
leaves staged chunks unpublished; the caller must cancel or terminate on an
unrecoverable failure. No scale qualification or task completion is claimed.
