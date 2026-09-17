# Candidate local Library trust profile

Status: experimental `0.1.0-draft.3`. Wire-contract and signed-fixture reviews were approved
on 2026-09-17. Shared MCK and package runtime implementation may proceed.
This document specifies no implemented package client or interoperability claim.
It supplements the [local Library contract](local-library-contract.md).

## Adopted protocols and boundaries

Repository authentication follows [TUF 1.0.36, pinned source](https://github.com/theupdateframework/specification/blob/59e601ed29c0d2e497264ae8b31c11b8ef07df1e/tuf-spec.md).
Publisher signatures follow DSSE 1.0.2's [protocol](https://github.com/secure-systems-lab/dsse/blob/d3beff7f8616e32cbbb1ec40b20a669c0e85eae6/protocol.md)
and [JSON envelope](https://github.com/secure-systems-lab/dsse/blob/d3beff7f8616e32cbbb1ec40b20a669c0e85eae6/envelope.md).
These pinned documents, including their client algorithms, are normative where this
profile delegates to them. This profile fixes their application choices below.

The existing [tool trust profile](../../docs/spec/tool-release-metadata/index.md) and
[`TrustedToolRepository`](../../ecosystem/morphir-rust/crates/morphir-distribution/src/tool_repository.rs)
show reusable TUF, filesystem transport and persistent-state machinery. Their installed-tool
policy, publisher authority, limits, descriptors and inventory do not become package rules.
Model packages remain a separate artifact domain and execute no package-controlled hooks.

Repository authority and publisher authority are independent requirements. A TUF targets
signature does not authorize a package publisher. A publisher signature does not authorize
a repository, location, release status or first restore. A lock supplies neither authority.

## Local trust policy

The [policy schema](schemas/package-trust-policy.schema.json) is JSON Schema 2020-12.
All fields below are required. Unknown properties at every policy object level fail.
Empty `repositories` or `publisherRules` arrays are valid and grant no corresponding
authority. No missing-field defaults, environment-derived grants or package-provided keys
are permitted. The conventional permissive continued-use choice must be written explicitly.

| Object | Fields and meaning |
| --- | --- |
| Policy | `formatVersion: "0.1.0-draft.3"`, `kind: "LibraryTrustPolicy"`, `repositories: Repository[]`, `publisherRules: PublisherRule[]`, `continuedUse: "previous-authorization"` or `"fresh-metadata"`. |
| Repository | `identity: Digest`, `bootstrapRoot: BootstrapRoot`, `namespaces: Namespace[]`. Identity is unique across repositories; namespaces are nonempty and unique within each repository. |
| BootstrapRoot | `version: PositiveInteger`, `digest: Digest`. Pins the signed root version and SHA-256 of its exact file bytes, including signatures and whitespace. |
| PublisherRule | `namespace: Namespace`, `publicKeys: PublicKey[]`, `threshold: PositiveInteger`. Namespace is unique across rules; keys are nonempty and unique within a rule. Threshold cannot exceed their count. |
| Namespace | Full lowercase dotted PackagePath authority followed by zero or more complete lowercase path components, using the schema grammar. No wildcard or trailing slash. |
| PublicKey | Exactly 64 lowercase hex characters encoding 32 raw Ed25519 public-key bytes. No PEM, DER, key identifier or secret key. |
| PositiveInteger | JSON integer from 1 through 9007199254740991, inclusive. Lexically use decimal digits without leading zeros, fraction or exponent. |

Policy JSON rejects duplicate decoded member names, a BOM and non-ASCII strings. Its
integers are an explicit exception to the draft.1 metadata domain, which has no numbers.
Array input order does not affect authorization. Writers sort repositories by identity,
rules by namespace, and namespaces and public keys lexicographically. Semantic uniqueness
and the threshold-to-key-count comparison are required beyond schema validation.

A namespace matches only when the complete authority is equal and its path-component list
is a prefix of the parsed PackagePath component list. `example.com/finance` covers itself
and `example.com/finance/eligibility`, but not `example.com/finance-other`,
`other.example.com/finance`, or `example.com.evil/finance`. `example.com` covers all package
paths under that exact authority. Repository namespaces form a union of grants. For publisher
authorization, choose the matching rule with the greatest number of path components.
There is no fallback to a broader rule if that rule's signatures fail, and no threshold
pooling across rules. No match means unauthorized.

Local configuration maps each lock registry alias to one policy repository identity and
one explicit physical directory. Multiple authorized repositories do not define priority
by array order. Acquisition ambiguity or conflicting records must be diagnosed before
passing a catalog to draft.2 resolution. The operation contract defines those diagnostics.

### Bootstrap and repository identity

At repository creation, define `identity` as `sha256:` followed by the lowercase SHA-256
digest of TUF canonical JSON bytes for the original root's complete `signed` object. Keep
that identity for the repository's lifetime. It is distinct from an exact root-file digest.
Out-of-band provisioning authorizes the pair of this fixed identity and `bootstrapRoot`.
Provisioning a later root, such as version 7, must explicitly retain the original identity;
clients must not recompute identity from version 7. A new machine can trust that explicit
pair without possessing the original root. A relocation changes only the local directory.

The configured identity also pins the original root's signed body for historical provenance.
When supplied later, that original root must match this configured body digest and satisfy
its self-threshold. Its forward rotation chain can authenticate old lock evidence. This
historical anchor does not replace the newer bootstrap or current root for fresh checks.
An identity asserted by an untrusted lock, cache or repository cannot provision this pin.

Root bytes may come from a local file, cache or lock evidence, but must match the independently
configured bootstrap pin and version and satisfy root self-signature and profile checks.
Neither a root embedded in a lock nor a matching self-signature authorizes its own pin.
An already bootstrapped client uses its durable current root. Editing `bootstrapRoot` never
replaces or rolls back that root automatically; it is a provisioning input for new state.
A disconnected root cannot repair compromised trust by ordinary refresh. Explicit trust
recovery is outside this profile and cannot inherit old continued-use grants implicitly.

## TUF package mapping

Use the TUF JSON format, Ed25519 keys and signatures, SHA-256 hashes, all four top-level
roles, `spec_version: "1.0.36"`, and `consistent_snapshot: true`. No delegated targets are
supported. Role thresholds come from root metadata and must be positive. This candidate
does not inherit the tool repository's production threshold defaults. TUF key objects use
`keytype: "ed25519"`, `scheme: "ed25519"`, and hex `keyval.public`; TUF signatures are hex,
not DSSE base64. Producers emit lowercase hex. All role thresholds also require distinct
raw public keys, so alternate key objects or key IDs for one key cannot enlarge a quorum.

The authenticated registry view is the top-level snapshot together with the targets file
it authenticates. Timestamp authenticates that snapshot. The snapshot `meta` contains
exactly `targets.json`; timestamp `meta` contains exactly `snapshot.json`. Both entries
include required `version`, exact byte `length` and `hashes.sha256`. Each target entry
likewise includes `length` and `hashes.sha256`. Lengths are nonnegative integers; versions
are positive integers. Verify every advertised supported hash, with SHA-256 mandatory.
Digest pins in a lock never replace these signed links.

| Logical object | Authenticated relationship | Physical location relative to registry root |
| --- | --- | --- |
| Record `records/<parent>/<leaf>` | Top-level targets entry keyed by the exact logical name; exact record bytes match its length and SHA-256. | `targets/records/<parent>/<H>.<leaf>` where `H` is that file's lowercase SHA-256, without `sha256:`. |
| Statement `statements/<parent>/<leaf>` | Targets entry keyed by the exact logical name; record `statement` and lock evidence agree on name and exact envelope digest. | `targets/statements/<parent>/<H>.<leaf>`. |
| Snapshot and targets | Logical `snapshot.json` and `targets.json` in their parent metadata. | `metadata/V.snapshot.json`, `metadata/V.targets.json`, with the respective signed version `V`. |
| Root | Independently pinned bootstrap or next authenticated rotation. | `metadata/V.root.json`. |
| Timestamp | Current commit point and byte-identical retained historical evidence. | Mutable `metadata/timestamp.json`; immutable `metadata/V.timestamp.json`. |

`<parent>/` may be empty or contain multiple permitted components. Prefix only the leaf
filename with the target hash. Record/statement references never contain the physical hash
prefix. All logical and physical paths must meet the materialization profile's path and
containment rules. Bundles use `bundles/<contentHex>`, where `contentHex` is the record's
content digest without `sha256:`. A bundle is verified through its manifest and declared
files; its directory is not a TUF target. No directory name establishes integrity.

### Signed release status

Every record target entry has the following exact `custom.morphir` object. All four fields
are required; no additional fields are allowed inside this object.

```json
{
  "formatVersion": "0.1.0-draft.3",
  "kind": "LibraryRelease",
  "release": {"packagePath": "example.com/finance/eligibility", "version": "1.2.0"},
  "status": "active"
}
```

`release` uses draft.2 `ReleaseId` and must equal the record. `status` is exactly `active`,
`yanked` or `revoked`. Every statement target has exactly `formatVersion`,
`kind: "LibraryReleaseStatement"`, and `release` inside `custom.morphir`, with the same
version and identity rules, and no status. The enclosing TUF objects may retain unrelated
custom members and other unknown fields under TUF's extension rules. The package view
contains only these record and statement target kinds. Each statement is referenced by
one record; every record has exactly one statement target in the same view. Duplicate
release identities under different record paths are invalid.

Status belongs to the repository's signed targets metadata. Changing status creates later
targets, snapshot and timestamp files; record and envelope bytes remain immutable. The
repository must retain revoked record entries as tombstones with their existing target
pins. `revoked` is terminal for that repository identity and ReleaseId. A newer active or
yanked assertion cannot override a learned revocation. Yank may later be withdrawn by a
new authenticated view. Retrying publication cannot change either status.

| Status | New resolution or update selection | Exact locked restore or continued use |
| --- | --- | --- |
| `active` | Eligible after all authorization checks. | Eligible after all authorization checks. |
| `yanked` | Excluded from candidates eligible for selection or change. | Permitted for the already locked exact identity, including frozen nodes in an update. |
| `revoked` | Rejected. | Rejected once learned, regardless of prior authorization. |

This filtering is an acquisition boundary around the unchanged draft.2 resolver. It does
not introduce a new version-selection algorithm. Omission from newer metadata prevents new
authorization but is not a revocation and does not erase an existing continued-use grant.

### Publication, refresh and historical evidence

Publish verified bundle, record and envelope objects before publishing numbered targets
and snapshot metadata. Retain the exact new timestamp bytes at `metadata/V.timestamp.json`
before atomically replacing `metadata/timestamp.json` as the final commit point. Readers
pin that timestamp's one snapshot and never mix views. There is no second signed index.
The publication contract defines writer serialization and recovery. Publishers allocate
strictly increasing versions per role and never overwrite numbered files, even after key
rotation; this publication rule is separate from the client's TUF recovery rules.

Apply the pinned TUF client workflow, including rollback checks and sequential root
rotation with both old and new root thresholds. Expired bootstrap/intermediate roots may
establish rotation continuity; the final root must be unexpired for fresh authorization.
Persist accepted roots even if later refresh steps fail. Follow TUF's timestamp/snapshot
state reset after their keys rotate, never an ad hoc counter reset or historical rollback.

Capture one trusted UTC time at operation start and use it for all freshness checks.
Expiry at or before that time fails. A clock earlier than the last successful fresh
authorization time cannot establish new freshness; report unavailable trusted time.
Keep that time in durable state. Continued use under `previous-authorization` does not
relabel expired metadata as fresh. Tests inject a fixed clock and isolated state.

Fresh cached metadata must pass the same root, role, expiry, version and link checks as
metadata read from the configured local registry. Equality with an already trusted
timestamp is not a new update; its retained complete view may be used only after checking
all role expirations at this operation's fixed time. Incomplete earlier refresh state is
not a complete authorized view. Cache-only use must not hide a newer durable rollback floor.

Historical lock evidence proves the pinned old view's provenance and exact record/envelope
membership. Verify its pinned bytes, signatures, authenticated links and root continuity
in an isolated historical verifier. Expiry does not erase that historical proof, but it
cannot establish current freshness. Never install historical evidence into the current
TUF datastore or roll it backwards to make a lock pass. A newer complete fresh view may
authorize the same exact record and envelope despite different timestamp, snapshot or
targets digests. Check both the old provenance and new authorization; do not rewrite the
lock. If the configured bootstrap is later than the old evidence, historical verification
uses retained previously authenticated roots or the original root body pinned by the
configured identity and its forward rotation chain. A chain merely ending at a trusted
newer root does not establish trust backwards. Thus a new machine provisioned with root 7
can authenticate supplied older evidence from the fixed identity anchor without having
previously stored root 1. Missing required root bytes or chain members fail evidence
completeness, even when current authorization would otherwise succeed.

## DSSE statement and JSON domains

The sole supported `payloadType` is the exact case-sensitive string
`application/vnd.morphir.library-release.v0.1.0-draft.3+json`. Its decoded payload is
the [release statement](schemas/release-statement.schema.json), encoded with draft.1
canonical metadata JSON, without a BOM or trailing LF. Dependencies are already sorted
as prescribed by the local Library contract. Verify the exact decoded bytes, then parse
those same bytes; never reserialize a payload before signature verification.

Use ordinary Ed25519 from [RFC 8032 section 5.1](https://www.rfc-editor.org/rfc/rfc8032#section-5.1),
with 32-byte raw public keys and 64-byte raw signatures. Do not use Ed25519ph, Ed25519ctx,
or an application prehash. Sign DSSE's standard PAE of the UTF-8 type and payload bytes.
PAE lengths count bytes and use decimal without leading zeros. No custom framing is added.

```text
PAE(type, payload) = "DSSEv1" || SP || decimal(byteLength(type)) || SP || type
                    || SP || decimal(byteLength(payload)) || SP || payload
```

Here `type` is the UTF-8 payload-type bytes, `SP` is byte `0x20`, and `||` concatenates bytes.

The JSON envelope has required string `payload`, string `payloadType`, and array
`signatures`. Each signature object requires string `sig`; string `keyid` is optional.
The plural field follows the upstream [envelope schema](https://github.com/secure-systems-lab/dsse/blob/d3beff7f8616e32cbbb1ec40b20a669c0e85eae6/envelope.proto).
Producers emit padded standard base64 for payload and signatures. Verifiers accept both
standard and URL-safe base64, with or without their correct trailing padding, but reject
mixed alphabets, embedded whitespace, invalid pad bits, and malformed encodings. An absent
key ID equals an empty key ID. It is an unauthenticated lookup hint, never authority.
Unknown envelope and signature-object fields must be ignored, not rejected or signed as
additional payload. Preserve the original complete file bytes for TUF and evidence hashes.

For each authorized raw public key in the chosen rule, count it once if any correctly
decoded signature verifies against that key. An empty signature list cannot meet a positive
threshold. Duplicate signatures, repeated key IDs, and different hints for the same key
do not increase the count. Unknown or misleading key IDs must not prevent trying authorized
keys. A cryptographically invalid extra signature does not defeat an otherwise valid
threshold. Malformed required fields or base64 are envelope decoding errors; a well-decoded
signature of the wrong byte length is invalid and contributes no key. Publisher signatures
are rechecked at every use under current namespace/key policy.

| JSON domain | Parsing and number rules | Unknown fields and Unicode |
| --- | --- | --- |
| Morphir record and decoded statement | Reject duplicate decoded keys, numbers, booleans, null and a BOM; enforce draft.1 depth and exact canonical bytes. Record adds one LF; statement adds none. | Closed schemas; printable ASCII strings and keys only, without Unicode normalization. |
| Local trust policy | Reject duplicate decoded keys and BOM; only the positive integer fields above contain numbers; reject fractions and exponent spellings. | Closed schema; ASCII fields as specified above. |
| TUF metadata | Reject duplicate decoded keys and BOM; use TUF canonical JSON for the complete signed object. No floats; parse integer values exactly, without binary-float rounding. | Preserve unknown fields and include signed unknown fields in canonicalization. TUF Unicode strings are permitted; do not apply the Morphir ASCII restriction or normalize strings. |
| DSSE envelope | Reject duplicate decoded keys and BOM; known fields have the types above. Unknown fields may contain any valid JSON value, including numbers. | Ignore unknown fields semantically. Unicode is permitted in hints and unknown fields; no Unicode normalization. Payload type still requires the exact supported string. |

All JSON is valid UTF-8. Reject ill-formed UTF-8 and unpaired surrogate escapes. Duplicate
member detection compares decoded keys, so `"sig"` and `"\u0073ig"` are duplicates.
The duplicate-member rule is this profile's ambiguity restriction; it does not make DSSE
unknown fields closed. JSON Schema alone cannot detect duplicate keys or canonical bytes.

## Durable local security state

Security state is client-controlled and separate from disposable caches, lock files and
reports. Its private storage format need not be portable. Retain these data durably:

| State | Required contents |
| --- | --- |
| Repository trust | Fixed repository identity, original provisioning pair, current trusted root bytes and version, authenticated root continuity, TUF rollback-protection metadata and key-rotation reset context, last successful fresh-authorization time. |
| Known revocations | Repository identity and exact ReleaseId, authenticated targets version and exact evidence digest, root/key epoch needed to establish its authority, and retained signed evidence bytes. Revocation applies to every digest for that identity. |
| Per-release authorization | Repository identity, exact ReleaseId, logical record and statement names, their exact file digests and bytes, manifest/content digests, IR name and requirements, all verified authorized raw publisher keys, successful fresh authorization time, and retained complete authentication evidence including root continuity. |
| Authorization trust context | Policy version and the repository namespace grant, selected publisher rule, threshold and key set used at creation, plus the effective local identity binding. Retain provenance for audit; aliases and physical directories are not authority. |

Store a per-release authorization only after fresh repository authorization, publisher
threshold verification, record/statement/manifest consistency, and verification of every
declared content byte succeed. The authorization binds one release and its immutable
acquisition, not an entire lock or graph. Successful nodes may retain their grants if
another node fails; graph readiness still requires all nodes and graph checks to pass.

Every replay first checks current repository namespace authority, the currently selected
publisher rule, known revocations and exact bytes. For continued use, require the current
threshold using keys that both verified at grant creation and still verify under the current
rule. Removing one key does not block a grant if enough other retained authorized keys
meet the current threshold. New keys alone cannot extend an old grant. If the surviving
keys are insufficient, fresh authorization is required under the new policy. An unrelated
namespace addition does not invalidate grants: compare effective permissions, not a hash
of the entire policy. Removing repository/namespace authority blocks use immediately.

Root rotation preserves repository identity and existing per-release grants. Retired TUF
role keys do not by themselves revoke previously authorized releases; their historical
signatures are checked in their authenticated historical context. Root rollback, missing
continuity or untrusted replacement cannot be repaired by a cache or old lock. Changing
`continuedUse` to `fresh-metadata` immediately requires fresh authorization for every use.

Learn revocations from a complete, fresh, authenticated package view after validating its
status structure and repository namespace authority. Persist every such revocation before
checking affected package availability, publisher signatures or graph readiness. A later
failure cannot undo that observation. Refresh failure before authentication establishes no
new status. Omission, cache cleanup, removing then readding a repository policy entry,
root rotation, and a later active assertion cannot clear durable known revocations.
This profile has no revocation-reset operation.

Serialize security-state changes per repository. Atomically persist each accepted root
and its required rollback-state transition, each learned revocation batch, and each completed
grant. Flush the transaction and its commit marker before reporting success or using a new
grant. Recovery exposes either a complete prior state or a complete committed successor,
never a partially written grant or a root with stale reset context. Concurrent refreshes
must recheck their predecessor state before commit. A state-write failure blocks the
operation; it cannot fall back to a cached success report. Once a revocation commit succeeds,
later failures must retain it.

Before authenticating a complete candidate package view and accepting its status, retain
its exact evidence bytes and durably record an in-flight update marker. The marker binds
repository identity, predecessor security-state revision and verification context, the
operation's fixed trusted clock, and the evidence digests. Do this under the repository's
security-state serialization. While a marker is unresolved, other operations cannot
change its predecessor or reuse that repository's previous grants. If marker persistence
fails, do not authenticate or accept the candidate view. This ordering prevents a later
failed revocation write from letting restart silently reuse an older grant.

Recovery revalidates the retained candidate using its recorded predecessor context and
clock, then atomically commits all authenticated revocations and required trust transitions
and clears the marker. The recorded clock is used only to preserve security observations
that the interrupted operation could have learned. It never establishes present freshness
or grants new per-release authorization after expiry. Preserve already committed root
updates and their TUF reset context; replaying marker context must not install an older
root or lower a durable rollback floor. A candidate that fails authentication may clear
its marker without learning statuses. If the marker or its evidence cannot be recovered,
or reconciliation cannot be durably committed, block grant reuse pending explicit recovery.
Do not discard the marker and fall back to the complete prior grant state. This rule does
not provide recovery from total protected-state loss, which follows the rules below.

Keep authorization evidence with security state or in protected retained objects referenced
by it; cache eviction must not delete the only copy. Missing or corrupt security state is
not an authorization grant. If loss or corruption is detected, fail closed and require
explicit reprovisioning; do not silently reconstruct rollback floors from a copied cache.
An explicitly initialized new client has no prior grants or known revocation history and
requires first-restore authorization. Loss of all state also loses knowledge of unseen or
formerly retained revocations; this profile provides no portable recovery from total loss.

Clients must not import copied security state as continued-use grants. Explicit initialization
or reprovisioning follows first-restore authorization rules. Protection against an administrator
replacing or cloning protected state is outside this profile; no machine binding or clone
detection is specified.

## First restore and continued use

The table assumes valid lock provenance, exact matching local bytes, current namespace and
publisher authority, and a complete graph. Any failed prerequisite still fails the operation.
Here "fresh" means the complete TUF view passes current-time checks against durable trust
state. It can be locally cached; it need not be newly fetched or use an internet connection.

| Situation | `previous-authorization` | `fresh-metadata` |
| --- | --- | --- |
| First restore; fresh local registry or cached view authenticates the exact record and envelope | Authorize after full verification; persist grant. | Same. |
| First restore; only expired historical evidence | Reject; historical pins do not grant authority. | Reject. |
| Machine A has a durable grant; metadata has since expired | Permit exact local use after current-policy, signature and byte rechecks. | Reject until a fresh view authorizes the exact release. |
| Machine B copies A's lock, bytes and ordinary metadata cache, but no security-state grant | First-restore rules apply; only a complete fresh view can authorize it. | Same. |
| Old lock plus newer fresh view authorizing the same exact record and envelope | Permit; retain historical pins and lock bytes unchanged. | Same. |
| Old lock view lies below current TUF rollback state, with no applicable grant or newer authorizing view | Reject; never install old state to authenticate it. | Reject. |
| A durable grant exists, but latest metadata omits the release | Continued use remains possible; omission is not revocation. | Reject new authorization without exact target membership. |
| Known revocation or withdrawn effective namespace/key authority | Reject. | Reject. |
| Cache removed, but protected security state and exact bytes survive | Grant remains usable subject to rechecks. | Requires a complete fresh locally available view. |
| Security state lost or corrupt | No continued-use authority; follow the state-loss rules above. | Same. |
| Missing or altered package/evidence bytes | Reject availability or integrity failure. | Same. |

Resolve and update always require fresh authorization for their inputs and never use the
continued-use exception to obtain new selections. Exact locked replay performs no selection,
implicit refresh, source fallback or version substitution. If policy requires freshness that
the caller has not made available, fail and report the requirement. Machine A can continue
after expiry under the permissive policy; machine B cannot derive that authority from A's
copied lock. Both enforce any revocation they have learned. Neither promises knowledge of
revocations it has never received.
