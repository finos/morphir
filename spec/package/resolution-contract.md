# Experimental Library resolution contract

This normative contract identifies the bounded `flat-library` resolution operation in
experimental MCK package contract `0.1.0-draft.2`. The [Library integrity contract](library-contract.md)
remains `0.1.0-draft.1`, including its content-digest domain separator and every existing
operation. A transport version change must not change Library content identity. IR protocol
and report version 1 and the default IR adapter invocation remain unchanged.

The `resolve-library` operation carries `input` as a raw JSON string. Its result
is the structured value defined below. A malformed protocol envelope is an adapter/protocol
failure, never an expected resolution rejection. Missing adapter support is an MCK capability
failure. The [MCK suite](mck/README.md) records executable checks and their landing status.
Schemas alone do not establish resolution compatibility.

## Scope and identities

Resolution is pure selection over finite immutable metadata. Acquisition, registries, payload
reading, publication, installation, and public-specification/API compatibility are outside
this operation. Success is a resolution metadata projection, not an installable `morphir.lock`
and not evidence that payload bytes or embedded public specifications were verified.

Keep authority-bearing PackagePath, release version, and IR PackageName distinct. Reuse the
existing manifest's PackagePath, StableVersion, IRPath, and Digest definitions. Schema references
to those definitions resolve against the locally registered draft.1 manifest schema; no network
fetch is required. Stable version components are unbounded decimal integers in strings. Compare
major, minor, patch numerically without floating-point or fixed-width truncation. Prereleases,
build metadata, and leading zeroes are outside this profile. An interval has inclusive minimum,
exclusive maximum, and minimum strictly less than maximum.

Core IR definitions, dependency names, and FQNames never gain release versions. For example,
`example.com/finance/eligibility@1.3.0` binds the unchanged IR name `example/eligibility`;
`example/eligibility:decision#default-decision` stays unchanged. Diagnostic occurrence paths
below are evidence handles, not advanced IR reference encoding.

## Wire values

All objects reject unknown fields. Arrays have no semantic input ordering. The
[input schema](schemas/resolution-input.schema.json) and [result schema](schemas/resolution-result.schema.json)
define the structural grammar; this text adds graph, uniqueness, comparison, and validation rules.

| Value | Required fields |
| --- | --- |
| ReleaseId | `packagePath`, `version` |
| Requirement | `irPackageName`, `packagePath`, `versionRange: {minimumInclusive, maximumExclusive}` |
| ReleaseRecord | `release: ReleaseId`, `irPackageName`, `manifestDigest`, `contentDigest`, `dependencies: Requirement[]` |
| Binding | `irPackageName`, `target: ReleaseId` |
| LockedNode | `release`, `irPackageName`, `manifestDigest`, `contentDigest`, `bindings: Binding[]` |
| LockedGraph | `root: ReleaseId`, `nodes: LockedNode[]` |
| Catalog | `packagePath`, `releases: ReleaseRecord[]` |
| UpdateTarget | `{kind: "eligible", packagePath}` or `{kind: "exact", packagePath, version}` |

Every input contains `formatVersion: "0.1.0-draft.2"`, `capability: "flat-library"`,
`root: ReleaseRecord`, and `mode`. The root release is fixed in all modes.

| Mode | Additional required fields | Behavior |
| --- | --- | --- |
| `initial` | `catalogs: Catalog[]` | Select a complete graph without a prior lock. |
| `update` | `catalogs`, `lock: LockedGraph`, nonempty `targets: UpdateTarget[]` | Validate the old graph, then select within the update boundary. |
| `replay` | `releases: ReleaseRecord[]`, `lock: LockedGraph` | Validate the supplied graph and preserve its exact releases and bindings; never select replacements. |

The separate `root` record supplies root metadata; catalogs and replay releases supply other
releases. Duplicate exact identities, including a second copy of the root record, are invalid
even when records are equal. Catalog paths, target paths, requirement IR names within a consumer,
node identities, node PackagePaths, and binding IR names within a node must be unique. Each catalog
record must have the containing PackagePath. One immutable exact identity has one metadata record.

## Input completeness and validation

Initial and update catalogs declare the complete candidate universe for every PackagePath
reachable by following dependencies of every candidate, starting at the root. This includes
unselected and infeasible candidates. A present empty catalog declares zero releases. An absent
catalog is incomplete input. Unreachable extra catalogs are permitted but do not enter unsatisfiable
evidence. Update catalogs must also supply every old locked release and the metadata needed to
validate its old requirements. Missing old or replay selected metadata is an incomplete `release`,
not proof that a lock is invalid. Root metadata comes from `root`, without requiring a root catalog.
Completeness is a closed-world input assertion, not proof that a registry disclosed every release.

