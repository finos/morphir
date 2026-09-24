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
| Revision | Optional immutable artifact snapshot identifier. Without it, a resolver selects the current artifact in its context. |
| Positional guard | Required for an unpinned path containing an ordered child, so an insertion cannot silently retarget that path. |

Conceptually, these are separate types, even though a URI has to render them as text:

```ts
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

The fragment is a path of typed semantic steps. `distribution` selects the whole distribution; `package` selects its own package definition or specification. `dependency` plus a canonical package path selects one embedded dependency package, which can contain specifications in a Library or definitions in an Application. `entry-point` plus a name selects an Application entry point. `module` is followed by one canonical module-path component, then optionally `type` or `value` and one canonical local name. A `module` at the beginning of a fragment belongs to the artifact's own package; a dependency's module follows its `dependency` step. `type-exp` enters a type alias's expression; `body` enters a value definition's body. A constructor step such as `record`, `apply`, `tuple`, or `pattern-match` must match the current semantic variant. It is followed by a role that variant actually has, such as `field`, `function`, `argument`, `element`, or `case`, and then a canonical name or zero-based index when that role has multiple children. The full role set is version-specific and derives from the semantic IR model; a URI parser may decode text but a resolver must reject a role not defined for that node and version. Generic JSON Pointer member names are not valid substitutes for semantic roles.

Components are UTF-8 percent encoded individually. Split fragment segments at literal `/` **before** decoding them; a slash inside one canonical package or module path is `%2F`. Use uppercase hex in percent escapes, encode reserved characters, and reject invalid UTF-8, duplicate query keys, unknown parameters, noncanonical Morphir name spellings, negative or leading-zero indices, and a URI that parses to more than one address. A canonical writer emits one spelling for each typed address. The [naming contract](../draft/names.md) decides whether a decoded package, module, type, value, or field name is valid; a URI does not admit arbitrary Unicode in those names merely because UTF-8 percent encoding can carry it. An Application entry-point key is a different domain value: preserve its exact nonempty identifier and percent encode it without Morphir-name normalization.

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

A module path such as `sales/orders` occupies **one** component: `#/module/sales%2Forders/type/order`. A type and value called `order` have distinct roots. Changing the physical V4 document suffix from `.json` to `.yaml` changes neither URI.

The typed module, type and value roots carry an owner: `own-package` or `dependency` with a package path. The URI's optional `dependency` prefix renders that owner. This prevents an embedded dependency's `basics#int` from colliding with a same-named module and type in the artifact's own package. It also avoids assuming every dependency is separately installed as an artifact.

## Resolution and revision behavior

A resolver first parses the URI into typed parts, then selects an artifact through its caller-provided context. Without `rev`, it selects the current matching artifact; two releases with the same package path yield `ambiguous_artifact` until the caller narrows the context. With `rev`, it selects and verifies exactly the named immutable snapshot. The URI parser does not invent a revision by hashing whichever file it received: a package release or unpublished snapshot supplies a verified content digest through its artifact resolver. A missing or unverifiable snapshot yields `revision_unavailable` or `revision_mismatch`; it never falls back to current. A local working artifact needs an immutable snapshot before it can produce a pinned permalink.

Equivalent JSON, YAML, and document-tree encodings of one semantic model share an unpinned node address. A pinned link identifies an exact acquired snapshot; converting that snapshot into a new physical artifact may produce a different revision token even when the semantic model remains equal. Hosts that can acquire and verify the same snapshot can resolve its pinned URI without sharing a website URL.

The resolver checks the artifact's actual format version before traversing the root and child steps. It builds or queries a version-specific semantic node index and returns one node. Missing names, changed constructors, and guard mismatches yield `stale_target`. Multiple targets for one typed address yield `ambiguous_target`, which is an index or input error, not a reason to choose the first node. Unsupported versions yield `format_version_mismatch`; malformed URI text yields `invalid_node_uri` before artifact access.

A named unpinned path follows the current node with that name. An ordered child needs a guard because inserting an earlier tuple element or match case can leave the same index pointing at a different node. Identical repeated semantic subtrees cannot be assigned historical object identity without stable IDs in the IR; this contract identifies semantic positions and reports detectable retargeting. A pinned URI always uses the addressed snapshot's ordering.

The draft guard fingerprints the *ordered-step lineage*: the role, index, and selected semantic child at each ordered step in the path. This lets one guard cover multiple nested positional selections. It is rendered as `guard=sha256:` followed by 64 lowercase hex digits. The URI parser checks the token's spelling; the resolver recomputes it for the selected current lineage and returns `stale_target` on a mismatch. Its canonical input encoding is **not yet fixed**, so the example token below is illustrative and this draft does not grant cross-implementation guard compatibility. A reviewed digest profile and fixed hash vectors are required before activating guarded cases in MCK.

