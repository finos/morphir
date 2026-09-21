# MCK kit snapshots, manifest and acquisition

Status: **approved** in the IR-0 design review on 2026-09-18 ([#851](https://github.com/finos/morphir/issues/851)). Changes now need their own review.
Implemented: the digest algorithm, the embedded kit, the manifest, managed-kit verification, and `kit vendor` and `kit update` from the `embedded`, local and `github:finos/morphir` sources (IR-1, IR-1V). Extraction and its bounds live in the engine (`morphir_mck::kit::archive`); only the download is in the CLI. Command spelling is in the [CLI contract](cli-contract.md).

An implementor of a binding or extension uses the installed `morphir` CLI to put a pinned copy of
the kit in their own repository, commit it, and run it offline. They need neither a Morphir source
checkout nor the TypeScript MCK package. Their adapter may still need its own runtime.

This is kit provenance. It is not the model-package `morphir.lock`, has no dependency-resolution
semantics, and does not depend on the unfinished package registry. It makes no TUF or restore claim.

## Snapshot layout

A snapshot is a directory of data files at their **repository-relative logical paths**, plus one
manifest at its root:

```text
vendor/morphir-mck/
  mck-kit.lock.json
  spec/ir/mck/README.md
  spec/ir/mck/types.md
  spec/ir/mck/...
  spec/mck/vocabulary.json
  website/static/ir/examples/v4/complete-example.json
  website/static/schemas/morphir-ir-v4.json
  website/static/schemas/morphir-ir-v4-document-tree-files.json
```

Corpus paths are not rewritten, so fixture references inside cases resolve exactly as they do in
finos/morphir with `--repo-root <snapshot>`. Bytes are preserved exactly. No line-ending or
encoding conversion happens at any step; implementors should mark the directory `-text` in
`.gitattributes`, and `kit vendor` prints that advice.

### Input closure

For the IR suite the snapshot holds exactly:

1. every file under `spec/ir/mck/`;
2. every file a `text` fence in any case resolves to;
3. the coverage vocabulary, `spec/mck/vocabulary.json`;
4. the schemas and examples `schema check` reads: the two IR schemas under
   `website/static/schemas/`, plus `spec/mck/vocabulary.schema.json`,
   `spec/mck/mck-kit.lock.schema.json`, `spec/mck/mck-kit.lock.example.json` and
   `spec/mck/provenance.schema.json`. Report and protocol schemas/examples are already
   included by item 1.

IR-3 extends the fixed closure to support installed offline schema checks. Re-vendor a source
revision carrying these inputs. An older managed snapshot missing them fails closed; the driver
does not silently add files to its manifest. The digest algorithm and lock format are unchanged.

Files outside this transitive set are not included. Items 1 and 2 are the **legacy corpus set**,
the input of the TypeScript driver's `kit.lock.json` hash. At the baseline that is 15 files, listed
in [baseline/corpus-inventory.json](baseline/corpus-inventory.json). A kit with parse errors or an
unresolvable fixture cannot be snapshotted.

## Digests

One algorithm, `mck-file-map-sha256/1`, kept from the TypeScript driver for parity:

```text
line(path)  = UTF-8(path) || 0x00 || lowercase-hex(SHA-256(bytes(path))) || 0x0A
digest      = "sha256-" || lowercase-hex(SHA-256(concat of line(path) for paths in sorted order))
```

- Paths are repository-relative, `/`-separated, with no leading `/`, no `.` or `..` segment and no
  empty segment.
- **Sort order is by UTF-16 code unit**, the default JavaScript string order. This differs from
  UTF-8 byte order and from Rust's `str` ordering for paths containing characters above U+FFFF.
  The Rust implementation must sort by `encode_utf16()` sequences.
- File bytes are raw. The TypeScript driver hashed `text` fixtures after a UTF-8 decode and
  re-encode, which is the identity for valid UTF-8 without a byte-order mark. `check` rejects a
  fixture that is not valid UTF-8 or that starts with a byte-order mark, so the two definitions
  cannot diverge on an accepted kit.

[baseline/hash-vectors.json](baseline/hash-vectors.json) fixes literal vectors, including a
non-ASCII path and a pair whose UTF-16 order is the reverse of its code-point order. A change to the
algorithm gets a new algorithm name; it never silently changes `/1`.

A snapshot records two digests:

| Field | Input set | Purpose |
| --- | --- | --- |
| `corpusHash` | Legacy corpus set (items 1 and 2) | Same identity the TypeScript `kit.lock.json` recorded, for parity and cross-runner comparison |
| `snapshotDigest` | Every file in `files` | Identifies the complete bytes a managed run uses |

The manifest is never an entry in `files`, so it does not hash itself.

## `mck-kit.lock.json`

Schema: [mck-kit.lock.schema.json](mck-kit.lock.schema.json).
[mck-kit.lock.example.json](mck-kit.lock.example.json) is an illustrative manifest over the legacy
corpus set at the baseline, so its two digests are equal; a real snapshot also lists the vocabulary
and schemas. Tab-indented JSON with a trailing
newline, keys in the order shown, `files` sorted in digest order, so regenerating an unchanged
snapshot is byte-identical.

```json
{
	"lockVersion": 1,
	"suite": "ir",
	"contract": { "protocol": 1, "report": 1 },
	"driverContract": ">=1, <2",
	"source": {
		"kind": "github",
		"repository": "finos/morphir",
		"revision": "a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0"
	},
	"algorithm": "mck-file-map-sha256/1",
	"corpusHash": "sha256-075bb621c9901fcca21830051065b3d5f303dfb827b1624c52c82d796bf4c609",
	"snapshotDigest": "sha256-...",
	"files": [
		{ "path": "spec/ir/mck/README.md", "sha256": "...", "size": 8439 }
	]
}
```

- `source.kind` is `embedded`, `local` or `github`. `embedded` records the CLI version that
  exported it and the revision that CLI embedded. `local` records the revision only if the source
  snapshot had a manifest; a plain directory has `revision: null`.
- `driverContract` is a range over the **driver contract version**, an integer the CLI reports as
  `driverContract` in `morphir mck kit status` (and its `--json`). The CLI disables `--version` on
  every subcommand, so `morphir mck --version` does not exist. It starts at 1 and increases only when the runner's interpretation of a
  kit changes incompatibly. A CLI whose contract is outside the range refuses the kit before
  starting an adapter, exit 1. It never fetches another kit and never downgrades silently.
- There is no timestamp. A manifest is a function of its content and source.

The CLI release and the kit are pinned separately: the implementor's tool manager pins `morphir`,
the manifest pins the kit.

## Sources and trust

| `--source` | Network | What is trusted |
| --- | --- | --- |
| `embedded` | None | The installed CLI. The kit is the one compiled into it. |
| `<path>` to a snapshot or a finos/morphir checkout | None | The local directory. A source with a manifest is verified first. |
| `github:finos/morphir` with `--revision <40 hex>` | HTTPS to `codeload.github.com` only | TLS to the fixed official host, plus the commit id the user chose |

Rules for the remote source (maintainer decision, 2026-09-18, "pinned commit over TLS"):

- `--revision` must be a full 40-character lowercase hex commit id. Branches, tags and abbreviated
  ids are usage error 2. The repository is fixed to `finos/morphir`; other repositories, mirrors and
  transports need a later contract.
- One request is made, for that commit's archive. Redirects are followed only to `github.com`
  hosts over HTTPS. Certificate validation uses the platform trust store and cannot be disabled by
  a flag. The standard proxy environment variables are honoured.
- The archive's single top-level directory must end in the requested commit id.
- `--expect-digest <sha256-...>` is optional and compares against `snapshotDigest`. A mismatch
  fails closed and publishes nothing.
- The computed digests are written to the manifest. **A digest detects change; it does not prove
  who published the content.** Authenticity in this delivery rests on TLS and the pinned commit id.
  `kit vendor` prints this boundary once, on stderr. Signed kit release assets are a possible later
  source kind and are not part of IR.

Acquisition reads data only. It never runs upstream hooks, build scripts or adapters, never installs
extensions and never acquires an executable test subject. `check`, `coverage`, `run`, `schema check`
and `kit status` never touch the network.

### Bounds and unsafe input

| Bound | Value |
| --- | --- |
| Download size | 64 MiB |
| Total extracted size of selected entries | 256 MiB |
| Archive entries scanned | 100 000 |
| Files in a snapshot | 10 000 |
| Path length | 1 024 bytes |

The full repository archive is streamed and only closure paths are extracted, in two passes over a
bounded temporary file:

1. `spec/ir/mck/**` plus the fixed parent-owned inputs of closure items 3 and 4:
   `spec/mck/vocabulary.json` and the schemas/examples `schema check` reads. The CLI carries this fixed
   list per suite and driver contract version; a schema that gains an external `$ref` adds the
   referenced file to the list in the same change.
2. The external fixtures that the cases parsed from pass 1 name.

A revision that lacks any fixed input, for example one older than `spec/mck/vocabulary.json`, fails
closure verification and publishes nothing. The same closure applies to the embedded and local sources.

Rejected, failing the whole acquisition:

| Rule | Applies to |
| --- | --- |
| A path that is not UTF-8, is absolute, or has a backslash, NUL, or an empty, `.` or `..` segment | Every entry |
| More than one top-level directory, or one whose name does not end in the requested commit id | Every entry |
| A symbolic or hard link, device or other special file where the snapshot takes a file | Selected entries |
| A duplicate, or two paths that collide after Unicode NFC and ASCII case folding | Selected entries |
| A name no supported platform can create: a Windows device name (`CON`, `NUL`, `COM1`...), a trailing dot or space, a colon or control character | Selected entries |

The link rules cover selected entries only because finos/morphir itself tracks symbolic links outside
the kit's closure (under `wit/`); refusing every link would refuse every real revision. No entry
outside the closure is extracted, so an unselected link is never followed or written. Snapshot
verification applies the selected-entry rules to local sources too: a listed path must be a regular
file, never a link.

## Publication, update and edits

Publishing is all-or-nothing.

1. Build the snapshot in a staging directory created next to the destination, on the same volume.
2. Verify it completely: closure, `check` with no errors, digests, optional `--expect-digest`.
3. Promote by rename. If anything fails before this step, the staging directory is removed and the
   destination is untouched.

`kit vendor` requires `--dest` to be absent or an empty directory; missing parent directories are
created, as `mkdir -p` would. If it holds a manifest whose
digests equal the new snapshot, the command is a successful no-op. Anything else is refused, exit 1.
There is no force option in this delivery.

`kit update --kit <dir> [--source <source>] [--revision <commit>]` replaces only a managed snapshot.
`--source` defaults to the source kind recorded in the manifest, so `--revision` alone updates a snapshot
that came from GitHub. `--revision` is required when the source is `github:finos/morphir` and is usage error 2 with `embedded` or a local path, whose
revision comes from the CLI or from the source snapshot's own manifest and may be null. The steps:

1. Verify the existing snapshot against its manifest, before anything is downloaded. An edited, missing or extra file is refused,
   exit 1, naming the files. Unrelated content is never deleted.
2. Stage and verify the new snapshot as above.
3. Carry the snapshot root's `.gitattributes`, if any, into staging. Rename the old snapshot to
   `<dir>.mck-old-<random>`, rename staging to `<dir>`, then remove the old one. If the second rename fails, the first is reversed. A leftover `.mck-old-*` or staging
   directory from an interrupted run is reported by the next `check`, `kit status`, `vendor` or `update`
   with the exact recovery action, and is never treated as a usable kit.
4. Print a summary of added, removed and changed paths and the old and new revisions and digests.
   Nothing is committed automatically.

An update from `embedded` whose digests equal the existing snapshot is a successful no-op.

## Managed and raw kits

Detection has no fallback and no ambiguity:

| Condition | Mode | Behaviour |
| --- | --- | --- |
| The directory given is a snapshot root, or `mck-kit.lock.json` exists at the repository root in use (`--repo-root`, or the inferred root) | Managed | `check`, `kit status`, `coverage`, `schema check` and `run` first check `driverContract`, verify every listed file's size and SHA-256, reject any other file under the snapshot root except a `.gitattributes`, and confirm the kit's corpus hash is the recorded one. Any mismatch fails, naming each file, before a case is read or an adapter starts. |
| No manifest there | Raw authoring | The checkout is used as is. `kit status` and the consolidated report identify it as `local`, with a digest of the bytes that ran and `modified: true` unless it equals the embedded kit. |
| No `--kit` | Embedded | The compiled-in kit. Its bytes are part of the binary, so there is no separate manifest to check; `kit vendor --source embedded` writes one. |

A manifest that is present but unreadable, or has an unknown `lockVersion`, is an error. It never
downgrades the kit to raw mode. Raw mode is for intentional corpus edits inside finos/morphir and
does not relax vendored CI checks.

`kit status` verifies inventory, digests and provenance locally and prints the source, revision,
both digests, the mode and the driver contract. `--kit` may name the snapshot root or its kit
directory. Exit 1 on any mismatch. There is no remote comparison in this delivery.

## Acceptance

The end-to-end test for IR-1V and IR-4, on Linux, macOS and Windows:

1. In a fresh repository with only the installed CLI, run `kit vendor` for a pinned revision.
2. Commit the data and manifest. Remove every acquisition cache and temporary file.
3. Disconnect the network.
4. Run `kit status`, `check` and `run` with an explicitly selected adapter.
5. Compare the report with a run of the same revision from a finos/morphir checkout.

Failure cases covered: corrupted and truncated files, a missing fixture, an incompatible
`driverContract`, each unsafe archive class, an interrupted update at each rename, an edited
destination, unrelated destination content, a digest mismatch, and an explicit revision update.
A compatibility claim covers only the suite that ran, never every aspect of an extension.