The separate root record is also the known candidate for its exact identity. An omitted catalog
for the root PackagePath declares no additional releases for that path. If a dependency reaches
the root PackagePath, traverse every release in any supplied root-path catalog for completeness,
including infeasible candidates. Such a catalog is not reachable merely because its path matches
the starting root. In abstract coexistence witnesses, a descendant may use another release at
that PackagePath while occurrence `[]` keeps the fixed root. Repeating the exact root release
on an ancestor path remains a forbidden cycle.

Validation runs the following phases in order. Stop after the first phase producing a diagnostic;
accumulate all independent violations or missing items within that phase. Never combine categories
from different phases. Skip lock phases for initial mode. This order also applies before replay.
The raw document must not begin with a byte order mark, U+FEFF. Report it as `malformed-json`
at the empty pointer, consistently with the package document boundary. This does not change
the separate IR parser's accepted inputs.
Decoded JSON strings and member names must contain Unicode scalar values, never unpaired
surrogates. An unpaired surrogate anywhere in the document is a phase-1 `malformed-json`
at the empty pointer, including within a later duplicate member. Valid surrogate pairs are
accepted. Do not normalize Unicode text.

| Phase | Checks and diagnostic |
| --- | --- |
| 1. JSON text | Syntax failure produces only `invalid-input` / `malformed-json` at `""`. If syntax is valid, collect duplicate decoded keys as `invalid-input` / `duplicate-key`; do not check shape. |
| 2. Outer shape | Validate required mode fields, types, literals, names, versions, digests, and unknown fields. Only recognized `update` and `replay` modes defer `lock` presence and content to phase 4. In `initial` mode, `lock` is an unknown field at `/lock`. Report `invalid-input`. |
| 3. Outer identities | Check catalog, release, requirement and target uniqueness, catalog/release path agreement, and nonempty intervals. Report `invalid-input`. |
| 4. Lock shape | Validate lock presence and structural grammar, including names, versions, and digests. Report `invalid-lock`. An absent lock reports `/lock` / `missing-field`. |
| 5. Lock identities | Check duplicate nodes, node PackagePaths, and consumer binding IR names; check flat IR-name uniqueness. Report `invalid-lock`. |
| 6. Lock topology | Check root identity/presence, dangling bindings, reachability, and cycles using the lock alone. Report `invalid-lock`. |
| 7. Selected metadata | Collect absent records for all locked identities except the separately supplied root. Report `incomplete-input` with `release` items. |
| 8. Lock metadata | Compare every locked node and binding with its original immutable metadata and requirements. Report `invalid-lock`. |
| 9. Target membership | Reject root targets and target paths absent from the old lock at their `packagePath` with `invalid-input` / `identity-mismatch`. |
| 10. Candidate completeness | For initial/update, collect absent catalogs reachable through the full candidate universe. Report `incomplete-input` with `catalog` items. |

Outer errors therefore precede lock errors. Lock topology faults precede missing selected metadata;
missing selected metadata precedes metadata-dependent lock faults. Exact target constraints apply
only after old-lock validation. The phase order deliberately avoids using absent metadata to infer
digest or requirement faults. Replay returns after phase 8; phases 9 and 10 do not apply to replay.

Within shape validation, a wrong JSON type produces `invalid-type` at the value and suppresses
checks below that value. A missing property produces `missing-field` at its would-be pointer.
An unknown property produces `unknown-field` at that property and suppresses checks of its value.
A correctly typed but unsupported literal, including `formatVersion`, `capability`, `mode`, or
target `kind`, produces `invalid-value`. An empty required nonempty array also uses `invalid-value`.
For an absent, wrong-type, or unknown discriminator, validate common fields but suppress
variant-specific checks, including unknown-field checks for fields belonging to any variant.
Strings with invalid name, version, or digest grammar use the corresponding specialized rule.

Within identity validation, keep the first identity in input traversal order, with `root` before
catalogs or replay releases, and arrays in index order. Report a later duplicate at its identity
field and suppress all semantic checks beneath that later entry, including nested duplicates,
intervals, and identity mismatches. Shape checks already happened and are not suppressed by
semantic duplicates. A duplicate catalog thus reports only its later `packagePath`, not repeated
release identities beneath it. Exact node duplication reports its `release`; a second different
release for the same node PackagePath reports its `release/packagePath`. A later node reusing an
IR name for a different release reports `unsupported-flat-binding` at its `irPackageName`.