```text
morphir://ir/pkg/acme/orders?format=4.0.0&guard=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#/module/domain/type/pair/type-exp/tuple/element/1
```

An unpinned URI with an ordered child and no guard is invalid. A pinned URI does not need a guard because its `rev` fixes the artifact snapshot. Named paths need no guard and can follow the current definition across edits.

| Outcome | Cause |
| --- | --- |
| `invalid_node_uri` | Invalid URI syntax, escaping, name, unknown role token, or missing required guard |
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
3. For an empty `TypeID` path, insert `type-exp`: Elm's lookup returns the type expression, while the new `type` root denotes the definition/specification. For an empty `ValueID` path, insert `body` for the same reason. Validate every following child step against its actual constructor.
4. Serialize the typed address only after one exact target is found. Reject two different old keys that collapse to one URI. On any invalid key, unresolved target, or value-validation failure, leave the original sidecar intact and report the key; the final migration writes the full replacement transactionally.

| V3 key, assuming the stated node shape | Typed meaning | New fragment |
| --- | --- | --- |
| `Acme.Orders:Domain` | Module | `#/module/domain` |
| `Acme.Orders:Domain:order.type` | Type alias expression | `#/module/domain/type/order/type-exp` |
| `Acme.Orders:Domain:order.type#customerId` | Record field's type expression | `#/module/domain/type/order/type-exp/record/field/customer-id` |
| `Acme.Orders:Domain:calculateTotal.value` | Value body | `#/module/domain/value/calculate-total/body` |
| `Acme.Orders:Domain:calculateTotal.value#0` | `Apply` function | `#/module/domain/value/calculate-total/body/apply/function` |
| `Acme.Orders:Domain:calculateTotal.value#1` | `Apply` argument | `#/module/domain/value/calculate-total/body/apply/argument` |
| `Acme.Orders:Domain:pair.type#1` | Second tuple type element | `#/module/domain/type/pair/type-exp/tuple/element/1` plus guard if unpinned |

The checked-in reference fixture includes `Morphir.Reference.Model:BooksAndRecords:deal/type#product`. Its `/type` spelling is not the Elm codec's declared `.type` spelling: the permissive parser happens to strip five characters, while `/value` can enter the wrong type branch. A migrator must recognize such keys explicitly and verify their targets. The current Elm `getAttribute` has no implemented `ModuleID` lookup, so module conversion needs the new index rather than an assumption based on that function.

## Sidecars and V4 layouts

The current decoration configuration keeps `displayName`, schema `ir`, `entryPoint`, and `storageLocation`. A proposed first explicit sidecar envelope, `1.0.0-draft.1`, uses the **same** configured file and preserves each JSON value. It replaces bare V3 node-ID keys with validated URI keys; it does not create a companion file. The sidecar format and safe file writes belong to `morphir-uqub.8`, and typed value/target validation belongs to `morphir-uqub.12`.

```json
{
  "formatVersion": "1.0.0-draft.1",
  "targets": {
    "morphir://ir/pkg/acme/orders?format=3.0.0#/module/domain/type/order/type-exp/record/field/customer-id": ["pII"],
    "morphir://ir/pkg/acme/orders?format=3.0.0#/module/domain/value/calculate-total/body/apply/argument": ["nPI"]
  }
}
```

A V4 sidecar uses the same envelope with `format=4.0.0`; its `targets` may include a definition and a nested field. A sidecar for a current working artifact normally uses unpinned URIs. One archived with an immutable snapshot may use a verified `rev`. Neither form silently applies an old decoration to a different node.

```json
{
  "formatVersion": "1.0.0-draft.1",
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
| Single JSON document | `distribution.Library.def.modules.domain.value.types.order.TypeAliasDefinition.typeExp.Record.fields.customer-id` |
| Equivalent YAML document | The corresponding YAML mapping entry after semantic normalization |
| Document tree | The `order.type.json` or `order.type.yaml` node document and its record-field entry |

The existing `morphir://pkg/.../order.type.json` locates that document, not the nested field. Translation needs the loaded artifact and its logical document mapping. A raw JSON Pointer appended to the document URI is not a semantic node address.

The [draft node-address reference corpus](fixtures/node-addresses-draft.json) records independent positive and negative examples. It is not an executable MCK capability until the shared adapter protocol grows an address operation; the existing MCK checker remains the sole runner.
