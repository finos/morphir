# Candidate local Library lock and registry contract

Status: experimental `0.1.0-draft.3`. Wire-contract and signed-fixture reviews were approved
on 2026-09-17. This is not a stable interchange release. Shared MCK and package runtime
implementation may proceed; no implemented registry interoperability is claimed.

This profile covers published Libraries acquired from local-directory registries.
Every graph node, including the root, is a published release. Unpublished packages,
workspace overrides, Git and HTTPS acquisition, archives, Contract releases, Applications,
and multiple versions of one PackagePath are outside this profile. No package operation
executes package-controlled hooks.

The [draft.1 Library contract](library-contract.md) still defines manifests, exact payload
bytes, manifest digests and Package content digests. The [draft.2 resolution contract](resolution-contract.md)
still defines selection, scoped updates and flat graph replay. Neither existing contract
changes. The full file is named `morphir.lock`; it is distinct from the draft.1 lock-core
projection. Release versions never enter IR dependency names or FQNames.

The [candidate trust profile](package-trust-profile.md) specifies repository and publisher
authority, signed release status, historical evidence and durable local authorization.

The accepted [filesystem assurance addendum](restore-filesystem-assurance.md) introduces
a portable restore delivery target alongside hardened restore. The filesystem guarantees
in this document remain the hardened baseline. Portable execution requires explicit host
selection and separate MCK profile evidence; this addendum does not silently weaken the
existing draft.3 execution contract or its fixed cases. Package artifact wire shapes stay unchanged.

## Common wire rules

The [lock schema](schemas/library-lock.schema.json), [record schema](schemas/registry-record.schema.json),
and [statement payload schema](schemas/release-statement.schema.json) use JSON Schema
2020-12. Their IDs start with
`https://morphir.finos.org/spec/package/0.1.0-draft.3/`. Register draft.1 and draft.2
schemas locally when resolving references; schema IDs do not authorize network fetching.

All fields in the tables below are required. Unknown fields fail at every object level;
there are no extension maps, optional flags, null defaults, or inferred values. Documents
reject a BOM, duplicate decoded object keys, invalid JSON, and non-ASCII strings. The
draft.1 bounded metadata domain applies: objects, arrays, printable ASCII strings, depth
at most 64 edges. This restriction applies to the lock, record and decoded statement
payload. TUF and DSSE envelopes follow their own specified encoding rules.

`ReleaseId`, `IRPath`, `Requirement`, and `Digest` retain their existing meanings.
`Digest` is `sha256:` plus 64 lowercase hex digits. `ReleaseId` has `packagePath` and
`version`; exact identity equality compares both strings. `Requirement` has `irPackageName`,
`packagePath`, and `versionRange` with `minimumInclusive` and `maximumExclusive`.
Compare version components as unbounded integers, and require a nonempty interval.

| Shared value | Type and permitted values | Additional rules |
| --- | --- | --- |
| `LocalId` | String matching `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` | An alias within one lock; conveys no authority. |
| `RegistryRelativePath` | String, at most 240 ASCII characters, matching `^[a-z0-9]+([.-][a-z0-9]+)*(/[a-z0-9]+([.-][a-z0-9]+)*)*$` | Relative slash-separated path; no empty or dot components, absolute roots, backslashes, colons, percent escapes, or trailing slash. Filesystem safety checks remain required. |
| `ObjectReference` | Object `{path: RegistryRelativePath, digest: Digest}` | `path` is a logical TUF target name; hash the exact target file bytes. The containing acquisition supplies the registry. |
| `DirectorySource` | Object `{kind: "registry-directory", path: RegistryRelativePath}` | A directory beneath the configured registry root, containing `manifest.json` and exactly the declared content. No fallback source or transport inference. |

Object member order has no structured meaning. Array input order has no structured
meaning except where a downstream signature authenticates exact bytes. Writers emit
the order specified below. Readers accept permutations, check uniqueness by the stated
keys, and never deduplicate an invalid document silently. For canonical records and
statement payloads, the prescribed array order is part of the required byte encoding.

## Full lock

| Field | Type and value | Ordering and uniqueness |
| --- | --- | --- |
| `formatVersion` | String `"0.1.0-draft.3"` | Exact match. |
| `kind` | String `"LibraryLock"` | Exact match. |
| `resolution` | Object defined below | One policy declaration for the whole graph. |
| `graph` | Existing draft.2 `LockedGraph` | Use the absolute reference `https://morphir.finos.org/spec/package/0.1.0-draft.2/resolution-input.schema.json#/$defs/LockedGraph`; no new graph type. |
| `registries` | Nonempty `Registry[]` | Unique `id`, emitted in ascending ASCII `id` order. |
| `acquisitions` | Nonempty `Acquisition[]` | Unique exact `release`; emit PackagePath ascending, version descending numerically. |
| `evidence` | Nonempty `Evidence[]` | Globally unique `id`; also unique pair of `registry` and `path`; emit ascending ASCII `id`. |

### Resolution

| Field | Type and value | Ordering and uniqueness |
| --- | --- | --- |
| `policy` | String `"flat-library:0.1.0-draft.2"` | Names the unchanged draft.2 deterministic policy. |
| `profile` | String `"local-library"` | Published Libraries and registry-relative unpacked bundles only. |
| `requiredCapabilities` | Array containing exactly `"dsse-ed25519"`, `"local-directory"`, `"tuf-1.0.36"` | Each occurs once; emit ascending ASCII. No unknown capability may be ignored. |

All three capabilities are required by this candidate. An unknown capability makes the
document unsupported, even if an implementation understands all remaining fields. A
recognized capability that the caller's implementation lacks is an implementation
capability failure. Neither case permits partial verification or selection of substitutes.
The closed schema rejects unknown capability strings and incomplete capability sets;
the operation's diagnostics must preserve the distinction from corrupt package content.

### Graph

Every node has required `release`, `irPackageName`, `manifestDigest`, `contentDigest`,
and `bindings`; every binding has required `irPackageName` and `target: ReleaseId`.
The graph has required `root: ReleaseId` and nonempty `nodes`. Draft.2 structural and
semantic rules apply unchanged: one exact release per PackagePath, unambiguous IR names,
one binding per dependency IR name, an existing root, existing targets, complete
reachability, and no cycle. Writers emit root first, remaining nodes by PackagePath
ascending and version descending numerically, and bindings by IR name ascending ASCII.

The full lock adds acquisition for the root as well as providers. It does not put a
second copy of requirements into `graph`; verified registry records supply the immutable
metadata against which draft.2 replay checks each graph node and binding.

### Registries

| Registry field | Type and value | Relationship |
| --- | --- | --- |
| `id` | `LocalId` | Logical registry alias used by acquisitions and evidence. |
| `snapshot` | `LocalId` | References exactly one evidence entry of kind `tuf-snapshot` whose `registry` equals this `id`. |

Every registry must serve at least one acquisition. A lock does not contain the trusted
repository identity, keys, credentials, local filesystem root, or namespace policy.
Local configuration explicitly maps each registry alias to a stable locally trusted
repository identity and to a physical root. Repository identity is stable across a
root-key rotation and byte-identical relocation; a physical pathname is neither identity
nor authority. Local policy separately authorizes that repository for parsed PackagePath
namespaces. Changing a path cannot authorize a different repository or widen a namespace.