JSON Pointers use RFC 6901 escaping and original input array indices. Duplicate-key pointers use
decoded keys, so `"a/b~c"` and `"a\\u002fb~c"` collide at `/a~1b~0c`. Sort violations by pointer
in Unicode scalar-value order, equivalent to lexicographic UTF-8 byte order, then ASCII rule;
shorter prefixes sort first. This agrees with ASCII order for ASCII pointers but also defines
the order of non-ASCII unknown fields and duplicate keys. Remove duplicate pointer/rule pairs.
During topology validation,
root disagreement reports `identity-mismatch` at `/lock/root` and suppresses root-presence and
reachability checks; a missing root node reports `missing-root` there and suppresses reachability.
Dangling bindings report at their `target` and are excluded from graph traversal. Unreachable nodes
report at their `release`. Report `cycle` at every binding `target` on a directed cycle, including
self-loops. Reachability and cycle checks use all remaining valid edges.

During lock-metadata validation, node IR-name mismatch reports `identity-mismatch` at
`irPackageName`, and digest mismatches report at the relevant digest fields. A missing required
binding reports `binding-mismatch` at the consumer's `bindings`; an undeclared binding reports
there at the binding's `irPackageName`. A binding whose target PackagePath or IR name disagrees
with its requirement reports `binding-mismatch` at `target` and suppresses interval checking for
that binding. Otherwise an out-of-range target reports `requirement-mismatch` at `target`.
Node metadata checks and distinct bindings are independent and accumulate within phase 8.
Permutation invariance applies to selections and graph-failure evidence on structurally valid
inputs. Validation pointers identify original input positions and may change when invalid array
entries move; their spelling is not a semantic graph identity.

Validate old locks against the original release requirements before applying any exact update
constraints. The lock root must equal the supplied fixed root and have exactly one matching root
node. Every binding
must reference an existing node, match exactly one declared requirement's IR name and PackagePath,
and satisfy its interval. Node IR names and digests must match metadata. Nodes must be reachable
from root, and the graph must be acyclic. Flat graphs select one release per PackagePath and one
unambiguous target release per IR PackageName across the closure. Replay emits the same graph in
normalized presentation even if newer metadata is supplied. Invalid locks never trigger selection.

Violation rules are `malformed-json`, `duplicate-key`, `unknown-field`, `missing-field`,
`invalid-type`, `invalid-value`,
`invalid-name`, `invalid-version`, `invalid-interval`, `invalid-digest`, `duplicate-identity`,
`identity-mismatch`, `missing-root`, `dangling-binding`, `binding-mismatch`, `requirement-mismatch`,
`digest-mismatch`, `unreachable-node`, `cycle`, and `unsupported-flat-binding`.
For duplicates, identify the later entry's identity field; for catalog mismatch identify the
contained release's `packagePath`; for invalid intervals identify `versionRange`; for metadata
digest disagreement identify the lock node digest field. Root or absent-target requests use
`identity-mismatch` at that target's `packagePath`. These are domain diagnostics, separate from
envelope validation and resource failures.

## Supported selection and updates

A valid complete graph has a fixed root, only reachable nodes, no cycles, one release per
PackagePath, and one unambiguous release per IR PackageName. Each consumer has exactly one
binding for each requirement. Every consumer's interval and identity association must hold,
including consumers outside the update closure. SemVer eligibility does not prove type compatibility.
Search must backtrack over complete graphs and establish that no better valid graph exists.
A resource budget, internal failure, or interrupted search is an execution error, never unsatisfiability.

Update targets must be nonempty, unique, existing locked PackagePaths other than root. Every
target must remain reachable. Exact targets intersect consumer requirements and cannot be relaxed.
The permitted existing packages are the targets and their transitive dependency closure in the
old lock. Existing packages outside that closure retain exact releases if reachable. Their bindings
may change to satisfy updated shared dependencies. New PackagePaths may be added, but a new edge
to an existing out-of-scope path does not unpin it. Remove every unreachable node, including
out-of-scope nodes; do not keep dead nodes to improve a preservation score.

Rank valid update graphs by these criteria, in order:

1. Sort target PackagePaths ascending ASCII, then maximize their numeric stable-version list
   lexicographically. Request-array order does not participate.
2. Minimize changed old non-target PackagePaths. A changed version or removal counts once.
   Newly introduced paths count zero. Target freshness precedes preserving dependencies.
3. Choose the first graph under canonical graph ordering.

Canonical graph ordering sorts each graph's release list by PackagePath ascending ASCII and
stable version descending numerically, then compares lists lexicographically using that same
entry order. A strict prefix sorts before the longer list. Initial resolution uses this ordering
directly. An earlier-sorting newly introduced path can beat a graph with a higher version of
another package. Immutable metadata and the flat profile determine bindings from the selected set.

Normalize successes independently of search order: root node first, remaining nodes by PackagePath
ascending and version descending, bindings by IR PackageName ascending. Object key order is not
part of structured result comparison. Return `{ok: true, graph}`.

## Failure diagnosis and evidence

