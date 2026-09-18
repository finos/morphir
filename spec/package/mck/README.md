# MCK package suite, draft cases

This directory holds candidate cases for the package suite of the [Morphir Compatibility Kit](../../mck/README.md).
The [Library contract](../library-contract.md) specifies the restricted `0.1.0-draft.1`
profile described here. Stable case IDs identify expected behavior within this draft.
Record the repository commit when comparing runs; no kit-release or package compatibility
claim follows merely from a local pass.

Run `mise run package:check` for the shared-core suite, in-process and over an executable adapter.
Run `mise run package:check:rust` for the same suite against the independent Rust implementation.
Run `mise run package:schema-check` separately for generic schema and example structure validation.

`resolution-cases.json` is the experimental `0.1.0-draft.2` resolution corpus index.
Its indexed fixtures cover all 13 families listed in the [resolution contract](../resolution-contract.md).
Cases use globally unique stable IDs, raw-string operation input, and fixed structured expected
results. Every digest in these fixtures is synthetic metadata, not a verified payload hash.
The schema task checks the index and case/result structure. Executable resolution
uses the shared TypeScript MCK core and the independent Rust implementation through an adapter.
The new `package:resolution-check` and `package:resolution-check:rust` tasks select draft.2
explicitly. Parent PR #820 landed CI against merged upstream implementation commits.
The existing draft.1 package suite remains available unchanged.

`schema-cases.json` declares each case's schema, base fixture, expected verdict, and
optional replacement or removal using a property-path array. Acceptance here means
structural schema acceptance only. Cross-document semantic checks must be separate operations
in the shared package suite. In particular, a valid schema does not
prove a public specification matches its selected implementation.

`digest-vectors.json` contains raw JSON inputs and fixed canonical text and digest
expectations, plus rejected documents and exact-byte cases expressed as hexadecimal.
It includes the worked manifests. These expected values are committed data, not computed
at test runtime by the implementation under test. The shared runner must compare implementation
results with these fixed expectations, not derive expectations from the same implementation.

`library-cases.json` checks the closed two-Library example against fixed accept/reject verdicts.
Mutations address `lock`, `eligibility`, or `consumer` through property-path arrays.
`payloadSuffix` appends hex bytes to a named fixture; `lockText` supplies raw lock JSON for syntax cases.
The operation verifies exact declared bytes, aggregate hashes, roots and binding targets, release
identity and stable-version intervals, IR package/dependency names, and public export targets.
It does not check public-specification compatibility, resolve versions, establish trust, or install files.

## Shared core integration

The [accepted ownership decision](../../../kb/bundles/morphir/morphir-package-system/decisions/0001-package-compatibility-uses-the-shared-mck-core.md)
places case loading, execution, comparison, capabilities, provenance, reporting, and adapter
infrastructure in finos/morphir-typescript. This directory supplies cases, not another runner.
Reference package functionality is a test target, separate from expected results.

The core exposes `PackageTestee`, `runPackageKit`, and `processPackageTestee`. Its `mck package run`
command requires `--kit`; no package corpus is embedded yet. `mck-adapter-typescript --suite package`
selects the experimental `0.1.0-draft.1` package protocol. The package protocol and report schemas
ship with `@finos/morphir-mck`. IR protocol/report version 1 and default IR commands stay unchanged.

Draft.2 adds `ResolutionTestee`, `runResolutionKit`, and `processResolutionTestee` through
the same execution, comparison, and reporting infrastructure. Select it with
`mck package run --contract 0.1.0-draft.2 --kit spec/package/mck` and
`mck-adapter-typescript --suite package --contract 0.1.0-draft.2`, or the corresponding
Rust adapter flags. Its `package-resolution-protocol.schema.json` and
`package-resolution-report.schema.json` ship with the MCK package. Omitting `--contract`
from a package invocation retains draft.1.

The Rust adapter exposes the same package contract through `mck-adapter-rust --suite package`.
Package behavior lives in the separate `morphir-package` library, not the adapter or the extension
distribution library. The parent wrapper selects the suite, optional package contract, and platform-specific
binary name. It forwards the same explicit contract to driver and adapter. The shared driver still
loads cases, compares fixed expectations and reports results.

CI writes `package-typescript.json`, `package-typescript-adapter.json`, and `package-rust.json`
under `.dev/out/mck/`. The two TypeScript transports count as one implementation; Rust supplies
the second implementation. Passing this restricted corpus does not complete all Stage 0 work.

