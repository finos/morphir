---
type: Decision Record
title: Native metadata uses a scoped property graph
description: Native V4 metadata uses compact facts on Type and Value nodes, specification annotations, and document-level $meta graph statements; contexts expand names and assertion identity retains carrier ownership.
state: Accepted
decided: 2026-09-25
tags: [ir, metadata, linked-data, v4, decorators]
status: draft
---

# Native metadata uses a scoped property graph

Morphir metadata needs to describe typed facts and relationships about addressed IR nodes. A decorator attachment is one useful view of that information, but a single typed value attached to one target cannot express repeated predicates, incoming links, or facts about a node in another document. We chose a compact property graph for a future V4 minor revision. This decision selects the model and authoring direction. It does not mint an IR revision or change `4.0.0` readers.

## Decision

Type and Value nodes write outgoing default-graph facts in `attributes.facts`, with the enclosing node as subject. A specification's `annotations` envelope can declare its own `@context`, `entries`, and `facts`. Document-level `$meta.@graph` writes explicit-subject facts, including statements about nodes in supplied dependencies. The document containing each assertion owns it, regardless of the subject's document.

An effective `@context` maps readable property keys to Morphir predicate declarations. It can scope aliases, prefixes, and a default vocabulary. Expansion produces canonical Morphir identities before validation; the alias text is not predicate identity. Node URI semantics identify subjects and node-reference objects. The first executable increment accepts only Morphir node subjects, Morphir predicates, and the default graph. The logical model retains graph identity so later quads can be specified without treating graph names as provenance.

Facts have set semantics. Several distinct objects may share a subject and predicate. Equal facts written in multiple places appear once in a graph query but retain separately owned assertions. An assertion key is derived from the owning document, semantic carrier, and expanded fact. Its carrier is an addressed `attributes.facts` or `annotations.facts` container, or the document's `$meta.@graph`; it is not a JSON Pointer, field offset, or authored alias.

## Alternatives

| Approach | Decision | Reason |
| --- | --- | --- |
| A. Explicit predicate, object, and origin records | Rejected as ordinary authoring syntax | Every node-local fact would repeat its subject and most records would repeat a context-resolved predicate. Expanded records remain useful for diagnostics and interchange. |
| B. Compact scoped property graph | Chosen | Ordinary property names stay readable while contexts, declaration resolution, and Node URIs preserve precise identities. Node-local and document-level forms normalize to the same graph. |
| C. FQName-keyed maps with Ion fact/quad S-expressions | Rejected as the primary syntax | A map cannot naturally hold repeated objects without a new convention, and an Ion-only fact syntax would create a different authoring model. Ion keeps its existing attribute structures and adds `morphir::$meta::{}` for document metadata. |

We use JSON-LD's compact context and value ideas without declaring the complete IR document to be JSON-LD. The bounded context grammar and typed Morphir data mapping require independent conformance cases. RDF import/export remains a later goal; it needs explicit IRI, datatype, blank-node, and graph mappings.

## Provenance and edits

New output defaults to the containing document as its source. A producer can optionally persist more detail in `$meta.assertionSources`. Each record selects one same-document authored assertion by carrier and expanded fact, then lists its tagged sources. The separate table keeps ordinary facts concise and avoids a serialized assertion-hash format. It also costs an extra record for selected assertions. When a fact changes, a writer updates its selector and sources together or reports an error. An ordinary rewrite preserves any existing detail, even when detailed storage is not the writer's default.

Source labels are producer claims, not proof of authorship and not permission to fetch a resource. A source-dependent removal requires stored detail or a trusted producer manifest; it cannot guess from the graph alone.

## Contexts and publication

Authoring contexts may be inline, confined local files, or explicitly accepted content-addressed resources. A context digest identifies exact raw bytes but does not establish trust. Standalone export defaults to inline materialization; an archive defaults to inventoried external files. Publication verifies its resource closure and binds declarations and node links supplied by the containing archive to that archive. External declarations and links receive verified artifact-revision pins. This self-binding rule avoids a digest cycle between an archive and a context inside it. A reader never falls back from a missing pinned provider to an unpinned current artifact.

## Compatibility and consequences

V3 and V4 decorator sidecars remain supported external overlays. After target and typed value validation, an implementation may project a sidecar entry into the graph with sidecar ownership intact. Reading the graph does not rewrite the sidecar. An explicit future migration can copy representable data to native V4; this decision sets no implicit precedence, deep merge, or retirement rule.

The first runtime must distinguish descriptive facts from facts that require an interpreter. An unknown predicate remains readable but cannot count as validated semantics. The predicate schema closure must supply subject roles, object form and type, and any required interpreter. A display name alone cannot establish those properties.

The provider's V4 IR carries those declarations as native facts. In a publishable `Library`, document `$meta.@graph` describes public value definitions and their public output signatures; in a `Specs` document, value-specification `annotations.facts` can carry the same declaration. A finite built-in schema vocabulary supplies the bootstrap meanings of `subject-role`, `object-form`, optional `node-target-kind`, and `interpreter`. We rejected a separate signed declaration-closure file because it would duplicate identities and introduce another artifact to inventory and keep in sync. Semantic validation uses this native closure only after the exact provider IR and contexts have been acquired through fresh authenticated Library restore. The reference MCK closure fixture is an oracle, not the production carrier.

The `targetNames` example is a single typed `@json` object with `frontend` and `backend` maps keyed by language ID. Supporting that example requires a bounded string-keyed `morphir/SDK:dict#dict` data mapping in the shared validator. The current decorator validator does not provide it; fixed cases and implementation must add it rather than replacing arbitrary language IDs with a fixed record of language names.

[Decision 0014](/decisions/0014-scope-of-v4-0-0-for-design-only-features.md) still governs `4.0.0`: its `$meta` is reserved and ignored in document trees, and classic documents reject root `$meta`. The new syntax, Ion revision, MCK cases, and implementation support must advance together. The [draft reference corpus](../../../../../spec/ir/mck/metadata-contract-draft.md) records initial fixed examples without claiming executable support.