The snapshot digest is the `digest` of the referenced `tuf-snapshot` evidence. Snapshot
versions alone do not pin a registry view. The timestamp, snapshot, targets and required
root chain form the TUF-authenticated view; there is no second signed Morphir index.
Each registry pins one snapshot, one timestamp and one top-level targets document.
The root evidence may contain the consecutive rotation chain required by its trust anchor.
Delegated targets are outside this initial profile.

### Acquisitions

| Acquisition field | Type and value | Relationship |
| --- | --- | --- |
| `release` | `ReleaseId` | Exactly one graph node has this identity. |
| `registry` | `LocalId` | References exactly one `registries[].id`. |
| `record` | `ObjectReference` | Logical target name and exact digest of the immutable registry-record file in this registry. |
| `source` | `DirectorySource` | Must equal that record's source object. |
| `statement` | `LocalId` | References `release-statement` evidence in this registry; its path and digest must equal the record's statement reference. |

Acquisitions and graph nodes form a bijection on exact `ReleaseId`. A missing provider
acquisition, duplicate acquisition even with identical values, or acquisition outside
the graph is invalid. Registry aliases do not permit duplicate acquisitions for one
release. Within one registry, two acquisitions cannot reuse one record path for different
releases: the uniqueness key is `(registry, record.path)`. Independent registries may
reuse the same logical record filename.

Record references use logical TUF target names beneath `records/`; statement references
use logical names beneath `statements/`. They are not physical filenames. With consistent
snapshots, a logical `records/x.json` and digest `sha256:H` identify the physical file
`targets/records/H.x.json`, where `H` is the 64-digit lowercase digest. Prefix only the
final filename, and never include that prefix in the logical TUF target name. Both target
reference forms use the portable relative-path grammar. Bundle directories lie beneath
`bundles/` relative to the configured registry root. Metadata evidence paths are also
registry-root-relative, beneath `metadata/`.
The path grammar is necessary but insufficient: readers must also apply the local
materialization profile's containment, link, reserved-name, collision and resource limits.
The source object cannot name an archive, URL, arbitrary filesystem directory, or hook.

### Evidence

| Evidence field | Type and value | Relationship |
| --- | --- | --- |
| `id` | `LocalId` | Globally unique alias, referenced by registry or acquisition entries. |
| `registry` | `LocalId` | References an existing registry. |
| `kind` | One of `tuf-root`, `tuf-timestamp`, `tuf-snapshot`, `tuf-targets`, `release-statement` | Exact type assertion; the referenced document must have that role and encoding. |
| `path` | `RegistryRelativePath` | For `release-statement`, a logical TUF target name beneath `statements/`. For TUF roles, a registry-root-relative historical metadata path beneath `metadata/`. |
| `digest` | `Digest` | SHA-256 of that file's exact bytes, including whitespace and final newline if present. |

An evidence ID is a reference, never an authorization token. Resolve it to one entry,
read that entry's bytes, verify the digest, then validate the asserted type and its
authentication chain. Hashing a parsed or reserialized TUF document or DSSE envelope
does not satisfy the evidence pin. TUF signed-body canonicalization and DSSE payload
verification are separate operations from this exact-file hash.

Each acquisition references one statement envelope. Each registry's evidence contains
the timestamp authenticating its pinned snapshot, the targets metadata authenticated
by that snapshot, and the root chain needed to authenticate those roles from configured
trust. These relationships are read from authenticated TUF metadata, not guessed from
filenames or a matching digest. Root-chain order follows signed root versions regardless
of evidence-array order. A snapshot alone is incomplete evidence of record membership.

Missing evidence IDs are invalid lock references. Missing files for existing references
are availability failures. Duplicate IDs or duplicate registry/path pairs are invalid,
even if their values match. Orphan statement evidence, unreferenced registries, extra
snapshots or timestamps, and unrelated targets/root metadata are invalid. A root entry
is non-orphan only when it belongs to the authentication chain for the pinned view;
TUF metadata need not have a direct lock ID reference to be connected through that chain.
Missing chain members fail evidence completeness, rather than proving an invalid signature.
Required trusted roots and newer authorization evidence may also be supplied by local
security state outside the historical lock; they do not rewrite its pinned evidence.

The lock contains historical provenance. First restore requires fresh authorization;
continued local use requires the separate durable authorization policy. A schema-valid
lock, possession of evidence bytes, and a successful hash check do not establish either.
Replay neither refreshes metadata implicitly nor rewrites the lock to record a successful
check. Reports and durable authorization state remain outside `morphir.lock`.

Historical metadata paths use positive decimal role versions without leading zeroes:
`metadata/V.root.json`, `metadata/V.timestamp.json`, `metadata/V.snapshot.json`, and
`metadata/V.targets.json`. Here `V` must equal the document's signed version. Retained
numbered timestamp copies contain the exact bytes published through the mutable
`metadata/timestamp.json` commit point. A lock pins the retained numbered copy, never
that mutable path. Logical names in signed TUF metadata remain `snapshot.json` and
`targets.json`; clients map them to the corresponding versioned physical files. The
authentication profile specifies this mapping and publication ordering in full.

## Immutable registry record

| Record field | Required type and value | Ordering and uniqueness |
| --- | --- | --- |
| `formatVersion` | String `"0.1.0-draft.3"` | Exact match. |
| `kind` | String `"LibraryRegistryRecord"` | Exact match. |
| `release` | `ReleaseId` | One immutable record per exact identity within a trusted repository. |
| `irPackageName` | Existing `IRPath` string | Same as manifest and graph. |
| `dependencies` | Existing draft.2 `Requirement[]` | Unique `irPackageName`; ascending ASCII IR name. Empty array permitted. |
| `manifestDigest` | `Digest` | Unchanged draft.1 canonical manifest digest. |
| `contentDigest` | `Digest` | Unchanged draft.1 Package content digest. |
| `source` | `DirectorySource` | Registry-relative immutable bundle location. |
| `statement` | `ObjectReference` | Exact DSSE envelope file bytes, not the decoded statement payload. |

The stored immutable record encoding is the draft.1 canonical metadata UTF-8 encoding
followed by exactly one LF byte. Dependencies must already be in the prescribed order.
No BOM, CRLF, indentation, duplicate key, extra final newline, or noncanonical object
order is allowed in stored record bytes. A readable JSON rendering in documentation
is not the stored encoding. Define:

```text
recordBytes  = canonicalMetadata(record) || UTF8("\n")
recordDigest = "sha256:" || lowercaseHex(SHA256(recordBytes))
```

This is a new record transport digest, with no domain prefix. It does not change
`manifestDigest`, `contentDigest`, or their draft.1 inputs. A reader hashes the received
bytes, verifies their canonical stored encoding and schema, then checks their TUF target
authentication. Recanonicalizing an incorrectly encoded record before hashing is invalid.

The release-to-record association in the authenticated registry is immutable. The record
does not include its own digest, signatures, current status, or local machine paths.
TUF targets metadata authenticates its exact file hash and length. Mutable yank and
revocation observations live in authenticated targets status metadata for a snapshot;
they never alter immutable records or publisher statements.

Publication is idempotent only when the repository's existing exact release maps to
identical record bytes, identical statement-envelope bytes, and the same fully verified
manifest/content identity and declared file bytes. The new request must verify successfully
under current publication policy. Reformatting a manifest preserves its draft.1 canonical
identity, but cannot change the declared file bytes. A byte-identical retry publishes no
new release, clears no status, and grants no new trust.

Different manifest/content digests under an existing identity are a release conflict.
Changing record metadata, source path, statement path, envelope signatures, or encoding
under that same identity is unsupported record replacement or signature renewal, even
when content digests match. Reject it without overwriting existing objects. New TUF
metadata may renew repository authorization of the same immutable target bytes or update
status. That operation is distinct from replacing a release record or publisher envelope.

