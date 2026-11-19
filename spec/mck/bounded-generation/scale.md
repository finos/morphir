# Bounded Orders scale recipe

This is the source recipe for the fixture portion of task 7.2 in
[add-bounded-model-access](../../../openspec/changes/add-bounded-model-access/specs/mck/bounded-generation/spec.md).
It adds a v4 plain JSON split tree beside the frozen Orders cases. It does not
change those cases, their five WASM controls, the small shared guest or receipt
draft.1. No scale run or resource qualification is recorded here. Task 7.2 also
requires measured execution at both scales and remains open until that evidence
exists.

## Materialize into scratch

From the repository root, with the existing tools environment available:

```powershell
bun tools/materialize-bounded-orders-scale.ts --scale A --output-dir .dev/orders-scale-a
bun tools/materialize-bounded-orders-scale.ts --scale B --output-dir .dev/orders-scale-b
```

Both options are required. The caller must supply an existing scratch parent,
such as `.dev`. The destination itself must not exist, even as an empty
directory or a symlink. The recipe resolves its parent before writing and
refuses destinations inside `spec/mck/bounded-generation/fixtures`, including
through a symlink or junction. A failed write leaves its partial scratch for
inspection; it never retries into an existing output or removes caller data.
Generated files belong in ignored caller scratch, not in the fixture directory
or source control.

The output contains `model/`, the IR tree, and `expected-artifacts.json`, the
independently calculated artifact inventory. Standard output records the actual
`sourceBytes`, `maxDocumentBytes`, `documentCount` and `modelDigest` separately
from the expected `artifactBytes`, `artifactCount` and `expectedArtifactDigest`.
`sourceBytes` sums only model document bytes, including their final LF. It does
not include the expected inventory, filesystem allocation or directory metadata.
The maximum is the largest actual model document, not a payload-size estimate.
Keep those fixture facts alongside the host observations and resource receipt
from each qualification run.

## Fixed dimensions and ordering

| Scale | Generated modules | Payloads per module | Bytes per payload | Aggregate payload bytes |
| --- | ---: | ---: | ---: | ---: |
| A | 1,024 | 64 | 16,384 | 1,073,741,824 |
| B | 2,048 | 64 | 16,384 | 2,147,483,648 |

The package is `acme/orders`. The tree follows the
[v4 document layout](../../../docs/spec/ir/schemas/v4/document-tree-files.md)
used by [frozen Orders](fixtures/acme-orders/README.md), with integer
`formatVersion: 4`, manifest-style module inventories and separate `.type.json`
and `.value.json` files. The SDK dependency supplies an opaque string type at
`deps/morphir/_sdk/@/string/string.type.json`. There are no timestamps, random
identifiers, absolute paths, contextual aliases or aggregate single-file IR.

Discover generated package modules in ordinal order, `m000000` through
`m001023` for A or `m002047` for B. The SDK string module is a specification,
not an output-producing package definition. Enumerate each package module's
types first, then values in the module manifest order:

1. Type `order000000`, a public alias of `morphir/SDK:string#string`.
2. The 64 public payload values `order000000` through `order000063`.
3. Public value `total-in-USD`, physically `total-in-_usd.value.json`, whose
   body is `Reference: acme/orders:mNNNNNN#order000063`.

All values have no inputs and output type `morphir/SDK:string#string`. A payload
body is a `Literal` containing a `StringLiteral`. The type and first value share
a name, so reference lookup must preserve member kind.

Use page size 16 for root and member inventory. Each module has 66 members, so
its fifth and final page contains value `order000063` followed by value
`total-in-USD`. The reference therefore requires the final payload in that
page. Follow all root cursors, including the SDK module if the selection exposes
it, and all member cursors. Filesystem enumeration order is not inventory order.
The recipe adds modules rather than expanding an unbounded root inventory
document. Each written model document is checked against a 32,768-byte ceiling.

## Independent expected artifacts

For module index `m` and payload index `v`, the payload is ASCII text starting
with `mNNNNNN/orderNNNNNN:` and padded on the right with `x` to exactly 16,384
bytes. Zero-based indices use six decimal digits. For example, the first prefix
is `m000000/order000000:`. No JSON syntax belongs in artifact bytes.