Package reports record suite, contract and driver versions, testee identity and capabilities,
and a content hash of all consumed corpus, schema and fixture bytes. Record both repository
commits alongside reports when comparing development checkouts. The existing IR embedded-kit lock
does not identify this package corpus.

The shared package runner must reject unknown case targets, duplicate IDs, empty corpora,
and malformed expectations. Tooling or schema infrastructure failures must be kit errors,
not successful rejection cases. Required-case failures, kit errors, and skips prevent a
compatibility claim. Independent implementations under test use the same runner through
its interfaces or adapters; duplicating the runner is not an independence requirement.

## Landed resolution evidence

The 2026-09-17 UTC development run passed all 78 draft.2 cases on each transport, with zero
failures, kit errors, or skips. After incorporating current upstream changes, the shared driver
and TypeScript testee versions are `0.2.0`; Rust remains `0.2.0`.

| Report under `.dev/out/mck/` | Testee | Passing cases |
| --- | --- | --- |
| `package-resolution-typescript.json` | morphir-typescript `0.2.0`, in-process | 78 |
| `package-resolution-typescript-adapter.json` | morphir-typescript `0.2.0`, executable adapter | 78 |
| `package-resolution-rust.json` | morphir-rust `0.2.0`, executable adapter | 78 |

All three reports identify corpus hash
`sha256-8dfed22a389bd08e945b35213586b0709f2cf11f5426199bcec746007443b08b`.
The fixed cases cover validation phases, replay, backtracking, scoped updates, graph ordering,
and diagnostic witness ranking. They do not verify acquisition, payloads, trust, or API compatibility.