## Release statement payload

| Payload field | Required type and value | Ordering and uniqueness |
| --- | --- | --- |
| `formatVersion` | String `"0.1.0-draft.3"` | Exact match. |
| `kind` | String `"LibraryReleaseStatement"` | Exact match. |
| `release` | `ReleaseId` | Same exact identity as manifest, record, acquisition and graph node. |
| `irPackageName` | Existing `IRPath` string | Same as manifest, record and graph node. |
| `dependencies` | Existing draft.2 `Requirement[]` | Unique IR names, ascending ASCII; same requirements as the manifest and record. |
| `manifestDigest` | `Digest` | Same verified draft.1 digest as record and graph. |
| `contentDigest` | `Digest` | Same verified draft.1 digest as record and graph. |

Encode the payload with draft.1 canonical metadata encoding, without BOM or final LF.
The DSSE signing profile supplies the exact versioned payload type and Ed25519 rules.
The statement schema describes the decoded payload only. It does not accept an unsigned
payload as a signed statement envelope. The evidence and record reference the exact DSSE
envelope file, whose digest differs from any digest of its canonical decoded payload.
The verifier parses the same authenticated payload bytes and requires their canonical
encoding; it must not verify one decoding and use another.

Publisher authorization comes from namespace-scoped local key policy. TUF target
authentication of an envelope and a DSSE key ID are insufficient publisher authorization.
Signatures remain outside the draft.1 package-content digest boundary.

## Equality and completeness

For each node, validate these relationships before reporting graph readiness:

1. `graph.nodes[].release`, acquisition `release`, record `release`, statement `release`,
   and manifest `{packagePath, version}` are equal.
2. Graph, record and statement `irPackageName` equal manifest `ir.packageName` and the
   decoded Library IR PackageName.
3. Record and statement dependencies equal the manifest dependency map projected to
   draft.2 requirements. Project each map member by adding its key as `irPackageName`,
   then sort by that name. Compare names, paths and both exact interval bounds.
4. Graph, record and statement `manifestDigest` and `contentDigest` equal the draft.1
   digests computed from the verified manifest and exact declared bytes. Every content
   declaration must match its file before the aggregate is evidence of bundle integrity.
5. Acquisition `source` equals record `source`; its statement evidence path and digest
   equal record `statement`. The authenticated registry view must include both exact
   record and statement target files. A file present on disk but absent from that view
   is not an authenticated registry release.
6. Every graph binding corresponds to exactly one requirement with equal IR name and
   PackagePath, targets the selected release, and satisfies that requirement's interval.
   Apply all draft.2 graph checks and the existing draft.1 Library verification limits.

Equality is structural after the prescribed projection; it is never a substring, prefix,
filename or version-only comparison. Package namespace authorization separately uses
parsed path components. No equality check can manufacture trust, availability, public
specification compatibility, or behavioral equivalence. A failing provider prevents graph
readiness even when the consumer has already passed.

## Review examples and schema boundary

The [unsigned worked shapes](mck/fixtures/local-registry/unsigned/README.md) include both
graph nodes, both acquisition entries, all evidence roles, both registry records and
unsigned statement payloads. Their unavailable envelope/metadata digests are visibly
marked `UNSIGNED:...`; they intentionally fail the digest grammar. They are not a valid
lock, authenticated registry, signed vector set, or compatibility-pass evidence.

| Example | Structural schema result | Required semantic or authorization result |
| --- | --- | --- |
| Two nodes, one acquisition each, complete correctly typed references | Accepts when all digests are real syntactically valid values | Graph, equality, bytes, signatures and caller authorization must still pass. |
| Duplicate acquisition for the same release | May accept, including two unequal entries with the same release | Reject duplicate acquisition; equality of duplicate entries does not excuse it. |
| Provider node without its acquisition | Accepts if at least the root acquisition remains | Reject missing provider acquisition. |
| Acquisition for a release outside the graph | Accepts | Reject orphan acquisition. |
| Record IR name, requirements or digest differs from verified manifest | May accept each document independently | Reject the specific cross-document disagreement. |
| Source `kind: "archive"` | Rejects | Unsupported source; no fallback interpretation. |
| Source `path: "/tmp/eligibility"` | Rejects | Unsafe absolute source path. |
| Unknown string in `requiredCapabilities` | Rejects | Unsupported required capability, never silently omitted. |
| Missing evidence reference, duplicate evidence ID, or orphan statement evidence | May accept | Reject reference, uniqueness or evidence-closure failure. |
| Correctly pinned bytes with invalid signatures | Accepts lock structure | Authentication fails; no authorization or materialization readiness. |

Schema validation does not enforce object-key duplication in raw JSON, canonical stored
bytes, sorted output, uniqueness by selected identity fields, graph topology, TUF
membership, cross-document equality, source containment, cryptography or policy. These
are required semantic checks, not optional schema extensions. The unsigned shapes are
review material only. The [signed two-Library fixture](mck/fixtures/local-registry/assets/signed/README.md)
now supplies exact authentication bytes and fixed first-restore expectations for review.
The operation diagnostics below are normative candidate rules; executing the draft.3
compatibility scenarios remains a separate deliverable.

## Portable paths and bounded operations

`RegistryRelativePath` uses the exact grammar above. Bundle content paths retain the
draft.1 grammar `^[a-z0-9]+(-[a-z0-9]+)*(/[a-z0-9]+(-[a-z0-9]+)*)*(\.[a-z0-9]+)?$`.
Compare complete strings, without URL decoding, Unicode normalization, case folding or
platform separator conversion. In both grammars a logical path has at most 240 ASCII
bytes, 32 components and 128 bytes per component. These are additional acquisition
bounds, not changes to the draft.1 digest or draft.2 selection algorithms.

Reject a component whose portion before its first dot, compared case-insensitively,
is `con`, `prn`, `aux`, `nul`, `com0` through `com9`, or `lpt0` through `lpt9`.
This includes extension spellings such as `con.json`. The grammars already exclude
spaces, trailing dots, alternate streams, device-path prefixes and percent escapes.
Apply reserved-name checks to logical components before adding a hash prefix.
The exact decoded names returned by directory enumeration must equal the requested
component spelling, even on a case-insensitive filesystem. Reject case-fold collisions
between directory entries before selecting either entry. Here folding means ASCII
`A` through `Z` to `a` through `z`; a non-ASCII entry is itself invalid.

Physical target paths add `targets/` and 65 bytes for `H.` to a logical target path.
Thus their registry-relative budget is 313 bytes, their leaf budget is 193 bytes,
and their maximum depth is 33 components. Bundle paths add `bundles/<contentHex>/`,
73 bytes and two components, giving 313 bytes and 34 components. Bundle components
still have the 128-byte limit. Metadata paths have no hash prefix and must obey the
240-byte logical path budget and 128-byte component budget, using the specified decimal
version spelling. Hash prefixes are generated
by the reader, never accepted as a substitute logical name. A host's configured absolute
root prefix is outside these wire budgets. Failure to support the resulting full physical
path is an environment failure, not an invalid Library.

All limits below are inclusive. MiB means 1,048,576 bytes and GiB means 1,073,741,824
bytes. Count bytes before parsing or decoding; count decoded DSSE payload bytes separately.
Depth counts edges from the JSON root at depth zero. Bound streams while reading, without
trusting file size or signed length alone. Use overflow-checked counters. The first byte,
entry or depth beyond a bound is sufficient evidence; do not finish reading an oversized
object to measure it.
Reject profile path/count bounds before accessing the named object. A lexical path
grammar or reserved-name fault uses `unsafe-path`; exceeding a numerical path bound
uses `resource-limit`.