After input and lock validation and completeness checks, search supported scoped graphs. If none
exist, search supported graphs after relaxing only outside-scope release pins. If one exists,
return `update-scope-conflict`. Otherwise search abstract consumer-scoped coexistence graphs,
also allowing those pins to relax. If one exists, return `unsupported-capability`. Only if none
exists return `unsatisfiable-requirements`. Exact target constraints, fixed root, reachable targets,
all requirements, and cycle rejection hold in every search.

Return `{ok: false, diagnostic}` with one of these shapes:

| Code | Evidence fields |
| --- | --- |
| `invalid-input`, `invalid-lock` | `violations: [{pointer, rule}]` |
| `incomplete-input` | `missing: [{kind: "catalog", packagePath} \| {kind: "release", release}]` |
| `update-scope-conflict` | `changedPins`, `witness` |
| `unsupported-capability` | `requiredCapabilities: ["graph-aware-coexistence"]`, `changedPins`, `witness` |
| `unsatisfiable-requirements` | `root: ReleaseRecord`, `catalogs: Catalog[]`, `targets: UpdateTarget[]` |

Missing evidence is deduplicated and sorted by kind, PackagePath, then version descending.
Changed pins identify relaxed outside-scope pins only, sorted by previous PackagePath then selected
version descending: `{kind: "changed", previous: ReleaseId, selected: ReleaseId}` or
`{kind: "removed", previous: ReleaseId}`. A coexistence witness may have several selected releases
for one path; include each differing selected identity once. If no occurrence uses an old pinned
path, report removal. `changedPins` is empty for initial resolution or when no pins need relaxing.

A witness is `{nodes: [{occurrence: string[], release: ReleaseId, bindings:
[{irPackageName, targetOccurrence: string[]}]}]}`. Fully unfold the dependency graph from root.
Root has occurrence `[]`; a child appends its dependency IR PackageName to its consumer occurrence.
Even a shared release appears at each consumer path. Sort occurrences segmentwise ASCII with
prefixes first, and bindings by IR PackageName. Every targetOccurrence names that exact child.
There is one binding per consumer IR name, but abstract witnesses allow different releases for
the same PackagePath or IR name in different consumers. A repeated exact release on an ancestor
path is a cycle and forbidden. Finite candidate metadata therefore bounds this diagnostic search.

Select the first witness by canonical sorted release-list ordering, including repeated occurrence
identities. Break equal-list ties by the normalized occurrence records, comparing occurrence paths,
release identities, then bindings and targetOccurrence paths with the orders defined above.
Witness selection does not use update freshness or preservation scoring. A witness is never a
supported lock, payload rewrite, or permission to install or change unrelated packages.

Unsatisfiable evidence contains the whole reachable input problem, not a minimum conflict core.
Normalize root requirements by IR name, reachable catalogs by PackagePath, candidate releases by
version descending, candidate requirements by IR name, and targets by PackagePath. Initial targets
are `[]`. The structured projection, not explanatory text or search visitation order, is compared.

## Fixed compatibility cases

[resolution-cases.json](mck/resolution-cases.json) lists confined relative fixture paths under
`fixtures/resolution/`. Each fixture holds `formatVersion` and `cases`; each case has a globally
unique stable `id`, `family`, `description`, raw-string `input`, and fixed `expected` result.
The [case schema](schemas/resolution-case.schema.json) validates the index and fixture envelopes.
Syntax-negative raw inputs intentionally do not conform to the input schema. Malformed fixture
envelopes are kit errors, never domain rejection passes.

Family values are `replay`, `initial-selection`, `backtracking`, `target-freshness`, `preservation`,
`update-boundary`, `shared-dependencies`, `exact-requests`, `multiple-targets`, `graph-ordering`,
`failure-distinctions`, `input-permutations`, and `profile-boundaries`.

The seed fixes `example.com/app/root@1.0.0`, IR `example/app`, requiring IR `example/eligibility`
from `example.com/finance/eligibility` in `[1.0.0, 2.0.0)`. Candidates `1.2.0` and `1.3.0` select
`1.3.0`. An empty catalog is unsatisfiable; an absent catalog is incomplete input.
Every fixture digest is a syntactically valid synthetic metadata projection: 64 zero hex digits,
or 64 one digits for the deliberate mismatch. These values claim no payload or manifest integrity.
Expected selections and evidence are authored from this contract, independently of the resolver,
and must never be generated or regenerated from the implementation under test. Witness-ranking cases also cover
repeated exact-release identities and equal release-list ties constrained by target reachability.

`finos/morphir` owns these specifications, schemas, and fixed data. The shared MCK core in
`finos/morphir-typescript` owns loading, execution, capability checks, comparison, corpus hashing,
and reporting. Independent implementations consume that driver. No second compatibility checker
belongs here. Required cases need zero failures, kit errors, or skips for a compatibility claim.
Passing this bounded corpus does not complete Stage 0 or authorize installation.
