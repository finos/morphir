---
title: "Semantic IR node addresses"
sidebar_label: "Node addresses (draft)"
description: "Draft V3/V4 semantic node identity, Morphir URIs, and resolution"
---

# Semantic IR node addresses

> **Draft for [#957](https://github.com/finos/morphir/issues/957).** The examples define a proposed contract, not a released URI or sidecar format. V3 and V4 decorator sidecars remain supported work; native V4 metadata may later provide another way to attach metadata.

A node address identifies a location in the *normalized IR model*. It is independent of the file containing that node, the JSON or YAML syntax used to write it, and the website that displays it. A Morphir URI serializes that address. A browser URL can then be derived from the URI and a publication context.

## Address model

| Part | Meaning |
| --- | --- |
| Artifact selector | A package path or resolver-provided workspace alias. The selector can be unpinned; a package path alone does not choose between multiple releases. |
| Format version | The exact V3 or V4 semantic contract used to interpret the path. It does not change when the same model is written as JSON, YAML, or a document tree. |
| Root | The distribution, its own package, an embedded dependency package, an application entry point, a named module, or a type or value definition/specification within a module. The type/value distinction is part of identity. |
| Child steps | Typed constructor and child roles from that version's semantic model. A named map entry uses a normalized Morphir name; an ordered child uses a zero-based index. |
| Revision | A tagged choice: `current` selects the artifact in the resolver context; `pinned` selects one immutable snapshot. |
| Positional guard | Required for an unpinned path containing an ordered child, so an insertion cannot silently retarget that path. |

Conceptually, these are separate types, even though a URI has to render them as text:

```ts
type Revision =
  | { kind: "current" }
  | { kind: "pinned"; algorithm: "sha256"; digest: string };

const fieldAddress = {
  artifact: { kind: "package", packagePath: "acme/orders" },
  formatVersion: "4.0.0",
  root: {
    kind: "type",
    owner: { kind: "own-package" },
    module: "domain",
    name: "order",
  },
  steps: [
    { kind: "type-expression" },
    { kind: "record-field", name: "customer-id" },
  ],
  revision: { kind: "current" },
} as const;
```

A decoder must validate each step against the actual IR constructor. For example, `apply/argument` only exists beneath an `Apply` expression, and `record/field/customer-id` only exists when the record has that field. An implementation may use compact internal indexes, but it must expose typed addresses and report duplicate or missing targets.

Each V3 or V4 index traverses one normalized artifact and provides both address-to-node lookup and node-to-address enumeration. Source files and source spans are optional *locations attached to a result*; they are not part of the address. If normalization produces two nodes for one address, index construction fails with `ambiguous_target` instead of overwriting one. The same semantic node loaded from equivalent V4 JSON, YAML, or document-tree layouts must produce the same address.

## Proposed URI text form

```text
morphir://ir/pkg/acme/orders?format=4.0.0#/module/domain/type/order/type-exp/record/field/customer-id
```

`ir` is the authority for semantic IR addresses. It is distinct from the existing `morphir://pkg/.../*.type.json` document-tree address, which locates a logical document in one storage layout. After the authority, `pkg` selects a package path; `workspace` selects an alias supplied by the resolver context. A workspace alias is portable as an address but only resolves where that alias has been configured. The required `format` parameter uses the exact three-component IR release form; thus numeric IR `4` is written as `format=4.0.0`. `rev` and `guard` are optional query parameters whose conditions are described below. The canonical parameter order is `format`, `rev`, then `guard`.

A workspace alias is a nonempty lowercase ASCII slug matching `[a-z][a-z0-9]*(?:-[a-z0-9]+)*`, such as `orders` or `team-orders-2`. Its spelling is exact: the resolver does not case-fold, apply Unicode normalization, or reinterpret it as a Morphir name. Uppercase letters, Unicode, `/`, `%`, empty aliases, leading/trailing hyphens, and redundant percent escapes are invalid. An alias occupies one literal URI path segment and is emitted without percent escapes. This deliberately narrow draft grammar avoids two resolvers treating differently normalized workspace labels as the same selector; a future grammar expansion requires a new reviewed contract.

| Workspace path after `/workspace/` | Result |
| --- | --- |
| `team-orders-2` | Valid alias, resolved by exact spelling |
| `Orders` or `caf%C3%A9` | Invalid uppercase or Unicode alias |
| `team%2Forders` or `a%25b` | Invalid encoded slash or percent sign |
| Empty segment or `orders-` | Invalid empty or trailing-hyphen alias |

The fragment is a path of typed semantic steps. `distribution` selects the whole distribution; `package` selects its own package definition or specification. `dependency` plus a canonical package path selects one embedded dependency package, which can contain specifications in a Library or definitions in an Application. `entry-point` plus a name selects an Application entry point. `module` is followed by one canonical module-path component, then optionally `type` or `value` and one canonical local name. A `module` at the beginning of a fragment belongs to the artifact's own package; a dependency's module follows its `dependency` step. `type-exp` enters a type alias's expression; `body` enters a value definition's body. A constructor step such as `record`, `apply`, `tuple`, or `pattern-match` must match the current semantic variant. It is followed by a role that variant actually has, such as `field`, `function`, `argument`, `element`, or `case`, and then a canonical name or zero-based index when that role has multiple children. Generic JSON Pointer member names are not valid substitutes for semantic roles.

The draft now assigns roles to every V3/V4 type expression, value expression, pattern, and definition child. A role identifies a semantic edge, not a JSON member. The table gives the suffix added to the current node's fragment. `name` is one canonical Morphir name component; `n` is a zero-based index. The index checks that the parent has the stated constructor and child. An implementation rejects unknown roles.

| Parent node | Child | Fragment suffix |
| --- | --- | --- |
| Type alias or value expression definition | Alias type or expression body | `/type-exp`, `/body` |
| Value definition or specification | Named input type, output type | `/input/name`, `/output` |
| V3 value definition | Input value annotation | `/input-annotation/name` |
| Derived or incomplete type | Base type, partial type | `/derived/base-type`, `/incomplete/partial-type` |
| Custom type | Constructor, its ordered argument type | `/constructor/name`, then `/argument/n` |
| Record or extensible record type | Named field type | `/record/field/name`, `/extensible-record/field/name` |
| Function or reference type | Parameter, result, ordered type argument | `/function/parameter`, `/function/result`, `/reference/argument/n` |
| Tuple type or value | Ordered element | `/tuple/element/n` |
| Apply or field value | Function, argument, field subject | `/apply/function`, `/apply/argument`, `/field/subject` |
| Destructure or conditional value | Pattern, value, body; condition, then, else | `/destructure/pattern`, `/destructure/value`, `/destructure/body`; `/if/condition`, `/if/then`, `/if/else` |
| Lambda or let value | Pattern, body; named definition, body | `/lambda/pattern`, `/lambda/body`; `/let/definition/name`, `/let/body` |
| List or pattern-match value | Ordered element; subject, ordered case pattern or body | `/list/element/n`; `/pattern-match/subject`, `/pattern-match/case/n/pattern`, `/pattern-match/case/n/body` |
| Record or update value | Named field; update subject or named field | `/record/field/name`; `/update/subject`, `/update/field/name` |
| As, tuple, constructor or head-tail pattern | Child pattern | `/as-pattern/pattern`, `/tuple-pattern/element/n`, `/constructor-pattern/argument/n`, `/head-tail/head`, `/head-tail/tail` |
| V4 external or incomplete value definition | Fallback or partial body | `/external/fallback`, `/incomplete/partial-body` |
| V4 hole value or incomplete definition | Expected or retained type | `/hole/expected-type` |
| V4 value or pattern with an inferred type | Inferred Type node | `/inferred-type` |
| V4 module, type, or value specification | Value in an ordered structured annotation argument | `/annotation/entry/n/argument/n` |

Distribution, package, module, type/value definition or specification, constructor, entry point, type expression, value expression, and pattern are addressable nodes. An annotation entry itself has no separate node URI, but its structured Value arguments do; the ordered entry and argument steps identify them. Literal payloads, names, attributes, documentation text, and external binding descriptors belong to their enclosing semantic node and do not receive separate node URIs in this draft. If a later metadata design needs one of those as an independent target, it must add a reviewed role rather than reuse a storage path.

Components other than workspace aliases are UTF-8 percent encoded individually. Split fragment segments at literal `/` **before** decoding them; a slash inside one canonical package or module path is `%2F`. Use uppercase hex in percent escapes, encode reserved characters, and reject invalid UTF-8, duplicate query keys, unknown parameters, noncanonical Morphir name spellings, negative or leading-zero indices, and a URI that parses to more than one address. A canonical writer emits one spelling for each typed address. The [naming contract](../draft/names.md) decides whether a decoded package, module, type, value, or field name is valid; a URI does not admit arbitrary Unicode in those names merely because UTF-8 percent encoding can carry it. An Application entry-point key is a different domain value: preserve its exact nonempty identifier and percent encode it without Morphir-name normalization.

| Semantic target | Proposed fragment |
| --- | --- |
| Distribution | `#/distribution` |
| Own package | `#/package` |
| Embedded dependency package | `#/dependency/morphir%2FSDK` |
| Type inside an embedded dependency | `#/dependency/morphir%2FSDK/module/basics/type/int` |
| Application entry point | `#/entry-point/start` |
| Module | `#/module/domain` |
| Type definition/specification | `#/module/domain/type/order` |
| Type alias record field | `#/module/domain/type/order/type-exp/record/field/customer-id` |
| Value definition/specification | `#/module/domain/value/calculate-total` |
| `Apply` function or argument | `#/module/domain/value/calculate-total/body/apply/function` or `/argument` |
| Second tuple type element | `#/module/domain/type/pair/type-exp/tuple/element/1` |
| Second pattern-match case's pattern | `#/module/domain/value/evaluate/body/pattern-match/case/1/pattern` |
| Inferred type on a value expression | `#/module/domain/value/evaluate/body/inferred-type` |
| First argument value of a structured annotation | `#/module/domain/value/evaluate/annotation/entry/0/argument/0` |

A module path such as `sales/orders` occupies **one** component: `#/module/sales%2Forders/type/order`. A type and value called `order` have distinct roots. Changing the physical V4 document suffix from `.json` to `.yaml` changes neither URI.

The typed module, type and value roots carry an owner: `own-package` or `dependency` with a package path. The URI's optional `dependency` prefix renders that owner. This prevents an embedded dependency's `basics#int` from colliding with a same-named module and type in the artifact's own package. It also avoids assuming every dependency is separately installed as an artifact.

## Resolution and revision behavior

A resolver first parses the URI into typed parts, then selects an artifact through its caller-provided context. An absent `rev` decodes to `{ kind: "current" }` and the writer omits `rev` for that variant; a present `rev` decodes to `{ kind: "pinned", algorithm, digest }` and the writer emits it. A current selector chooses the matching artifact; two releases with the same package path yield `ambiguous_artifact` until the caller narrows the context. A pinned selector verifies exactly the named immutable snapshot. The URI parser does not invent a revision by hashing whichever file it received: a package release or unpublished snapshot supplies a verified content digest through its artifact resolver. A missing or unverifiable snapshot yields `revision_unavailable` or `revision_mismatch`; it never falls back to current. A local working artifact needs an immutable snapshot before it can produce a pinned permalink.

Equivalent JSON, YAML, and document-tree encodings of one semantic model share an unpinned node address. A pinned link identifies an exact acquired snapshot; converting that snapshot into a new physical artifact may produce a different revision token even when the semantic model remains equal. Hosts that can acquire and verify the same snapshot can resolve its pinned URI without sharing a website URL.

The resolver checks the artifact's actual format version before traversing the root and child steps. It builds or queries a version-specific semantic node index and returns one node. Missing names, changed constructors, and guard mismatches yield `stale_target`. Multiple targets for one typed address yield `ambiguous_target`, which is an index or input error, not a reason to choose the first node. Unsupported versions yield `format_version_mismatch`; malformed URI text yields `invalid_node_uri` before artifact access.

A named unpinned path follows the current node with that name. An ordered child needs a guard because inserting an earlier tuple element or match case can leave the same index pointing at a different node. Identical repeated semantic subtrees cannot be assigned historical object identity without stable IDs in the IR; this contract identifies semantic positions and reports detectable retargeting. A pinned URI always uses the addressed snapshot's ordering.

**Guard behavior decision:** an unpinned indexed URI uses a node fingerprint, not the revision of the whole artifact. The guard fingerprints the *ordered-step lineage*: the role, index, and selected semantic child at each ordered step in the path. This lets one guard cover multiple nested positional selections. Editing an unrelated module or adding an element after the selected position leaves the guard valid; changing the selected child or shifting its index makes it stale. An edit inside a selected child subtree may also change its fingerprint, even if the final descendant named by the URI did not change. The guard does not hash unrelated artifact content or physical JSON, YAML, and document-tree bytes.

The spelling is `guard=sha256:` followed by 64 lowercase hex digits. The URI parser checks the token's spelling. The resolver recomputes the selected current lineage and returns `stale_target` on a mismatch. The `draft.1` digest input starts with the UTF-8 bytes `morphir-node-fingerprint-draft.1` and a zero byte. For each ordered step from root to leaf, append a four-byte big-endian length and the UTF-8 role name, an eight-byte big-endian index, then an eight-byte big-endian length and the canonical JSON bytes of the selected typed IR child. A pattern-match case selection hashes the whole case (pattern and body), even when the URI descends through only one of them; swapping cases with equal bodies but different patterns must stale a body URI. Roles include `tuple/element`, `reference/argument`, `constructor/argument`, `annotation/entry`, `annotation/argument`, `list/element`, `pattern-match/case/pattern`, `pattern-match/case/body`, `tuple-pattern/element`, and `constructor-pattern/argument`. Hash the complete byte stream with SHA-256.

Canonical child JSON comes from the normalized V3 or V4 model. Serialize V4 types in the expanded semantic form regardless of a caller's ambient compact-output setting. Omit `source` coordinates and tool `extensions` only from typed V4 IR attributes; keep arbitrary JSON inside a `DocumentLiteral` byte-for-byte as semantic payload. An empty typed `attributes` object is omitted. Keep semantic constraints and inferred types. Sort object keys by their decoded UTF-8 bytes, then apply JSON string escaping; keep array order and Unicode code points. The IR model's numeric literal lexeme remains part of that model. Source JSON/YAML whitespace, member order, document filenames, and unrelated siblings do not enter the hash. A V4 `Unit` type with default attributes writes `{"Unit":{}}`. Selecting it at `/tuple/element/1` gives `sha256:05709fcf331bd4125b9a2121fac18712390e8572bb545cd091be14bd925ffe92`. The same typed node loaded from V4 JSON, YAML, or a document tree produces this digest.

For the proposed V4 `4.1.0` linked-metadata revision, fingerprint serialization omits `attributes.@context` and `attributes.facts` along with `source` and `extensions` **before** selecting a Value or Pattern's compact or expanded spelling. A fact-only edit anywhere inside a selected child therefore leaves its unpinned guard valid. Constraints, inferred types, and JSON data inside those semantic fields remain in the digest. Exact artifact revisions still hash the acquired bytes, including metadata, so a fact edit changes a pinned snapshot's revision. Existing V3 and V4 `4.0.x` guards keep their original `draft.1` byte inputs; their previously issued URIs are not recalculated using the `4.1.0` attribute rule.

```text
morphir://ir/pkg/acme/orders?format=4.0.0&guard=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#/module/domain/type/pair/type-exp/tuple/element/1
```

An unpinned URI with an ordered child and no guard is invalid. A pinned URI does not need a guard because its `rev` fixes the artifact snapshot. Named paths need no guard and can follow the current definition across edits.

| Edit after issuing an unpinned link to tuple element 1 | Fingerprint guard result |
| --- | --- |
| Edit another module | Resolves the same selected element |
| Insert an element before position 1 | `stale_target` if position 1 now selects a different semantic child |
| Change the selected element | `stale_target` |
| Append an element after position 1 | Resolves the same selected element |

| Outcome | Cause |
| --- | --- |
| `invalid_node_uri` | Invalid URI syntax, escaping, name, unknown role token, or missing required guard |
| `artifact_mismatch` | The supplied artifact has a different package selector |
| `ambiguous_artifact` | The current selector matches more than one artifact |
| `revision_unavailable` | The requested immutable snapshot is absent |
| `revision_mismatch` | Retrieved snapshot fails revision verification |
| `format_version_mismatch` | Selected artifact has a different or unsupported IR format version |
| `stale_target` | Root/child is absent, constructor changed, or positional guard mismatches |
| `ambiguous_target` | One typed address indexes more than one semantic node |

A browser may render a resolved URI as a link such as `https://viewer.example.org/ir/acme/orders?node=...`. The browser host, routes, and display state are not part of node identity.

## V3 `NodeID` conversion

Elm V3 sidecars are flat JSON objects from `NodeID` strings to values decoded against the configured Morphir `entryPoint` type. Convert a key using the loaded V3 distribution, never by replacing punctuation in its text:

1. Parse `ModuleID`, `TypeID`, or `ValueID`, with `ChildByName` and `ChildByIndex` steps. Accept the Elm codec's `.type` and `.value` spelling. Treat historical `/type` and `/value` as a separate, explicitly tested input variant; Elm's permissive parser can otherwise misclassify them.
2. Normalize the package, module and local names under V3 rules and verify that the selected artifact matches the key's package. Resolve the target through the V3 semantic index.
3. An empty `TypeID` path is shape-dependent in Elm's lookup. For a `TypeAliasDefinition`, insert `type-exp`: the lookup returns the alias expression, while the new `type` root denotes the definition. For a `CustomTypeDefinition` with exactly one constructor named like the type and exactly one argument, the lookup returns that argument's type; conversion needs a reviewed typed path to the constructor argument and a positional guard when unpinned. Other custom-type shapes fail lookup. Do not map every `TypeID` to `type-exp`. For an empty `ValueID` path, insert `body`: Elm's lookup returns the value body. Validate every following child step against its actual constructor.
4. Serialize the typed address only after one exact target is found. Reject two different old keys that collapse to one URI. Report `mapping_not_specified` for a valid old target whose semantic role or guard encoding has not been fixed. On any invalid key, unresolved target, unsupported mapping, or value-validation failure, leave the original sidecar intact and report the key; the final migration writes the full replacement transactionally.

| V3 key, assuming the stated node shape | Typed meaning | New fragment |
| --- | --- | --- |
| `Acme.Orders:Domain` | Module | `#/module/domain` |
| `Acme.Orders:Domain:order.type` | Type alias expression | `#/module/domain/type/order/type-exp` |
| `Acme.Orders:Domain:accountId.type` | Sole argument type of the sole `accountId` custom-type constructor | `#/module/domain/type/account-id/constructor/account-id/argument/0` plus a positional guard when unpinned |
| `Acme.Orders:Domain:order.type#customerId` | Record field's type expression | `#/module/domain/type/order/type-exp/record/field/customer-id` |
| `Acme.Orders:Domain:calculateTotal.value` | Value body | `#/module/domain/value/calculate-total/body` |
| `Acme.Orders:Domain:calculateTotal.value#0` | `Apply` function | `#/module/domain/value/calculate-total/body/apply/function` |
| `Acme.Orders:Domain:calculateTotal.value#1` | `Apply` argument | `#/module/domain/value/calculate-total/body/apply/argument` |
| `Acme.Orders:Domain:pair.type#1` | Second tuple type element | `#/module/domain/type/pair/type-exp/tuple/element/1` plus guard if unpinned |

The checked-in reference fixture includes `Morphir.Reference.Model:BooksAndRecords:deal/type#product`. Its `/type` spelling is not the Elm codec's declared `.type` spelling: the permissive parser happens to strip five characters, while `/value` can enter the wrong type branch. A migrator must recognize such keys explicitly and verify their targets. The current Elm `getAttribute` has no implemented `ModuleID` lookup, so module conversion needs the new index rather than an assumption based on that function.

## Sidecars and V4 layouts

The decoration configuration keeps `displayName`, schema `ir`, `entryPoint`, and `storageLocation`. The first explicit sidecar envelope, `0.1.0-draft.1`, uses the **same** configured file and preserves each JSON value. It replaces bare V3 node-ID keys with validated URI keys; it does not create a companion file. The sidecar format and safe file writes are tracked by `morphir-uqub.8`, and typed value/target validation by `morphir-uqub.12`.

```json
{
  "formatVersion": "0.1.0-draft.1",
  "targets": {
    "morphir://ir/pkg/acme/orders?format=3.0.0#/module/domain/type/order/type-exp/record/field/customer-id": ["pII"],
    "morphir://ir/pkg/acme/orders?format=3.0.0#/module/domain/value/calculate-total/body/apply/argument": ["nPI"]
  }
}
```

A V4 sidecar uses the same envelope with `format=4.0.0`; its `targets` may include a definition and a nested field. A sidecar for a current working artifact normally uses unpinned URIs. One archived with an immutable snapshot may use a verified `rev`. Neither form silently applies an old decoration to a different node.

```json
{
  "formatVersion": "0.1.0-draft.1",
  "targets": {
    "morphir://ir/pkg/acme/orders?format=4.0.0#/module/domain/type/order": {
      "summary": "An order placed by a customer"
    },
    "morphir://ir/pkg/acme/orders?format=4.0.0#/module/domain/type/order/type-exp/record/field/customer-id": {
      "summary": "Identifier of the customer who placed the order"
    }
  }
}
```

The field type in `#/module/domain/type/order/type-exp/record/field/customer-id` has these physical homes while retaining one semantic address:

| V4 representation | Physical location |
| --- | --- |
| Single JSON document | `distribution.Library.def.modules.domain.Public.types.order.Public.TypeAliasDefinition.typeExp.Record.fields.customer-id` |
| Equivalent YAML document | The corresponding YAML mapping entry after semantic normalization |
| Document tree | The `order.type.json` or `order.type.yaml` node document and its record-field entry |

The existing `morphir://pkg/.../order.type.json` locates that document, not the nested field. Translation needs the loaded artifact and its logical document mapping. A raw JSON Pointer appended to the document URI is not a semantic node address.

The [draft node-address reference corpus](fixtures/node-addresses-draft.json) records the full typed URI grammar and resolver outcomes. The smaller [executable MCK corpus](https://github.com/finos/morphir/blob/main/spec/ir/mck/node-address-draft.json) checks V3 and V4 artifact resolution through the draft `node-address` adapter suite. The existing numeric V1 IR decode protocol remains unchanged; the new suite advertises `contractVersion: "0.1.0-draft.1"` and `operations: ["resolve"]`. The shared Rust MCK runner owns fixed outcomes and semantic node values; the adapter owns IR decoding and indexing.

```sh
morphir mck node-address run \
  --adapter ./mck-adapter-rust \
  --adapter-arg=--suite --adapter-arg=node-address \
  --report node-address-report.json
```

The executable cases cover these boundaries with fixed V3/V4 JSON artifacts:

| Boundary | Cases |
| --- | --- |
| V3 definitions, nested record fields, custom-constructor arguments, and absent fields | `node-address-0001`–`0002`, `0014`, `0032` |
| V4 definitions, nested type/value roles, pinned ordered children, and wrong node kind | `node-address-0003`–`0005`, `0015`–`0021` |
| Positional fingerprint after a changed child, later append, unrelated edit, or insertion of an identical sibling | `node-address-0010`–`0012`, `0022`–`0025` |
| Canonical URI escaping, Unicode/name grammar, query uniqueness, index spelling, required guards, and typed roles | `node-address-0006`, `0026`–`0031`, `0033` |

`node-address-0025` resolves after an identical `Unit` element is inserted before
the selected index. The semantic node at that index is indistinguishable from
the original; without a stable IR node ID, the guard cannot detect that swap.
The [URI roundtrip tests](https://github.com/finos/morphir-rust/blob/main/crates/morphir-core/tests/node_address_uri.rs)
exercise all typed child roles and the draft URI reference cases. The
[index tests](https://github.com/finos/morphir-rust/blob/main/crates/morphir-core/tests/node_address_index.rs)
cover duplicate semantic fields and equivalent V4 JSON, YAML, and document-tree
addresses. These are separate from the JSON-only MCK transport cases above.

For a configured decorator, `morphir decoration set` checks the target URI against the loaded target IR and the JSON value against the configured Morphir `entryPoint` type before replacing the sidecar. The draft sidecar can be V3 or V4. `show` and `validate` reject stale targets or invalid values; `migrate-v3` converts a flat V3 NodeID map at its existing `storageLocation` transactionally.

```json
{
  "decorations": {
    "sensitivity": {
      "displayName": "Sensitivity",
      "ir": "decorations/morphir-ir.json",
      "entryPoint": "Acme.Decorations:Domain:Sensitivity",
      "storageLocation": "attributes/sensitivity.json"
    }
  }
}
```

```sh
morphir decoration set sensitivity \
  'morphir://ir/pkg/acme/orders?format=4.0.0#/module/domain/type/order' \
  --config morphir.json --ir morphir-ir.json --value sensitivity-value.json
morphir decoration validate sensitivity --config morphir.json --ir morphir-ir.json
```

Both configured paths remain inside the project directory; `--ir` explicitly chooses the target artifact. The first CLI slice reads JSON IR and one JSON value per `--value` file. The semantic index itself also covers equivalent V4 YAML and document-tree layouts; those CLI transports can be added without changing URI keys.