| Resource name | Profile maximum | Scope |
| --- | --- | --- |
| `lock-bytes` | 16 MiB | One full lock. |
| `manifest-bytes`, `record-bytes`, `statement-bytes`, `envelope-bytes`, `policy-bytes` | 1 MiB each | One manifest, record, decoded payload, complete DSSE envelope, or trust policy. |
| `root-bytes`, `timestamp-bytes`, `snapshot-bytes` | 1 MiB each | One complete TUF document. |
| `targets-bytes` | 16 MiB | One complete targets document. |
| `metadata-bytes` | 256 MiB | Sum of distinct complete metadata and policy inputs in one operation, including lock, historical and current evidence, and decoded statement payloads. |
| `file-bytes` | 256 MiB | One declared content file. |
| `bundle-bytes` | 1 GiB | Manifest plus all declared file lengths for one bundle. |
| `operation-content-bytes` | 8 GiB | Sum of all bundle bytes verified in one operation, counting an exact bundle once even when shared. |
| `declared-files` | 4,096 | One manifest's content declarations. |
| `bundle-entries` | 65,536 | Files and directories beneath one bundle, including `manifest.json`, excluding its root. |
| `operation-entries` | 1,048,576 | Distinct filesystem entries visited in one operation, including metadata and staging inventories. |
| `json-depth` | 64 | Each JSON document, including payload IR and ignored TUF/DSSE extension values; this acquisition bound does not change the standalone IR format. |
| `graph-nodes` | 512 | Root plus providers. |
| `node-bindings` | 512 | Bindings or requirements for one release. |
| `graph-bindings` | 32,768 | Total bindings in one selected graph. |
| `catalog-releases` | 4,096 | Distinct release records presented for resolve/update before status filtering. |
| `registries` | 32 | Distinct repository identities involved in an operation. |
| `evidence-entries` | 2,048 | One lock's evidence array. |
| `target-entries` | 8,192 | One targets map, counting records and statements. |
| `publisher-rules`, `namespace-grants` | 1,024 each | Policy rules and total repository namespace grants. |
| `publisher-keys` | 64 | Raw keys in one publisher rule. |
| `tuf-keys` | 256 | Key objects in one root. |
| `role-keys`, `signatures` | 64 each | One TUF role's authorized key IDs, or one TUF/DSSE envelope's signatures, including duplicates. |
| `root-rotations` | 32 | Consecutive transitions in each historical or current authentication chain in one operation; a starting root is not a transition. |
| `path-bytes`, `path-components`, `component-bytes` | 240, 32, 128 | Logical registry and bundle-relative content paths, as defined above. |

Distinct metadata inputs use repository identity, role/path and exact file digest as
their key; lock and policy are counted once each. Operation byte budgets describe logical
inputs, not filesystem read retries or private copies. Entry budgets count each physical
entry once per tree, so a staged copy is a different tree. Missing and rejected entries
still count when visited. Directory inventories must be bounded too; sorting an unbounded
directory before enforcing the entry limit is invalid. At a stream/count limit, report
`observed` as exactly `maximum + 1`, even if a size declaration already advertises more.

Profile excess is `resource-limit` with `scope: "profile"`. A caller may configure a
smaller local limit and must report `resource-limit` with `scope: "local-policy"` and
that effective maximum. An implementation cannot claim full profile support while silently
using smaller limits. Local policy cannot enlarge a profile bound. Failure to allocate
memory, permission denial, or disk exhaustion below the effective bound is operational.
Reaching a graph/search bound is not proof that resolution is unsatisfiable. Such an
operation fails with its resource witness without changing draft.2 scoring or witnesses.

## Safe staging and materialization

The caller explicitly configures each trusted registry, cache and destination root.
That root may resolve through a symlink during configuration. Resolve it once, open and
retain the resulting directory handle, and anchor all later traversal to that directory.
Descendants must never follow symlinks, junctions or any reparse point. A sequence of
`lstat` followed by an ambient pathname open does not satisfy this rule. Use anchored
no-follow opens and type checks on the opened handles, or equivalent guarantees on the
host. Detect special files before an open can block on a FIFO or access a device.

Accept only directories and ordinary regular files. Reject sockets, FIFOs, devices,
symlinks, junctions and other special entries. Every regular file in the source and
destination inventory must have link count one. Never hardlink registry/cache files into
a consumer-writable location. Check actual names, types and link counts through the
anchored traversal, not only the path strings stored in metadata.

For each bundle, the exact inventory is `manifest.json`, every declared content path,
and only the nonempty directories needed to contain those files. Reject extra files,
extra empty directories, a content claim for `manifest.json`, and any declaration whose
file path is an ancestor of another declared file. Missing declared files are availability
failures. The registry as a whole may contain unreferenced immutable objects; the exact
inventory rule applies within each acquired bundle, not to all registry history.

Create a private staging directory on the destination filesystem with exclusive creation
and permissions that prevent other principals or package code from writing it. Copy
from the anchored source handles while hashing the bytes actually copied. Record and
recheck source file identity, type, link count, size and modification/change metadata
around each copy, and recheck the source inventory before accepting the copy. Observable
replacement, mutation, addition or deletion during the copy is `source-changed`. No
readiness claim depends on the source remaining unchanged after verification.

Perform manifest/content digests, payload decoding, IR identity, exports and dependency
checks against that private staged tree. Verify its complete inventory and bytes before
promotion. Mutation detection alone is not a snapshot guarantee; hashes and semantic
checks on the staged bytes provide that guarantee. A changing source that produces
different bytes must never cause those different bytes to bypass staged verification.
Make consumers read the verified staged bytes or the exact promoted tree, never reopen
the original source after verification.

Promote a verified bundle atomically without replacing an existing destination. Flush
its files and directories before promotion and the destination parent before reporting
durable success. A digest-shaped cache directory name is not proof. If a destination
already exists, including a concurrent promotion winner, reverify its inventory and
bytes before using it. Reject a corrupt existing entry rather than overwriting it or
trusting it because its name matches. Cache storage must remain owned and protected
against consumer mutation. A consumer needing writable files gets a separate copied and
verified tree. Later administrator modification is outside this guarantee; later replay
still rechecks bytes and policy.

Promotion and fresh-authorization grants are per bundle. A verified consumer can remain
cached when a provider fails. It is not a usable graph until all nodes, including the
published root, pass acquisition, current policy, integrity and draft.2 graph checks.
Never emit `graph-ready`, expose a runnable graph handle, or execute a package hook after
only a subset passes. A failure result does not assert that caches or security state
were rolled back; authenticated revocations and accepted roots remain durable as the
trust profile requires.

## Catalog boundary and release status

Resolve/update authenticates complete current views for the caller's explicitly selected
repository set before forming draft.2 catalog inputs. A lock replay uses its exact
acquisitions and does not search other repositories. Aliases are labels, never precedence.
Two aliases for the same repository identity may share the same exact pinned view; they
do not create two catalog candidates. Two different current snapshot digests for that
identity in one catalog input are `registry-view-conflict`.