Parent [PR #820](https://github.com/finos/morphir/pull/820) merged as
`d67cf0df7bce30cd46328366d155919ff4874e69` on 2026-09-17 UTC. It includes the YAML
integration in #819 and pins these merged implementation commits:

- TypeScript `100b7aa02359f57cbf0cd3db7cb2fbb3c1bb3b45`, [PR #18](https://github.com/finos/morphir-typescript/pull/18).
- Rust `1c522051555eaefb076697cc3f0c7159670aeaa7`, [PR #154](https://github.com/finos/morphir-rust/pull/154).

These commits include the upstream IR support-table changes; Rust also includes the YAML profile
and enforces its 512-release execution bound during replay and update baseline validation.
[Integration CI run 35179127974](https://github.com/finos/morphir/actions/runs/35179127974)
passed against final PR head `5202086716e584ef2164458f93a831672651bf3c`, whose tree matches
the squash commit. Its dedicated package job checks both contracts against both implementations
and retains reports. The completed review posted no findings. Local reports remain ignored
build outputs, not committed evidence artifacts. This is bounded draft-contract evidence,
not a stable package-system compatibility release.

The separate draft.1 corpus also passed all 80 cases on each transport with no failures,
kit errors, or skips. Its hash remains
`sha256-72b6593c99af919076e59208b833771394d659838e28ee4c23554ee7f5590e23`.
Neither result completes Stage 0 or produces an installable `morphir.lock`.

## Candidate local-registry contract

The accepted [filesystem assurance design](../restore-filesystem-assurance.md) targets
portable restore on Linux, macOS and Windows before hardened providers. The existing
54 draft.3 cases retain their original, hardened requirements and fixed expectations.
Portable execution requires its own explicitly versioned execution/report profile,
declared complete required-case set and provider evidence in the shared MCK core.
Do not relabel this corpus, skip hardened cases to produce a portable pass, or add
mode fields to closed messages without versioned schema support. Existing pending assets
remain pending. Definition validation is not evidence for either filesystem mode.

`restore-assurance-preflight-vectors.json` supplies fixed expectations for the separate
internal `restore-filesystem-assurance` profile, version `0.1.0-draft.1`. Its six synthetic
cases check explicit selection, exact-mode qualification, refusal of unavailable modes
and preflight receipts. The shared TypeScript MCK checks these fixtures through its
`local-registry-assurance-parent-integration.ts` support entry point. They are not additions
to the 54-case corpus and do not define a complete portable suite. The synthetic evidence
references qualify no provider or platform. See [internal host preflight](../restore-filesystem-assurance.md#internal-host-preflight)
for the request and receipt boundary; no public portable adapter or runtime restore is
implied by these checks.

The [draft.3 local Library contract](../local-library-contract.md) defines candidate full-lock
and immutable registry-record shapes. The [unsigned example](fixtures/local-registry/unsigned/README.md)
is review material, not a new passing corpus. Its lock and record examples deliberately use
nonconforming `UNSIGNED:` values where signed evidence is unavailable.
The separate [signed example](fixtures/local-registry/assets/signed/README.md) supplies
complete bytes and verification instructions. User signed-fixture review was approved
on 2026-09-17; full draft.3 runtime execution remains unimplemented.

The existing driver does not execute draft.3. Its schema, trust and filesystem cases require
shared TypeScript MCK support and independent Rust operations before interoperability can be claimed.
Do not include these unsigned shapes in draft.1 or draft.2 case counts or corpus provenance.

### Publisher-signature integration

Run `mise run package:publisher-check` from the parent repository root. It invokes the
shared TypeScript MCK's `local-registry-publisher-parent-integration.ts --source .`
support entrypoint against the two fixed signed statements. The check verifies all
authorized signing keys, including both keys when the policy threshold is one,
preserves exact envelope and payload bytes, and checks that evidence binds the requested
release even when the signed payload names another release. Existing signed assets and
their historical reproduction instructions remain unchanged.

This is a publisher-signature evidence check. It does not establish TUF or repository
authentication, graph readiness, durable authorization grants, filesystem guarantees,
restore compatibility or a full 54-case draft.3 corpus pass. Execution stays in the
shared MCK; this parent task adds no verifier, fixtures or schemas. The shared MCK
requires Node.js 24 or later. The separate Morphir IR package retains Node.js 20 support.

### Definition status and admission

[`local-registry-cases.json`](local-registry-cases.json) indexes 54 required candidate
definitions in seven families. The [case schema](../schemas/local-registry-case.schema.json)
defines the index, case files, operation results, witnesses, tree manifests and normalized
observations. The draft.3 case wire contract was approved on 2026-09-17. These definitions are not an executable
corpus or an implementation claim. The resource maxima remain candidate profile choices.

Every asset is explicitly `pending` with a purpose, or `bound` with a confined path,
decimal byte length and actual SHA-256. This revision has 121 pending assets and six bound
assets for the [signed two-Library review fixture](fixtures/local-registry/assets/signed/README.md)
and its fixed first-restore observations. No local-registry executor or compatibility pass
is claimed. Four rejection probes already contain their exact raw input bytes as lowercase
hexadecimal. Success graphs use the existing two-Library fixture's real manifest/content
digests. Pending signing inputs never use plausible placeholder hashes, unsigned examples,
or a digest of a pretty-printed statement as a signed envelope digest.

A definition validator can report definition validity and pending counts. It must not
produce a compatibility report, pass count or executable kit hash. Executable admission
requires every transitively referenced asset, complete expected result and final snapshot
to be bound, length/hash checked and semantically validated before calling a testee.
Unresolved pending entries, missing bound files, unknown references and malformed
expectations are nonzero kit errors. An intentionally absent file inside a complete,
successfully bound negative tree is a test input; a missing fixture asset is a kit error.

An `asset` expectation's pointer assertions fix already-known fields while its complete
expected bytes await signing-dependent hashes. They are review constraints, never partial
runtime matching rules. Before execution, validate the complete bound asset against
`$defs/Result` or `$defs/Observations` and require every pointer assertion to match it.
Compare the whole resulting operation result and normalized snapshot with those fixed
expected values. Do not compute expectations from the reference implementation, testee,
or actual operation output. `terminated` instead expects process termination at exactly
its named checkpoint and no portable operation result.

### Raw inputs, setup and operation boundary

`Bytes` is either decoded lowercase hex or an asset's exact bytes. Pass those bytes through
unchanged, including whitespace, duplicate spellings, final newlines, BOMs and invalid UTF-8.
Do not parse and reserialize a caller lock, policy, record, DSSE envelope or TUF document
before the testee sees it. Parse cases are rejection-only frontend probes of their named
document domain, before I/O or authentication. They must return the fixed failure, never
`graph-ready` or a parser-specific success mistaken for package readiness. Their current
four cases all target lock decoding. Domain-specific parse failures retain the enclosing
operation phase when used inside a scenario.

Each scenario creates fresh isolated roots for registry, ordinary cache, staging,
destination, client security and shared repository publisher state. Logical owners and
root kinds identify them; absolute temporary paths never enter results. Configuration
assets bind aliases to explicit registry roots, original repository identities and
independently provisioned bootstrap bytes. The policy is an exact separate caller input.
Explicit initialization installs bootstrap trust but starts with no grants, known
revocations, successful fresh-authorization time or accepted current metadata floors.
Publisher initialization inspects the complete initial view, initializes its reservation
floors from existing numbered files/committed versions, and creates shared writer state
once per registry. It never overwrites existing or corrupt publisher state on restart.

Tree assets validate against `$defs/Tree`. They enumerate the complete logical tree;
implicit files, directory contents, clocks and shell commands are forbidden. Declare parent
directories, unique paths and exact file bytes. Hardlinks refer to another fixed regular
file in that tree; symlink targets are root-relative fixture locations. A `fifo` requires
host support. Setup must not follow fixture symlinks or escape its isolated roots. A host
that cannot represent the prescribed setup, including both case-colliding names, reports
required unsupported. It cannot silently weaken the fixture or pass it.

Scenarios use only the five operation names in the contract. Every operation has an
explicit actor, policy, fixed UTC second and caller resource limits. Empty limits mean
the candidate profile maxima, not implementation defaults. Resolve/update receive an
explicit repository set; update targets reuse draft.2 unchanged. `authorizationView` on
replay is a test invocation input, not a lock field. `supplied` gives the exact complete
local metadata view to verify, without fetching or implicit refresh. `none` supplies no
new view: only existing ordinary cached metadata and retained protected evidence/grants
are available. First restore cannot manufacture a grant from these bytes. Withholding
the registry also removes every physical-registry read route, including one suggested
by a copied cache, while explicitly retained evidence remains available.

Publication takes fixed bundle, record, envelope, predecessor and complete proposed
successor metadata assets. The proposal contains the exact caller-signed targets,
snapshot and timestamp bytes and versions. No signing keys are given to the testee.
The real operation validates, reserves, installs and commits those bytes using the
contract's ordering. Supplied successor files are not preinstalled publication results.
Both concurrent writers share one registry and publisher state. Their client security
roots remain separate. Proposal failures and idempotent retries follow the contract;
neither can reserve versions or alter status.

### Controller and observations

Actions execute once in listed order. `start` launches an operation and installs its
declared barriers before execution. `await` waits for that exact operation, boundary,
step and logical subject; `release` advances it. A barrier must be declared once, reached
once and released or terminated once. `join` requires an operation result. A termination
has no join/result; `restart-client` launches a fresh process with the same surviving
roots and no inherited memory. Publisher restarts reopen the shared publisher state.
An unresolved barrier, timeout, unexpected process exit or invalid schedule is a kit
infrastructure error, never an expected domain rejection.

`inject-fault` applies one normalized I/O error to the held `before` step. It cannot fail
an already completed `after` step. `terminate` is process death, not simulated power loss.
The final-directory-flush failure case observes the complete visible successor after
process restart without claiming power-loss durability. `select-view` switches the
complete fixture view exposed at the registry root while preserving independently held
operation handles and all protected client state. It neither accepts that view nor
refreshes trust. `withhold-registry`, `evict-ordinary-cache`, explicit tree changes and
client restart are the remaining controller operations. No sleeps, polling races,
callbacks, package hooks, arbitrary commands or executable fixture scripts are allowed.

Checkpoint subjects use logical object names. A per-bundle security grant commit uses
that bundle's source directory as its object subject; repository-wide root or revocation
commits use a repository subject. All eight provider-bundle failure cases hold the provider
before inventory until the consumer reaches `after bundle-ready`. That aggregate checkpoint
means both verified cache promotion and required grant durability completed; it imposes
no order between them. It is not graph readiness. This schedule fixes the consumer's
side effects before the provider fails, including the source-mutation case. The revocation
write-failure case holds the durable marker, injects a one-shot revocation commit failure,
then restarts and verifies that reconciliation blocks reuse of the old grant.

The final `observe` context supplies one fixed clock and an explicit policy for every
actor. Observation does not refresh, create grants or change state. Normalized security
observations report required root/floor/time state, known revocations, unresolved markers
and continued-use grants eligible under that context. They do not require a particular
database layout or retention of unusable revoked grant records. Lost/corrupt state has
no reportable grant. Grant observations retain the public acquisition identity, creation
time and authorized verifying keys, not private filenames. Subsequent explicit replay
operations supply the behavioral evidence for eligibility. Protected state recovery
uses the interrupted operation's recorded clock only as specified in the trust profile.

Sort actors and registry aliases in ASCII order. Sort grants and revocations by registry,
PackagePath and numeric version; sort keys in ASCII order. Sort logical filesystem roots
by owner then kind and their entries by path. Filesystem observations contain only registry,
cache and destination roots. Registry entries describe the complete public registry tree,
including retained and unreferenced immutable objects. Cache entries describe only completed
verified bundle promotions, mapped to logical `bundles/<contentHex>/` paths and their exact
manifest/content inventory, regardless of the implementation's physical cache layout.
Include the logical parent directories. Optional cached metadata, private cache indexes,
security/publisher filenames and partial staging trees are excluded. Publisher reservation
maxima and normalized security fields capture their required durable effects. Destination
entries describe explicitly requested output trees; these cases request no consumer-writable
copy, so their destination inventories are empty. This is a fixed complete projection of
named outputs, not a partial-match allowance. `readyGraphs` follows operation declaration
order, and `lockBytes` follows asset ID order. Compare input lock hashes unchanged on both
success and failure. Every expected snapshot includes complete named registry/cache/
destination inventories; an assertion is not permission to omit other observations.

### Semantic validation and corpus identity

JSON Schema checks structure. Admission additionally rejects duplicate case/asset/actor/
operation IDs, duplicate fixture or logical asset paths, wrong asset types, unresolved
references, duplicate or contradictory assertions, invalid calendar timestamps,
inconsistent graph/verified output, unsupported operation-result combinations and invalid
checkpoint schedules. Validate exact code/category/witness-tag and rule relationships
from the contract, canonical witness ordering, revision/role-version rules and resource
`maximum + 1` observations. For example, a `release-revoked` authority witness must use
`rule: revoked`; a `resolver` witness retains the unchanged draft.2 diagnostic category.
An expected parser failure or malformed negative package input is allowed. A malformed
case, expected result, proposal fixture declaration or asset binding is a kit error.

Hash all consumed raw bytes: index, every case file, this definition README, transitive
local schemas, bound asset manifests, configuration and policy, bootstrap/root chains,
signed TUF files, DSSE envelopes and payloads, records, locks, binary content and complete
expected snapshots. Resolve schema IDs only through the registered local files. Case and
asset paths are relative to this MCK directory and confined to the declared fixture
directories; reject traversal, symlink escapes, duplicate logical paths and framing
characters. Use repository-relative slash-separated logical names in the hash map.

Reuse the shared core's `packages/mck/src/kit/hash.ts` exactly: JavaScript string-sort
logical paths, SHA-256 each file's exact bytes, then SHA-256 the concatenated UTF-8 records
and prefix the lowercase final hex with `sha256-`. The current shared implementation's
record is `path + NUL + lowercaseHex(SHA256(bytes)) + LF`, where NUL is byte `00` and
LF is byte `0a`. Reject backslashes, NUL, CR and LF in logical paths. Do not substitute a different
framing algorithm and claim an existing kit hash. A hash while assets remain pending
identifies candidate definitions only, never an executable compatibility corpus.

The future driver extends the shared package `run.ts` capability, execution, comparison
and reporting lifecycle. Every case here is required. Missing required testee or
controller support, skipped cases, failures and kit errors prevent a compatibility claim
and cause nonzero overall status. An expected `unsupported-source` rejection of an invalid
input can pass; inability to execute a required operation or fault control cannot. Never
send expected results, case IDs, acceptance descriptions or pass/fail labels to a testee.

Run the existing `mise run package:schema-check`, then separately run `jsonschema
metaschema` and local-reference `compile` on the candidate case schema and `jsonschema
validate` on this index and every indexed family. The existing task does not list these
new schemas. These checks validate definitions, not signatures, runtime scenarios or
compatibility. Wire approval permits signed-asset tooling in the shared TypeScript MCK.
Signed-fixture review was approved on 2026-09-17. Shared execution support and independent
adapters may now proceed, with their own tests and reviews.
