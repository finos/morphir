---
title: Linked metadata for Morphir IR
sidebar_label: Linked metadata
description: Draft V4 design for scoped facts, document graphs, provenance, and decorator coexistence
status: draft
tracking:
  beads: [morphir-uqub.6, morphir-uqub.11]
---

# Linked metadata for Morphir IR

Morphir needs to say more about an IR node than its type and body: whether an API is deprecated, its operational name, which type a rule inferred, or what name a backend should emit. It also needs to say things *about* a node without editing the document that defines that node. This draft adds typed, queryable facts to a future V4 revision. Existing `4.0.0` documents and V3/V4 decorator sidecars keep their present behavior.

The common form is short. A Type or Value node writes properties in `attributes.facts`; the enclosing node is the subject. `attributes.@context` maps readable keys such as `operationalName` to declared Morphir predicates. A specification can independently scope `annotations.entries` and `annotations.facts`. A document's `$meta.@graph` can assert facts about explicitly addressed nodes, even in another supplied artifact. These locations normalize to the same default-graph facts while retaining separate assertion ownership.

The examples below are **format sketches**, not valid `4.0.0` documents or a released Ion revision. Their surrounding document headers and future versions are omitted deliberately. [The fixed reference corpus](https://github.com/finos/morphir/blob/main/spec/ir/mck/metadata-contract-draft.md) records literal expected results; executable MCK and codec support are still planned.

## A specification in three profiles

This `legacy-submit-order` Value specification has a document vocabulary, a local attribute scope, and a separate annotation scope. `ops:operational-name` and `transactionalName` resolve to different declarations. `targetNames` is one typed data object whose `frontend` and `backend` maps can use validated language IDs. `replacement` is a node link because its context says `@type: @id`. `publicApi` is an annotation entry, not a graph fact.

### JSON

```json
{
  "$meta": {
    "@context": {
      "@vocab": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/"
    },
    "@graph": [
      {
        "@id": "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/submit-order-v2",
        "aliases": ["placeOrder", "createOrder"]
      }
    ]
  },
  "spec": {
    "attributes": {
      "@context": {
        "ops": {
          "@id": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/operations/value/",
          "@prefix": true
        },
        "transactionalName": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/transactional-name",
        "targetNames": {
          "@id": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/target-names",
          "@type": "@json"
        }
      },
      "facts": {
        "transactionalName": "Submit Order",
        "ops:operational-name": "submit_order",
        "targetNames": {
          "frontend": { "gleam": "legacy_submit_order", "typescript": "legacySubmitOrder" },
          "backend": { "java": "legacySubmitOrder", "sql": "LEGACY_SUBMIT_ORDER" }
        }
      }
    },
    "annotations": {
      "@context": {
        "@vocab": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/",
        "publicApi": "morphir://ir/pkg/acme/annotation-vocab?format=4.0.0#/module/annotations/value/public-api",
        "replacement": {
          "@id": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/replacement",
          "@type": "@id"
        }
      },
      "entries": ["publicApi"],
      "facts": {
        "deprecated": true,
        "replacement": "morphir://ir/pkg/acme/orders-next?format=4.0.0#/module/api/value/submit-order-v2"
      }
    }
  }
}
```

### YAML

```yaml
$meta:
  "@context":
    "@vocab": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/"
  "@graph":
    - "@id": "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/submit-order-v2"
      aliases: [placeOrder, createOrder]
spec:
  attributes:
    "@context":
      ops:
        "@id": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/operations/value/"
        "@prefix": true
      transactionalName: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/transactional-name"
      targetNames:
        "@id": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/target-names"
        "@type": "@json"
    facts:
      transactionalName: Submit Order
      "ops:operational-name": submit_order
      targetNames:
        frontend: { gleam: legacy_submit_order, typescript: legacySubmitOrder }
        backend: { java: legacySubmitOrder, sql: LEGACY_SUBMIT_ORDER }
  annotations:
    "@context":
      "@vocab": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/"
      publicApi: "morphir://ir/pkg/acme/annotation-vocab?format=4.0.0#/module/annotations/value/public-api"
      replacement:
        "@id": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/replacement"
        "@type": "@id"
    entries: [publicApi]
    facts:
      deprecated: true
      replacement: "morphir://ir/pkg/acme/orders-next?format=4.0.0#/module/api/value/submit-order-v2"
```

### Ion

```ion
// Proposed extension of the Ion draft profile, without a released ionVersion.
morphir::$meta::{
  '@context': {
    '@vocab': "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/",
  },
  '@graph': [
    {
      '@id': "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/submit-order-v2",
      aliases: ["placeOrder", "createOrder"],
    },
  ],
}
public::spec::value::{
  module: "api",
  name: "legacy-submit-order",
  attributes: {
    '@context': {
      ops: {
        '@id': "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/operations/value/",
        '@prefix': true,
      },
      transactionalName: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/transactional-name",
      targetNames: {
        '@id': "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/target-names",
        '@type': "@json",
      },
    },
    facts: {
      transactionalName: "Submit Order",
      'ops:operational-name': "submit_order",
      targetNames: {
        frontend: { gleam: "legacy_submit_order", typescript: "legacySubmitOrder" },
        backend: { java: "legacySubmitOrder", sql: "LEGACY_SUBMIT_ORDER" },
      },
    },
  },
  annotations: {
    '@context': {
      '@vocab': "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/",
      publicApi: "morphir://ir/pkg/acme/annotation-vocab?format=4.0.0#/module/annotations/value/public-api",
      replacement: {
        '@id': "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/replacement",
        '@type': "@id",
      },
    },
    entries: ["publicApi"],
    facts: {
      deprecated: true,
      replacement: "morphir://ir/pkg/acme/orders-next?format=4.0.0#/module/api/value/submit-order-v2",
    },
  },
}
```

The Ion form uses its own annotated elements and attribute placement; it is not a JSON object transliterated to Ion. `morphir::$meta::{}` is the selected spelling for document metadata; [Ion permits `$` in identifier symbols](https://amazon-ion.github.io/ion-docs/docs/symbols.html). The next Ion draft must specify placement in datagram, record, and tree layouts before an implementation can claim support.

| Written key | Scope | Meaning |
| --- | --- | --- |
| `transactionalName` | `attributes.@context` | Explicit alias for a naming predicate. |
| `ops:operational-name` | `attributes.@context` prefix | A different operations predicate. |
| `targetNames` | `attributes.@context` | One typed `@json` object, not one fact per nested language key. |
| `publicApi` | `annotations.@context` | An annotation declaration used by `entries`; no graph fact is added. |
| `deprecated` | `annotations.@context` vocabulary | A boolean fact about the enclosing specification node. |
| `replacement` | `annotations.@context` | A node-reference fact; the referenced artifact must resolve. |
| `aliases` | `$meta.@context` vocabulary | Two facts about the explicit subject in `$meta.@graph`. |

## Type-node attributes

The same `attributes.@context` and `attributes.facts` envelope belongs on a Type node. These three equivalent fragments attach a deprecation flag and two aliases to the enclosing Type; no top-level `facts` member is needed.

```json
{
  "attributes": {
    "@context": {
      "@vocab": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/",
      "aliases": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/aliases"
    },
    "facts": { "deprecated": true, "aliases": ["Order", "PurchaseOrder"] }
  }
}
```

```yaml
attributes:
  "@context":
    "@vocab": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/"
    aliases: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/aliases"
  facts:
    deprecated: true
    aliases: [Order, PurchaseOrder]
```

```ion
{
  attributes: {
    '@context': {
      '@vocab': "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/",
      aliases: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/naming/value/aliases",
    },
    facts: { deprecated: true, aliases: ["Order", "PurchaseOrder"] },
  },
}
```

An inferred type is a distinct case. V4 already stores a Value node's `inferredType` in its core attributes. If that expression names a Type node, a graph reader can **derive a view** such as `legacy-submit-order --inferred-type--> morphir://ir/pkg/acme/orders?format=4.0.0#/module/domain/type/order`. The view points back to the core attribute as its source; an author does not write a second `attributes.facts.inferredType` that could disagree with it. An anonymous type expression needs a separately specified data mapping and is outside the first executable increment.

## Facts, assertions, and sources

A fact is an expanded subject, predicate, object, and graph. The first executable increment accepts only the default graph. Two different aliases for the same predicate and object in one carrier yield one assertion. The same fact in `attributes.facts`, `annotations.facts`, and `$meta.@graph` yields three assertions but one fact in a graph query. Each assertion retains its owning document and carrier so a roundtrip can preserve where it was written.

Ordinary provenance comes from the containing document. A writer can optionally store exceptional detail in `$meta.assertionSources`. A record selects one authored assertion by carrier and expanded subject, predicate, and object, then lists tagged document, compiler, or author sources. Its selector must match an assertion in the same document; an edit that changes the fact updates the selector with it or fails. The [reference cases](https://github.com/finos/morphir/blob/main/spec/ir/mck/metadata-contract-draft.json) show matched, unmatched, and duplicate selectors. Source labels are descriptive claims, not proof of authorship.

For example, the document-level `deprecated: true` assertion can retain both compiler and author detail. The selector uses expanded identities, not the alias text. Omitting `assertionSources` leaves the same graph fact and ordinary document provenance.

```json
{
  "$meta": {
    "@context": { "deprecated": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated" },
    "@graph": [{
      "@id": "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/legacy-submit-order",
      "deprecated": true
    }],
    "assertionSources": [{
      "selector": {
        "carrier": "documentGraph",
        "subject": "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/legacy-submit-order",
        "predicate": "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated",
        "object": { "@value": true }
      },
      "sources": [
        { "kind": "compiler", "producer": "morphir-gleam", "ref": "src/Orders.gleam" },
        { "kind": "author", "ref": "review/deprecation" }
      ]
    }]
  }
}
```

```yaml
$meta:
  "@context":
    deprecated: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated"
  "@graph":
    - "@id": "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/legacy-submit-order"
      deprecated: true
  assertionSources:
    - selector:
        carrier: documentGraph
        subject: "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/legacy-submit-order"
        predicate: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated"
        object: { "@value": true }
      sources:
        - { kind: compiler, producer: morphir-gleam, ref: src/Orders.gleam }
        - { kind: author, ref: review/deprecation }
```

```ion
morphir::$meta::{
  '@context': {
    deprecated: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated",
  },
  '@graph': [{
    '@id': "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/legacy-submit-order",
    deprecated: true,
  }],
  assertionSources: [{
    selector: {
      carrier: "documentGraph",
      subject: "morphir://ir/pkg/acme/orders?format=4.0.0#/module/api/value/legacy-submit-order",
      predicate: "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated",
      object: { '@value': true },
    },
    sources: [
      { kind: "compiler", producer: "morphir-gleam", ref: "src/Orders.gleam" },
      { kind: "author", ref: "review/deprecation" },
    ],
  }],
}
```

Predicates come from an explicit Morphir declaration closure. Its contract determines allowed subject kinds, node-reference versus typed data object, and whether interpretation beyond storage is required. An undeclared predicate remains readable for roundtrips but cannot count as validated semantics. The `targetNames` declaration requires an interpreter for its language-ID rule; if that interpreter is unavailable, a type-valid fact is retained but reported as unvalidated. A bare array at a fact property means repeated objects; `@json` wraps one structured data object. The `targetNames` data type requires string-keyed `morphir/SDK:dict#dict` support in the shared validator. Current decorator validation does not have that support yet.

## Context resources and publication

Context imports are explicit, confined, and finite. A writer can use local relative files or an accepted `morphir://context/sha256/<digest>` resource. It checks the raw byte digest before parsing. The digest proves byte identity, not trust; a resolver must still admit the resource. An unpinned remote URL is not fetched implicitly. Context expansion and its error cases belong to the fixed contract, rather than to generic JSON-LD library behavior.

Standalone output defaults to an inline resolved context. A package archive can hold external context files in its authenticated inventory. Publication binds declarations and node links supplied by the archive to that archive; links supplied by another artifact receive that provider's verified revision. This includes explicit graph subjects, implicit node subjects, and `@id` objects. A URI-looking string inside typed `@json` data remains data. Failure to resolve or verify a required provider prevents publication; it never silently selects a current artifact.

## Decorators, migration, and later graphs

V3 and V4 decorator sidecars continue at their configured storage locations. Once their target and `entryPoint` value validate, a reader can project a sidecar entry as a typed graph fact with sidecar ownership. This does not rewrite either input. A later explicit copy-to-native operation can migrate representable values after validating every target and value. A consumer that needs one decoration value reports ambiguity if several distinct facts fit; the graph itself does not impose a single-value rule or precedence order.

Named graphs/quads are part of the logical design, but their wire spelling and execution are deferred. RDF import/export also needs explicit mappings for IR Node URIs, Morphir data types, external IRIs, blank nodes, and graph names. The first release makes no RDF-conformance claim. The [decision record](https://github.com/finos/morphir/blob/main/kb/bundles/morphir/morphir-ir/decisions/0019-native-metadata-uses-a-scoped-property-graph.md) records why this shape was selected over explicit assertion records and FQName-keyed maps.