Before filtering status, group authenticated records by exact ReleaseId across distinct
authorized repository identities. Different manifest/content digests, IR name or
requirements produce `catalog-record-conflict`. Otherwise more than one repository
providing that release produces `catalog-ambiguous`, even when record and statement bytes
are identical. Their provenance and mutable status remain distinct. The caller must
narrow its explicitly selected repository set to remove ambiguity; array order, alias
spelling and pathname order cannot choose a winner. Check every record in the supplied
catalog universe, including records later excluded by status. Only authenticated views
whose repository is authorized for a record's PackagePath can supply that record.

Filter `active` releases into candidates for new selection. Exclude `yanked` releases
from new selections, while permitting their already locked exact identity for replay
and frozen update nodes. Known `revoked` identities block use; no active assertion can
undo a durable revocation. Frozen nodes must still satisfy fresh authorization during
update. Pass the resulting immutable metadata and frozen pins to the unchanged draft.2
resolver. Its version ordering, scoped update rules, coexistence witnesses and failure
selection remain unchanged. Absence of candidates after filtering is resolved by those
existing rules, not by substituting a yanked or revoked release.

## Publication transaction and restart

A publication request names one expected predecessor:
`{kind: "absent"}` for the first timestamp, or
`{kind: "timestamp", digest: Digest}` for the exact current timestamp file bytes.
The digest is not the snapshot digest. The request also supplies the exact proposed
signed targets, snapshot and timestamp file bytes, with role versions carried in their
signed bodies. Producing and signing this complete successor view is the caller's
responsibility. This operation verifies and publishes supplied bytes; it does not choose
a TUF JSON serializer or generate repository signatures. Signing keys never enter the
portable lock. First verify the request's complete staged bundle,
record and publisher statement under current publication policy. A repository writer
then holds one exclusive writer lock from checking the predecessor through the final
timestamp directory flush. The lock must retain a stable lock identity across processes
and crashes; deleting and recreating a lock pathname while another process holds it is
invalid. A crashed holder must release ownership without a time-based stale-lock guess.

Under that lock, read and verify the complete committed current view, or establish that
it is absent in an explicitly initialized empty repository. Compare its exact timestamp
digest to the expected predecessor. Mismatch is `publication-conflict`, including when
another writer just published identical requested bytes. Do not merge, rebase or retry
against another predecessor automatically. Two writers with the same base therefore
have one winner; the second receives the exact observed successor digest.

Check immutable release identity and idempotence before reserving new metadata versions.
Identical republication returns `idempotent` with the current timestamp digest and leaves
all target statuses unchanged. A changed manifest/content identity is `release-conflict`.
Changing the record or envelope with the same content identity is
`record-replacement-unsupported`. Even an idempotent request must pass current publication
policy. A yanked or revoked existing release never becomes active through this operation.
An idempotent request returns before inspecting the proposed successor metadata. It
reserves no versions and publishes no status or metadata changes. Proposal bytes are
opaque inputs until the non-idempotent proposal-validation step below.

For a non-idempotent request, authenticate the complete proposed successor under the
writer lock after predecessor and immutable-identity checks, before reserving versions
or installing any registry objects. Apply the trust profile's role signatures, current
root authority, fixed-clock freshness, bounded decoding and exact signed links. The
proposed timestamp must authenticate the exact proposed snapshot, and that snapshot must
authenticate the exact proposed targets bytes. The targets view must retain every existing
record and statement association, exact target pins and release status, and add exactly
the requested record and statement, with record status `active` for the new release. Their pins
must match the verified request's exact bytes. Publishing a release cannot also change
another release's status or remove its targets. Status changes remain a distinct operation.

Malformed proposed metadata uses `invalid-input`; unsupported literals use the existing
supported-string codes. Signature, expiry, digest and length failures use the corresponding
existing codes and witnesses. A proposed view that changes or omits a required association,
pin or status uses `cross-document-mismatch` with a `violation` witness pointing into the
proposed targets document. Use `target-link-mismatch` for changed/missing target membership
or pins and `invalid-value` for a changed status or an additional unrequested release.
Proposal failures have phase `publication`. A proposal-validation failure must not
reserve a role version or install part of the proposal.

The filesystem must provide anchored no-follow traversal, exclusive file creation,
cross-process writer exclusion, atomic same-filesystem directory promotion without
replacement, atomic replacement of the timestamp file, and durable file and directory
flush ordering. The timestamp replacement must expose either complete old bytes or
complete new bytes to readers. Check these capabilities before publication. A filesystem
or network mount without the required guarantees fails `filesystem-unsupported`; do not
emulate atomic publication through copy/delete. A supported flush or rename that fails
at runtime is an operational I/O failure. Private staging, immutable objects, and the
timestamp replacement must use the relevant destination filesystem.

For a non-idempotent transaction, perform the following persistence sequence under the
writer lock. Each step completes its durability requirements before the next step.

1. For each proposed targets, snapshot and timestamp version, require a positive number
   greater than every reserved number, every existing numbered filename for that role,
   and every committed version. The floor is the maximum of those numbers, or zero when
   none exist. Reject a proposed version less than or equal to its floor with
   `metadata-rollback` at phase `publication`, using `trusted` for that floor and
   `received` for the proposed version. Check all three before making any reservation.
   Reserve exactly the supplied versions in private durable publisher state. Persist
   and flush the reservation and its parent directory before exposing numbered metadata.
   Abandoned reservations are burned. A caller cannot derive valid proposed versions
   from `current + 1` alone. The reservation format is private and is not a second
   public index or reader commit point.
2. Install the verified bundle, record and statement through no-replace promotion.
   Existing destinations must verify as the exact expected objects. Flush all new files
   and their parent directories. An occupied immutable pathname with different bytes is
   `immutable-object-conflict`; it must never be overwritten, even if unreferenced.
3. Install the exact verified proposed targets bytes at the reserved numbered path
   without replacement and flush file and parent. Install the exact proposed snapshot
   bytes authenticating that targets file, then flush file and parent. Do not reserialize
   or sign replacement bytes during installation.
4. Install the exact proposed timestamp bytes at the reserved
   `metadata/V.timestamp.json` without replacement and flush file and parent. Prepare
   a private file containing identical timestamp bytes and flush it.
5. Atomically replace `metadata/timestamp.json` with that private file and flush the
   metadata directory. This replacement is the sole public commit point. Report
   `committed` only after the final directory flush succeeds.

Root rotation is a separate consecutive chain, not one of the freely skipped role
reservations. From root `V`, the next root is exactly `V + 1` and must meet both old
and new thresholds. If interruption left `V + 1` present, reuse it only after verifying
its exact bytes and rotation authority; a different proposed root at that occupied
version is `immutable-object-conflict`. Do not skip to `V + 2` or overwrite the old file.
Any root needed to authenticate a new view must be durably installed before that view.
The per-operation rotation bound does not authorize skipping intermediate roots.

| Interruption point | Required restart observation and action |
| --- | --- |
| Before durable reservation | Prior timestamp remains current. Recover private state, recheck predecessor, then require proposed versions above every surviving reservation/file/commit. |
| After reservation, object promotion, targets, snapshot, or retained timestamp, but before current timestamp replacement | Prior timestamp remains current. Ignore unreferenced objects for release membership, retain occupied immutable paths, burn abandoned role reservations, and start a new transaction against the observed predecessor. |
| During current timestamp replacement | Recover a complete old or complete new current timestamp, verify its complete referenced view, and use that exact digest as the observed predecessor. Partial current bytes are an unsupported durability outcome and require operator recovery. |
| After replacement but before successful final directory flush | Return `commit-outcome-uncertain` if still running. The new view may already be visible. Do not roll back automatically. Restart verifies the exact current view and then determines whether a retry is idempotent or conflicts. |
| After successful directory flush | The new complete view is durable. A retry against the old base conflicts; a retry against the current base with identical release bytes is idempotent. |