Each module produces `orders/mNNNNNN.txt`. Emit each of its 64 payload strings
in value order followed by LF, then resolve `total-in-USD` as a value reference
and emit that referenced payload followed by LF. Thus each artifact has 65
lines and exactly 1,065,025 bytes. Include the final LF in every digest. A body
change, reference redirect or missing final page must fail the full comparison.
The output inventory must contain exactly the specified paths, with no omissions
or extra artifacts.

| Scale | Expected artifact bytes | Fixed artifact inventory SHA-256 |
| --- | ---: | --- |
| A | 1,090,585,600 | `4647993318ded44552c1cfe273f96dfab83adefdf5d63849b6d4382ce7c6ee55` |
| B | 2,181,171,200 | `4783e20057439e98e398b88a7cbf7f04299a0354324bcaa119971dd4dc523212` |

The fixed digests were calculated separately by hashing one complete
formula-derived artifact at a time. The recipe checks its streamed inventory
against that digest before writing the model documents.

Before it writes any model documents, the recipe hashes the output chunks
directly from this formula. It never reads produced IR to establish expectations
and never invokes a host, codec, runner or guest. It streams the canonical
inventory as an RFC 8785 JSON array of `{path, sha256}` objects, sorted by UTF-8
path bytes, without whitespace or a final newline. These paths and keys are
ASCII, so the recipe's explicit key and module ordering is canonical.
`expectedArtifactDigest` is the lowercase SHA-256 of those exact inventory bytes,
as required by [receipt draft.1](receipt.md). Individual `sha256` members cover
complete original artifact bytes. The recipe stores digests, not generated
artifact files. It retains one payload chunk, one bounded model document and
at most one module's member names at a time.

`modelDigest` covers the exact source documents in recipe order: distribution
manifest, SDK module, SDK type, then generated modules in ordinal order. Within
each module, visit its manifest, shared-name type, payload values in ordinal
order and final reference. For every document, hash its slash-separated path
relative to `model/`, NUL, its exact UTF-8 bytes, then NUL. Documents use compact
`JSON.stringify` property order as written in the recipe and one final LF.
This source fingerprint is distinct from the expected-artifact inventory digest.

## Receipt case identities

[Orders scale cases](orders-scale.cases.json) binds the two independent
artifact inventories, the plain source-tree fingerprints, and the shared
WASM guest. Use `orders-scale/a` or `orders-scale/b` as the receipt's
`kit.caseId`. The contract digest is the SHA-256 of the receipt schema.
The suite digest is the SHA-256 of the exact case file bytes. These
identities and expectations come from the kit. An observed output digest
comes from the published artifacts.

The case file supplies the expanded input size for these plain trees and
the largest individual document. They describe the source fixture. They
are not measurements of residency or operation I/O. A successful output
comparison leaves resource qualification pending unless the receipt also
has the enforced ceilings and measurements required by draft.1.

## Tiny source tests and remaining qualification

The imported `materialize({ scale, outputDir }, tinyTestDimensions?)` API accepts
a test-only second argument with `moduleCount` of 2 or 3, `payloadCount` from 2
to 64 and `payloadBytes` from 32 to 256. No CLI flag exposes these overrides.
The tests retain 64 payloads with 48-byte strings to exercise all five member
pages without large trees. They compare independent formula bytes with complete
observed payload output and hashes, check the page-final reference, deterministic
files and source byte accounting, and reject overwrite and unsafe destinations.

Run the focused tests and TypeScript check from the repository root.

```powershell
bun test tools/materialize-bounded-orders-scale.test.ts
bun run --cwd tools typecheck
```

A later scale guest must consume signatures and every payload body, resolve the
final value by typed inventory identity and stream artifact chunks. The frozen
five-round guest cannot run this recipe. Host document-count and snapshot-disk
budgets, enforced resident and guest-memory limits, pagination costs, measured
host/descendant memory and actual receipts still need qualification. The plan's
candidate ceilings are not claims made by these source files.
