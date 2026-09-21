# Library contract, first Stage 0 slice

Status: experimental draft `0.1.0-draft.1`. The exact-payload-byte policy is accepted;
field names, grammar restrictions, and aggregate encoding remain subject to Stage 0 review.
The [package design](../../kb/bundles/morphir/morphir-package-system/package-system-design.md)
remains the architectural source. This document supplies draft schemas and candidate cases.

## Identity and the worked example

Package releases associate a packaging identity with an IR Package name. They do not
insert release versions into IR definitions, dependency keys, or FQNames.

| Role | PackagePath | Release version | IR Package name |
| --- | --- | --- | --- |
| Provider | `example.com/finance/eligibility` | `1.2.0` | `example/eligibility` |
| Consumer | `example.com/finance/loan-rules` | `1.0.0` | `example/loan-rules` |

These are hypothetical packages, not packages hosted at example.com. The complete files
live in [the two-Library fixture](mck/fixtures/two-libraries/).

The provider's public `decision` module defines the custom type `decision`, its `approved`
and `declined` constructors, and the value `default-decision`. Its type FQName is
`example/eligibility:decision#decision`. The consumer's public `eligibility` module defines
the value `decision`, whose body refers to `example/eligibility:decision#default-decision`.
There is no implicit SDK dependency in either fixture.

The consumer's IR `dependencies` map embeds the provider's public PackageSpecification
under `example/eligibility`. Its release manifest separately requests
`example.com/finance/eligibility` in the interval `[1.0.0, 2.0.0)`. The lock-core selects
`1.2.0`. This records a valid selection; it does not implement a selection algorithm or
claim that `1.2.0` is the highest available release.

## Restricted draft profile

This slice accepts Library releases with one JSON/classic IR v4 document. Metadata uses
objects, arrays, and printable ASCII strings. Format markers in metadata are strings;
the IR fixture keeps its own numeric `formatVersion: 4`.

Package paths use a lowercase ASCII dotted authority followed by slash-separated
lowercase alphanumeric/kebab components. Stable release versions contain three decimal
components, without leading zeroes except `0`. Requirements use explicit
`minimumInclusive` and `maximumExclusive` versions. Implementations compare each component
as an integer, without floating-point conversion. The lower bound must precede the upper.

IR paths use the current v4 canonical string spelling, including uppercase initialism
words such as `HTTP`. They do not adopt the dotted authority syntax of PackagePath.
The schema includes that IR path grammar. The worked payloads pass the pinned v4 schema;
the TypeScript and Rust package implementations also use their respective v4 codecs. No current IR
schema or codec is changed here.

Content paths are relative slash-separated lowercase alphanumeric/kebab components with
an optional final dot-extension. Absolute paths, empty components, backslashes, dot
components, and traversal are outside this grammar. This is a lexical restriction, not
an extraction security policy. Windows reserved filenames, path budgets, filesystem
collisions, links, and archive resource limits still need transport/materialization rules.

Unicode identities, prereleases, build metadata, snapshots, alternate requirement syntax,
YAML and document-tree payloads remain outside these cases. Those omissions are not
decisions to exclude them from the complete package system.

## Release manifest

The [manifest schema](schemas/library-manifest.schema.json) describes normalized release
metadata, not authoring configuration. Every field is required and unknown fields fail.

| Field | Meaning |
| --- | --- |
| `formatVersion`, `kind` | Draft marker and `Library` artifact kind |
| `packagePath`, `version` | Exact release identity |
| `ir.packageName` | Associated IR Package name |
| `ir.formatVersion` | Payload IR version, `"4"` in this profile |
| `ir.payload` | Declared path, media type, and codec profile |
| `dependencies` | IR Package name to PackagePath and version interval |
| `exports` | Effective public export path to IR Module path |
| `content` | Declared payload path to exact-byte SHA-256 digest |

The effective `exports` map is explicit at the release boundary. Authoring tools may
derive it by convention from public IR Module paths and apply user customizations before
emitting the manifest. The fixture uses identity mappings. It does not implement the
complete authoring/export-map rules or redefine the approved default based on logical IR
structure rather than source filesystem layout.

The payload path must occur in `content`. Export targets must be public modules. Dependency
keys must agree with the IR's dependency specification keys, and selected releases must
provide the corresponding IR Package names and compatible public specifications. The shared
package suite must check these relationships. Generic schema validation does not establish
cross-document consistency or public-specification compatibility.

The manifest does not declare itself as payload and does not contain its own manifest or
Package content digest. Release statements and signatures sit outside that digest boundary.
Undeclared transport entries cannot silently become package content.

## Exact bytes and normalized metadata

For each declared file, hash the bytes as stored, including whitespace and line endings.
Do not parse, rewrite, transcode, or convert the IR before hashing it. A semantic-equivalence
check is a different operation.

Normalize the manifest as follows:

1. Reject an initial BOM. Parse JSON while rejecting duplicate object keys at every level, including escape-equivalent keys.
2. Accept only objects, arrays, and strings whose decoded characters are U+0020 through U+007E.
   Apply the same string restriction to keys. Reject numbers, booleans, and null.
   Limit depth to 64 edges from the root at depth zero; each object member or array element adds one edge.
3. Sort object members lexicographically by their ASCII keys. Preserve array order.
4. Write compact JSON, escaping double quotes as `\"` and backslashes as `\\`.
   Write all other accepted characters literally, including `/`. Do not emit a BOM or final newline.
5. Encode that canonical text as UTF-8.

Normalization accepts values within that bounded domain. A release manifest must also
pass its schema and semantic checks; successful normalization alone says nothing about
whether an object is a valid release manifest.

Every digest is rendered as `sha256:` followed by 64 lowercase hexadecimal digits:

```text
fileDigest       = SHA256(exact declared file bytes)
manifestDigest   = SHA256(canonical manifest UTF-8 bytes)
contentDigest    = SHA256(UTF8("morphir-package-content:0.1.0-draft.1\n")
                          || canonical manifest UTF-8 bytes)
```

Here `\n` denotes one LF byte, and `||` denotes byte concatenation. The canonical
manifest already contains the sorted `content` map, so each declared path and file digest
contributes to the aggregate. Verify each declared digest against the actual file bytes
before accepting the aggregate as evidence about a bundle. Hashing declarations alone
does not verify content.

Reordering manifest keys or changing its insignificant whitespace preserves these
manifest and content digests. Reformatting a declared IR file changes its file digest;
after updating the declaration it changes the Package content digest. Recompressing a
transport archive without changing the manifest or declared files preserves Package
content identity, although the separate transport digest can change. No archive packer
or transport-digest protocol is implemented here.

## Lock-core projection

The [lock-core schema](schemas/lock-core.schema.json) captures the dependency graph needed
for this example. It is **not an installable lock file**. It omits acquisition sources,
registry metadata, trust evidence, release statements, status observations, snapshots,
and the complete resolution-policy record. It cannot authorize installation or execution.
The full user-facing lockfile remains named `morphir.lock`; `lock-core` names this draft projection only.

`root` names a graph node. Each member of `nodes` has an exact release identity, the
associated IR Package name, manifest and content digests, and its own `bindings` map.
Bindings map an IR dependency Package name to a target node. IDs such as `n0` and `n1`
are local graph handles, not PackagePaths, release identities, persistent PackageInstanceIds,
or IR names. This draft does not settle multiple environments for one release.

In the example `n0` is loan-rules and its `example/eligibility` binding selects `n1`.
The provider `n1` has no dependencies. One consumer has at most one implicit binding
for any IR Package name. There are no direct multi-bindings or version-bearing FQNames.

The root and every binding target must exist. Target IR names and PackagePaths must
match requirements, selected versions must satisfy their intervals, and node digests
must agree with the selected manifests. Lock-core JSON follows the same bounded metadata
normalization domain, including duplicate-key rejection. JSON Schema checks structure, not these graph
relationships. The shared suite's `verify-library-set` operation checks the supplied closed
Library set, including dangling roots and targets, duplicate keys, and inconsistent aggregate digests.
It is not a dependency resolver or a public-specification compatibility checker.

## Evidence and remaining Stage 0 work

`mise run package:schema-check` validates the draft schemas and the worked manifests,
lock-core, and IR document structures. `mise run package:check` runs the schema/digest case
matrices and Library integrity cases through the native `morphir mck package run` command
against the independent TypeScript adapter. `mise run package:check:rust` runs the same cases
against the independent Rust adapter, which delegates package operations to the
`morphir-package` library.

The fixed digest expectations were cross-checked during the initial local prototype.
That prototype's standalone runners were retired after the
[shared MCK core decision](../../kb/bundles/morphir/morphir-package-system/decisions/0001-package-compatibility-uses-the-shared-mck-core.md).
Current execution follows the [native MCK ownership decision](../../kb/bundles/morphir/morphir-package-system/decisions/0003-mck-tooling-lives-in-the-rust-morphir-cli.md).
The runner owns case loading and verdicts; each implementation participates through an explicit
executable adapter. TypeScript reference operations remain independent of the runner.
Historical comparisons remain frozen in the [migration record](../mck/migration.md).

[Deterministic resolution](resolution-contract.md) and its fixed MCK cases have since landed
under draft.2, with independent TypeScript and Rust implementations. See the
[landing evidence](mck/README.md#landed-resolution-evidence). This does not expand draft.1's operations.

Full lock and registry-record schemas, acquisition and trust diagnostics, public
specification compatibility, authoring configuration, PURL mapping, WIT interfaces,
additional package operations and their interoperability evidence remain Stage 0 work. The bounded
draft now has a versioned adapter/report contract, corpus content provenance and mandatory-case gates.
Advanced reference encoding remains Stage 3 work.