No reader may infer publication from an unreferenced numbered file, bundle or reservation.
Readers capture one current timestamp file through a handle and use only its authenticated
snapshot/targets links. A later timestamp replacement does not change those pinned bytes.
Recovery never promotes an orphan view automatically. Delete only private staging objects
known to belong to an inactive transaction; never delete or rewrite immutable objects to
make a retry fit. Garbage collection is outside this profile. Missing/corrupt publisher
state or a committed view that cannot be verified blocks publication pending explicit
recovery; it is not an empty repository.

## Operation results and diagnostics

These are portable operation results for the candidate profile, not new fields in the
lock. All result objects and tagged witness objects are closed and all listed fields
are required. No implicit defaults or null values exist.

`invalid-input` describes a malformed operation/document input. `domain-rejection`
means the requested operation cannot satisfy a profile or authorization rule; it is
not a general verdict that the Library is invalid. In particular a stricter local
resource policy does not change package validity. `unsupported-capability` means the
required interpretation or host guarantee is unavailable. `operational-failure` means
required bytes or host execution are unavailable, or a durable outcome is uncertain.
Missing content is an availability failure, separate from corrupt content and denied
authority; possession of a lock does not imply its referenced bytes are present.

```text
GraphReady = {ok: true, kind: "graph-ready", graph: LockedGraph,
              verified: ReleaseId[]}
Published  = {ok: true, kind: "publication", outcome: "committed" | "idempotent",
              timestampDigest: Digest}
Refreshed  = {ok: true, kind: "registry-refreshed", registry: LocalId,
              timestampDigest: Digest, snapshotDigest: Digest}
Failure    = {ok: false, diagnostic: {category: Category, code: Code,
              phase: Phase, witnesses: Witness[]}}
Category   = "invalid-input" | "domain-rejection" | "unsupported-capability"
             | "operational-failure"
```

`verified` contains every graph release exactly once, root first and remaining releases
in graph presentation order. `graph` is the unchanged draft.2 normalized graph. A failed
operation never includes a partial `graph-ready` result. Resolve/update may expose their
successful lock as a separate output artifact only after graph readiness; diagnostics
do not mutate a prior lock. Publication reports the exact committed current timestamp
file digest, including for an idempotent request.

The operation vocabulary for this contract is `resolve-library`, `update-library`,
`replay-library`, `publish-library` and `refresh-library-registry`. These names identify
adapter operations, not new public CLI commands. Resolve takes a fixed published root
ReleaseId and an explicitly chosen repository set. Update also takes the previous full
lock and the unchanged draft.2 update scope/targets. Replay takes the full lock and uses
its exact acquisitions. All three return `GraphReady` or `Failure`; resolve/update also
produce the full lock artifact on success. Publish takes one release bundle, immutable
record, envelope, expected predecessor and complete proposed signed successor metadata,
and returns `Published` or `Failure`. It verifies and commits those exact supplied
metadata bytes; producing signatures is outside this operation.
Refresh takes one explicitly configured registry and returns `Refreshed` or `Failure`
after current TUF verification and required durable state transitions. It grants no
per-release authorization without bundle verification. Its two digest fields identify
the exact accepted current timestamp and snapshot bytes. Each operation receives explicit
local configuration, policy, fixed clock and protected client/publisher state as applicable.
No operation implicitly invokes refresh during replay. Pending MCK case data may bind
these inputs to fixture references; no fixture may forge a successful previous grant.

### Phases and fault selection

| Phase, in precedence order | Required checks |
| --- | --- |
| `decode` | Bound and decode the caller's lock/request/policy JSON; reject malformed UTF-8, BOM, JSON or surrogate escapes, then duplicate decoded keys. |
| `support` | Recognize correctly typed format, policy, profile, required-capability and source-kind strings before generic closed-schema rejection. |
| `shape` | Remaining schema/type/grammar/canonical-encoding checks for caller input. |
| `structure` | Lock/acquisition/evidence uniqueness and closure, draft.2 lock identity/topology, policy uniqueness and thresholds. |
| `repository` | Configured roots and filesystem guarantees; bounded evidence reads; exact evidence pins; historical continuity; current TUF signature, expiry, rollback and link checks. |
| `authorization` | Effective namespace/publisher rules, authenticated status and durable revocations; publisher threshold; fresh authorization or eligible previous authorization. |
| `catalog` | Resolve/update repository-view conflict and cross-repository release ambiguity/conflict, then status filtering. Skipped for replay/publication. |
| `bundle` | Exact inventory, anchored copy, byte verification and draft.1 Library semantics for each node. |
| `graph` | Cross-document equality and draft.2 metadata-dependent binding/replay checks, or unchanged resolve/update result. |
| `publication` | Writer lock, expected predecessor, immutable identity/idempotence, complete proposed signed successor verification, strict role-version floors, reservations and precommit installation. Skipped for graph acquisition. |
| `commit` | Required durable security-state commits, verified cache promotion, or timestamp replacement and final flush. |

Phases order checks only when their prerequisites exist. JSON loaded from a registry
during `repository`, or a manifest during `bundle`, undergoes the same decode, supported
literal and shape checks there; its reported phase remains the enclosing phase. Per-node
bundle verification and promotion may finish before another node fails. Such scheduling
does not change graph readiness or final diagnostic precedence. Required root/revocation
state commits occur as soon as the trust profile requires them, even before later phases.
Their failures report the phase in which persistence was required.

Inspect a supported-string discriminator only after its enclosing known object and the
field's string type are established. Missing or wrong-type values are shape violations;
an unknown string is `unsupported-profile`, `unsupported-source`, `unsupported-capability`
or `unsupported-payload-type`, as applicable. Unsupported `kind`, `formatVersion`,
resolution `policy`/`profile`, `continuedUse`, TUF `spec_version`/key scheme and package
custom status strings use `unsupported-profile`. Unknown evidence kinds do too. As in
draft.2, a missing, wrong-type or unknown discriminator suppresses variant-specific
checks; common fields still validate. A supported required capability absent from the
implementation uses `capability-unavailable`. Missing or duplicate required capability
entries remain shape/identity violations. Do not turn an unknown supported-string into
a generic schema `invalid-value` or silently drop it.

Stop at the first phase with a reportable failure. Within it, common acquisition faults
have precedence in this order: `commit-outcome-uncertain`, `io-failure`,
`filesystem-unsupported`, `resource-limit`, `unsafe-path`, `source-changed`,
`missing-content`, `invalid-input`, supported-string/capability codes in ASCII code
order, then domain codes in ASCII code order. Select one code and accumulate independent
witnesses for that code only. Never invent dependent violations after a prerequisite
failed. Never continue unsafe traversal, blocking special-file opens, a failed write,
or an over-limit parse merely to accumulate witnesses. Fatal I/O/resource/unsafe traversal
faults report one witness for the first logical object in deterministic processing order.
Parallel implementations must select as though processed in that order.

