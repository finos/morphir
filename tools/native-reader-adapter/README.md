# Native reader development adapter

This standalone development executable supplies observations to an explicitly
selected .NET MCK adapter. It contains no kit runner, expected-result comparison,
receipt validator or production command routing. Build with the repository's
pinned MoonBit `0.10.20+65efd5b93`, native target and one job.

The executable takes no arguments, or the optional `--json` flag. Both forms use
the same JSON protocol. It reads one UTF-8 JSON request through stdin until EOF,
then writes one UTF-8 JSON object with no trailing newline to stdout. Requests
are limited to 16,384 bytes and depth 32. Responses are limited to 65,536 bytes.
Failure exits 1, writes diagnostics to stderr and writes no response. Success
exits 0 and leaves stderr empty. Unknown arguments, including `--help`, fail on
stderr so they cannot corrupt the adapter channel.

The request has exactly these required keys:

```json
{
  "scope": "native-reader-adapter",
  "caseId": "acme-orders/4.0.0/plainJson",
  "binding": { "opaque": "owned by the runner" },
  "treeRoot": "/absolute/path/to/v4/plain-json",
  "snapshot": "<64 lowercase SHA-256 hex digits>",
  "irVersion": "4.0.0",
  "profile": "plainJson",
  "selection": "pkg/acme/orders/domain/module",
  "pageSize": 2,
  "documentLimit": 8192,
  "attributes": []
}
```

`irVersion` is exactly `3.1.0` or `4.0.0`. `profile` is exactly `plainJson`,
`plainYaml`, `contextualJson` or `contextualYaml`. `caseId` must match both.
`selection` is an extensionless logical module document ID string. The adapter
resolves it against actual admitted module inventory to obtain the typed package
and module identities. It does not decode identities from escaped paths or
special-case the Orders module. Object selections are refused. `pageSize` is an integer from 1 through 256;
`documentLimit` is an integer from 1 through 8192 and also caps each selected
expanded document. `attributes` is an ordered array
of objects with exactly `document` and `pointer` string keys. Document IDs come
from inventory and omit the serialization extension. Pointers use RFC 6901.
The v4 request must have an empty attributes array. The adapter rejects duplicate
JSON members at every depth, unknown keys and invalid input types. It matches
the runner admission limits of 8192 nodes, 64 properties per object, 256 entries
per array and 4096 UTF-16 units per individual string or property name. The binding
must be an object. Its complete supplied JSON value text is echoed verbatim,
including numeric lexemes and whitespace, without interpreting its members.

The response has exactly `scope`, `caseId`, `binding` and `facts`. Its scope is
`native-reader-adapter`. Facts have exactly `scope`, `revision`, `irVersion`,
`distribution`, `package`, `pathBudget`, `dependencies`, `modules`, `pages`,
`finalPageBody` and `classicAttributes`. Their scope is `native-reader`.
`revision` is the verified snapshot. Modules and their members use the parent's
orders grammar. `pages` records actual member pages for the requested selection,
following only the reader's opaque continuations. The last member must be a
value with a direct expression reference. The adapter follows its typed FQName's
package, module and local name with the value role, then observes the target's
integer literal. It does not infer identity from filenames. Attribute values
come from selected expanded document bytes under the requested reader profile.
No output is compared with fixture expectations inside the executable.

The small snapshot admission accepts exactly nine regular files, at most 64
entries across all descended directories, and at most 8192 bytes per file.
It refuses symbolic links and special files, including links in the supplied
root's ancestors. Paths containing line separators or backslashes in a component
are refused. It sorts relative paths ordinally with `/` separators. For every
file it hashes its exact bytes, then computes SHA-256 of the UTF-8 concatenation
`path + LF + lowercaseFileHash + LF` in that order. The supplied hash must match
before observation and after a fresh filesystem capture following all reads.

This adapter captures the nine admitted files in memory and exposes their actual
names and capped UTF-8 content through `TreeSource` to `open_bounded_tree`.
It checks every listed member's typed reader admission. This is small correctness
scope. It makes no resident-memory claim or general mutable-source provenance,
producer-lease, host-generation, WASM or scale qualification claim.

The nested `moon.work` keeps this tool separate from production workspaces.
It selects the local IR module and a cached, unmodified `moonbitlang/x@0.5.5`
under `.mooncakes/moonbitlang/x` for SHA-256. Prepare that directory by copying
an already available exact cached dependency. The replay bundle includes it
and its license and source digest manifest. No dependency installation is needed.
From the repository root, with the pinned `MOON_HOME` and its `bin` on PATH:

```sh
moon -C tools/native-reader-adapter test . --frozen --deny-warn --target native -j 1
moon -C tools/native-reader-adapter build . --frozen --deny-warn --target native -j 1
```

Use the artifact path reported by `moon build` directly as the selected adapter
command. Do not use `moon run` as the runner-facing command because build output
is not part of the adapter protocol. Linux and Windows replay require their
existing native installation of the same pinned MoonBit toolchain. Only macOS
arm64 has been executed for this candidate. The parent orders corpus remains
independent data; the root integrates this executable into the shared .NET MCK.

The wire shape follows finos/morphir-dotnet PR #695 at
`6d00edae0fb33875c2ac0fc55ec6410d3a887171`,
`docs/development/bounded-reader-adapters.md` and
`src/Morphir.Mck/BoundedGenerationRun.cs`. No protocol shim is used.