Order logical objects by lock then policy then request, registry aliases in ASCII order,
evidence paths in ASCII order, and graph root then remaining nodes in graph order; within
a bundle use `manifest.json` first then paths in ASCII order. When a directory exceeds
its entry bound, the witness identifies the directory, not an arbitrary last returned
entry. An unsafe directory with several unsafe entries identifies its first ASCII entry
after bounded enumeration. Duplicate decoded JSON keys use their RFC 6901 pointers;
input array indices remain original, so invalid-input pointer spelling need not be
permutation invariant. Witnesses sort by the lexicographic UTF-8 bytes of their canonical
JSON encoding, with object keys sorted and no whitespace; remove exact duplicate
witnesses. This diagnostic encoding permits JSON booleans and integers and does not
reuse the number-free package metadata encoder. It never includes absolute local paths,
OS error strings, random staging names or wall-clock timing.

### Closed witness vocabulary

`Subject` is one of `{kind: "lock"}`, `{kind: "policy"}`, `{kind: "request"}`,
`{kind: "repository", registry: LocalId}`, or
`{kind: "object", registry: LocalId, path: string}`. An object path is the logical
registry path, or source path plus bundle-relative path, before physical hash-prefix
mapping. A malformed input path may appear verbatim in a witness. The string is data,
never a path to access. `Revision` is the publication predecessor union defined above.
`Decimal` is a nonnegative integer encoded as decimal digits without leading zeros,
except `"0"`. Times are UTC `YYYY-MM-DDTHH:mm:ssZ` with a four-digit year; subsecond
clock inputs are floored to seconds before comparison. Witness arrays are nonempty.

| Witness tag | Exact fields in addition to `kind` |
| --- | --- |
| `violation` | `subject: Subject`, `pointer: string`, `rule: ViolationRule`. |
| `unsupported` | `subject: Subject`, `pointer: string`, `value: string`. |
| `resource` | `subject: Subject`, `resource: ResourceName`, `scope: "profile" | "local-policy"`, `maximum: Decimal`, `observed: Decimal`. ResourceName is exactly a name in the bounds table. |
| `path` | `subject: Subject`, `rule: "grammar" | "reserved-name" | "case-collision" | "case-spelling" | "symlink" | "hardlink" | "special-file" | "unexpected-entry" | "manifest-claim" | "file-ancestor" | "escape"`. |
| `missing` | `subject: Subject`. |
| `changed` | `subject: Subject`. |
| `digest` | `subject: Subject`, `expected: Digest`, `actual: Digest`. |
| `length` | `subject: Subject`, `expected: Decimal`, `actual: Decimal`. |
| `authentication` | `subject: Subject`, `role: "root" | "timestamp" | "snapshot" | "targets" | "publisher"`, `required: Decimal`, `verified: Decimal`. Count distinct authorized raw keys. |
| `repository-authority` | `registry: LocalId`, `rule: "repository-unconfigured"`. |
| `authority` | `registry: LocalId`, `release: ReleaseId`, `rule: "namespace-denied" | "publisher-rule-missing" | "previous-grant-ineligible" | "revoked" | "fresh-view-required"`. |
| `continuity` | `registry: LocalId`, `fromVersion: Decimal`, `throughVersion: Decimal`, `missingVersions: Decimal[]`. Sort missing versions numerically, uniquely; versions are positive. |
| `time` | `registry: LocalId`, `role: "root" | "timestamp" | "snapshot" | "targets" | "clock"`, `at: string`, `boundary: string`. Both strings use the UTC spelling above. |
| `rollback` | `registry: LocalId`, `role: "root" | "timestamp" | "snapshot" | "targets"`, `trusted: Decimal`, `received: Decimal`. |
| `membership` | `registry: LocalId`, `release: ReleaseId`, `path: string`. |
| `catalog` | `release: ReleaseId`, `candidates: CatalogCandidate[]`. |
| `views` | `repository: Digest`, `snapshots: Digest[]`. Unique ASCII-sorted digests. |
| `release-conflict` | `release: ReleaseId`, `existingManifest: Digest`, `proposedManifest: Digest`, `existingContent: Digest`, `proposedContent: Digest`. |
| `replacement` | `release: ReleaseId`, `field: "record" | "statement"`, `existing: Digest`, `proposed: Digest`. |
| `revision` | `expected: Revision`, `actual: Revision`. |
| `immutable` | `subject: Subject`, `existing: Digest`, `proposed: Digest`. |
| `filesystem` | `subject: Subject`, `guarantee: "anchored-no-follow" | "exclusive-create" | "writer-lock" | "atomic-no-replace" | "atomic-replace" | "durable-flush" | "physical-path"`. |
| `io` | `subject: Subject`, `action: "open" | "read" | "enumerate" | "create" | "copy" | "lock" | "reserve" | "rename" | "flush" | "state-read" | "state-write"`, `reason: "permission" | "no-space" | "memory" | "interrupted" | "state-corrupt" | "other"`. |
| `uncertain` | `registry: LocalId`, `previous: Revision`, `attempted: Digest`. |
| `resolver` | `diagnostic`: exact unchanged draft.2 diagnostic object. |
| `library` | `release: ReleaseId`, `subject: Subject`, `pointer: string`, `rule: "ir-decode" | "ir-identity" | "export-missing" | "export-private" | "dependency-identity" | "payload-undeclared"`. |

`CatalogCandidate` is `{repository: Digest, snapshot: Digest, record: Digest,
manifestDigest: Digest, contentDigest: Digest}`; sort by repository then snapshot then
record, all ASCII. At least two candidates occur in a catalog witness. `ViolationRule`
contains the draft.2 violation rules plus `noncanonical`, `missing-reference`,
`orphan-reference`, `evidence-kind-mismatch`, `target-link-mismatch`,
`dependency-mismatch` and `threshold-exceeds-keys`. The original draft.2 rules and their
pointer semantics remain unchanged when enclosed in a `resolver` witness. For local
cross-document failures, point at the disagreeing lock/record/statement/manifest field;
use `identity-mismatch`, `digest-mismatch`, `dependency-mismatch` or `binding-mismatch`
as appropriate. Do not report both a derived aggregate mismatch and a failed declared
file digest when the aggregate could not be computed from fully verified inputs.
The `library` witness labels existing draft.1 semantic checks; it does not assume an
existing draft.1 diagnostic wire format. Point at `/ir/packageName` for IR identity,
the relevant `/exports/<escaped-name>` or `/dependencies/<escaped-name>` in the manifest
for export/dependency faults, `/ir/payload/path` for an undeclared payload, and the empty
pointer on the payload object for an IR decode failure.

An unconfigured repository always uses `repository-authority`, including during
`refresh-library-registry`, where no release is involved. Namespace and publisher checks
use `authority` with the actual release being checked. The repository-scoped witness
has no `release` property; the release-scoped witness requires a real ReleaseId, never
null or a sentinel identity.

### Stable code table

The following table is exhaustive. Code spelling and witness tags are part of the
contract. A code accepts only its listed tags; human-readable text may be emitted outside
the portable result but cannot replace or change these fields.

| Code | Category | Witness tag and meaning |
| --- | --- | --- |
| `invalid-input` | `invalid-input` | `violation`; malformed JSON, duplicates, shape, identity/closure or canonical encoding errors. |
| `unsupported-profile`, `unsupported-source`, `unsupported-capability`, `unsupported-payload-type`, `capability-unavailable` | `unsupported-capability` | `unsupported`; recognized field position with unsupported literal or unimplemented required capability. |
| `filesystem-unsupported` | `unsupported-capability` | `filesystem`; required host guarantee unavailable, including physical full-path support. |
| `resource-limit` | `domain-rejection` | `resource`; explicit profile or stricter caller policy bound exceeded. |
| `unsafe-path` | `domain-rejection` | `path`; unsafe inventory, entry type or traversal. |
| `source-changed` | `domain-rejection` | `changed`; source mutation observed during the copy interval. |
| `missing-content` | `operational-failure` | `missing`; a referenced evidence, record, statement, manifest or declared file is absent. |
| `digest-mismatch` | `domain-rejection` | `digest`; exact bytes disagree with their required digest. |
| `length-mismatch` | `domain-rejection` | `length`; exact byte length disagrees with authenticated metadata. |
| `signature-invalid` | `domain-rejection` | `authentication`; distinct authorized signatures do not reach the required threshold. |
| `unauthorized-repository` | `domain-rejection` | `repository-authority` with repository-unconfigured, or release-scoped `authority` with namespace-denied. |
| `unauthorized-publisher`, `previous-authorization-ineligible`, `release-revoked`, `freshness-required` | `domain-rejection` | `authority`; respectively publisher-rule-missing, previous-grant-ineligible, revoked, or fresh-view-required. |
| `historical-continuity-missing` | `domain-rejection` | `continuity`; required original root or consecutive historical root bytes are absent. Takes precedence over generic missing-content for these root bytes. |
| `metadata-expired`, `trusted-time-unavailable` | `domain-rejection` | `time`; respectively `at >= boundary` for a role expiry, or clock `at < boundary` for retained last successful fresh authorization. |
| `metadata-rollback` | `domain-rejection` | `rollback`; current refresh falls below a retained role floor, or a proposed publication version is less than or equal to its reservation/file/commit floor. Equality is forbidden for new publication; ordinary TUF refresh equality rules remain unchanged. Historical verification never modifies either floor. |
| `target-membership-missing` | `domain-rejection` | `membership`; authenticated view does not contain the required exact target. |
| `cross-document-mismatch` | `domain-rejection` | `violation`; independently valid objects disagree. |
| `registry-view-conflict` | `domain-rejection` | `views`; one repository identity supplies different current views. |
| `catalog-record-conflict`, `catalog-ambiguous` | `domain-rejection` | `catalog`; conflicting immutable meaning, or multiple authorized provenance choices. Conflicting meaning takes precedence over ambiguity for a release. |
| `resolution-invalid` | `invalid-input` | `resolver`; unchanged draft.2 `invalid-input` or `invalid-lock` diagnostic. |
| `resolution-unsupported` | `unsupported-capability` | `resolver`; unchanged draft.2 `unsupported-capability` diagnostic. |
| `resolution-rejected` | `domain-rejection` | `resolver`; any other unchanged draft.2 rejection, including incomplete input, unsatisfiable requirements and update-scope conflict. |
| `library-rejected` | `domain-rejection` | `library`; unchanged draft.1 semantic verification failure. |
| `publication-conflict` | `domain-rejection` | `revision`; current timestamp differs from the requested predecessor. |
| `release-conflict` | `domain-rejection` | `release-conflict`; immutable release content identity differs. |
| `record-replacement-unsupported` | `unsupported-capability` | `replacement`; record or envelope replacement under an existing content identity. |
| `immutable-object-conflict` | `domain-rejection` | `immutable`; occupied immutable file has other bytes. For an occupied bundle, use its verified manifest/content conflict or integrity failure instead. |
| `io-failure` | `operational-failure` | `io`; operation could not complete due to host I/O/allocation or corrupt private security/publisher state. Absence of referenced public content is missing-content, not generic I/O. |
| `commit-outcome-uncertain` | `operational-failure` | `uncertain`; timestamp replacement may be visible but durability was not confirmed. No domain verdict or automatic rollback follows. |

When complete historical proof exists but only expired fresh metadata is available,
first restore reports `metadata-expired`; when no complete fresh view is available at
all it reports `freshness-required`. Eligible continued use does not fail merely because
old metadata expired. A wrong namespace is an authority failure; an authorized publisher
rule whose signatures do not meet threshold is `signature-invalid`, including signatures
made solely by unauthorized keys. A missing historical root reports continuity failure
even if newer fresh authorization succeeds. A clock rollback cannot grant fresh authority.

For simultaneous failures, malformed input precedes unsupported literals, which precede
remaining shape errors. Structural graph faults precede reading missing package bytes.
Validly authenticated revocation precedes a changed payload. Bundle digest failure precedes
metadata-dependent binding failure. Expected-predecessor conflict precedes immutable
identity comparison once publication holds the writer lock. A post-replacement flush
failure is always uncertain, never a successful publish or an invalid-release verdict.

### Deterministic scenario checkpoints

MCK cases use real isolated temporary registry, cache, destination and client-state
directories, fixed clocks and explicit barriers. A checkpoint is the closed object
`{operation: LocalId, boundary: "before" | "after", step: Step, subject: Subject}`.
The operation ID is assigned by the scenario, not generated by an implementation.
The subject identifies the repository or logical object affected, never a private
staging pathname. `after` means the complete step, including its stated flush, finished.

| Step | Exact transition |
| --- | --- |
| `writer-lock` | Acquire the repository writer lock. |
| `predecessor-check` | Verify current committed view and compare expected timestamp. |
| `version-reservation` | Durably commit the next role-version reservation. |
| `bundle-install` | Install and flush one immutable verified registry bundle. |
| `record-install`, `statement-install` | Install and flush that immutable target file and parent directory. |
| `targets-install`, `snapshot-install`, `retained-timestamp-install` | Install and flush that numbered metadata file and parent directory. |
| `timestamp-replace` | Atomically replace current timestamp with the already flushed private timestamp file; excludes final directory flush. |
| `timestamp-directory-flush` | Complete the final metadata directory flush. |
| `source-inventory` | Complete the first bounded bundle inventory. |
| `source-file-copy` | Copy and hash one file, including its source handle checks. |
| `source-recheck` | Complete final source inventory and mutation checks. |
| `staged-verification` | Verify one staged bundle's inventory, exact bytes and Library semantics. |
| `cache-promotion` | Promote and durably flush one verified cache tree, or verify an existing winner. |
| `bundle-ready` | Complete one release's verified cache promotion and every required durable per-release authorization commit. This aggregate checkpoint imposes no order between those steps and does not make the graph ready or permit hooks. Its subject is the bundle's logical source directory. |
| `security-update-marker` | Durably record the trust profile's in-flight security update before accepting candidate status. |
| `security-state-commit` | Durably commit accepted roots, learned revocations or a completed per-release grant, with the trust profile's required transaction context. |

Fixtures can stop an invocation at an exact checkpoint, release it, inject one normalized
I/O failure into that step, or crash it without returning an operation result. Restart
opens the same surviving directories and durable state in a new process. Crash recovery
must not inherit memory or synthesize a prior successful result. An `after` checkpoint
does not retroactively fail its completed step; failures target `before`. Timestamp
visibility and final durability therefore have separate checkpoints.

The scenario's ordered controller actions determine which writer holds the lock first,
which file changes during a copy, and which persistence boundary a crash interrupts.
Filesystem mutation actions refer to fixed test assets and logical paths, not executable
package scripts. Previously authorized replay scenarios establish grants through successful
fresh `replay-library` operations, then advance the injected clock or remove cache bytes.
Two writers can receive one fixed predecessor and advance in a prescribed order. No case
may rely on sleep duration, wall-clock races, filesystem listing order or random staging
names. The shared MCK case schema defines the controller action encoding; these checkpoint
and operation names define its required meanings.

Specifications, schemas and fixed data live in `finos/morphir`. The shared MCK core in
`finos/morphir-typescript` owns case loading, execution, comparison and reporting. This
candidate adds no independent checker, registry client, generator or runtime implementation.
