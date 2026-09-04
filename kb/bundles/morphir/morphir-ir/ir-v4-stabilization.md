---
type: Design Note
title: IR v4 stabilization
description: "The one register of what IR v4 has settled, where its sources still contradict each other, and which decisions remain open before the format can be called stable."
tags: [ir, ir-v4, schema, specification, stabilization, divergences]
status: draft
stale_after: 2026-12-31
sources:
  - id: v4-schema
    resource: https://github.com/finos/morphir/blob/64dc34ed170b18606360e2217841f0220447c0f2/website/static/schemas/morphir-ir-v4.yaml
    title: morphir-ir-v4.yaml
  - id: v4-tree-schema
    resource: https://github.com/finos/morphir/blob/64dc34ed170b18606360e2217841f0220447c0f2/website/static/schemas/morphir-ir-v4-document-tree-files.yaml
    title: morphir-ir-v4-document-tree-files.yaml
  - id: v4-spec
    resource: https://github.com/finos/morphir/tree/64dc34ed170b18606360e2217841f0220447c0f2/docs/spec/ir/schemas/v4
    title: docs/spec/ir/schemas/v4 (published v4 specification pages)
  - id: spec-draft
    resource: https://github.com/finos/morphir/tree/64dc34ed170b18606360e2217841f0220447c0f2/docs/spec/draft
    title: docs/spec/draft (v4 specification draft)
  - id: design-draft
    resource: https://github.com/finos/morphir/tree/64dc34ed170b18606360e2217841f0220447c0f2/docs/design/draft/ir
    title: docs/design/draft/ir (v4 design documents)
  - id: rust-v4
    resource: https://github.com/finos/morphir/tree/64dc34ed170b18606360e2217841f0220447c0f2/ecosystem/morphir-rust/crates/morphir-core/src/ir/v4
    title: morphir-rust v4 model and codecs
  - id: ui-decoder
    resource: https://github.com/finos/morphir/blob/64dc34ed170b18606360e2217841f0220447c0f2/ecosystem/morphir-ui/packages/morphir-ir/src/ast-decode.ts
    title: morphir-ui v4 value decoder
  - id: scala-kb-divergences
    resource: https://github.com/finos/morphir/blob/64dc34ed170b18606360e2217841f0220447c0f2/ecosystem/morphir-scala/kb/bundles/morphir/morphir-ir-v4-draft/design/divergences.md
    title: morphir-scala kb, Specification and Design Divergences
  - id: scala-kb-conformance
    resource: https://github.com/finos/morphir/blob/64dc34ed170b18606360e2217841f0220447c0f2/ecosystem/morphir-scala/kb/bundles/morphir/morphir-ir-v4-draft/schema-conformance.md
    title: morphir-scala kb, Schema Conformance
generated:
  by: human:damianreeves
  at: 2026-09-03T00:00:00Z
---

# IR v4 stabilization

IR v4 is not yet stable, and the reason is not missing features. Its four sources of truth disagree with each other,
and two of them disagree with themselves. This note is the single register of that state. It records what has been
settled and where, what still contradicts, and which decisions nobody has made. The [beads epic
`morphir-ir-v4-stabilize`](#tracking) partitions the work; this page is its narrative home and is updated as items
close.

The stabilization rule is that **the Morphir Compatibility Kit (MCK) at `spec/ir/mck/` is the tiebreak.** A case in the
kit states the meaning of a spelling by example; the TypeScript reference model in
`ecosystem/morphir-typescript` defines the shape; every binding is driven through the kit by
the mck driver. Prose that disagrees with a case is corrected to the case. Where no case exists the
question is open, it appears under [Open decisions](#open-decisions), and it is closed by writing the case and
the codec together. The design is recorded in the approved specification of 2026-09-04 (kept outside the
repository under `.dev/`), and its first migration step landed on this date. The schema-as-tiebreak rule this
paragraph replaces still describes how the mechanical prose corrections of 2026-09-03 were chosen.

## Sources

Four bodies of material describe v4. Each carries a different authority, and the differences are the problem.

| Source | Location | Authority |
| ------ | -------- | --------- |
| Schemas | `website/static/schemas/morphir-ir-v4.yaml` and `morphir-ir-v4-document-tree-files.yaml` | Normative. What `examples:validate` and `schema:validate` run. |
| Published spec pages | `docs/spec/ir/schemas/v4/` and `docs/spec/ir/format-version.md` | Normative prose. Carries MUST and SHOULD language. |
| Specification draft | `docs/spec/draft/` | Draft. Predates the schemas and lags them. |
| Design documents | `docs/design/draft/ir/` | Rationale. Its own status table marks nothing Approved. |

Three implementations read or write v4: the Rust codecs in `ecosystem/morphir-rust/crates/morphir-core/src/ir/v4/`,
the Rust CLI `morphir ir migrate` in `crates/morphir`, and the TypeScript decoder in
`ecosystem/morphir-ui/packages/morphir-ir/`. morphir-elm pins `currentFormatVersion = 3` and does not produce v4.

Earlier registers of the same divergences exist in the morphir-scala knowledge base, pinned to commit `4d5e5c06`.
This note supersedes them for finos/morphir and records which of their findings have since closed.

## Settled

These rules have a decision or a consistent normative source behind them. Prose that still says otherwise is a
documentation defect, listed under [Live contradictions](#live-contradictions).

| Rule | Settled by |
| ---- | ---------- |
| `formatVersion`: integer `4` is canonical for 4.0.0; `"4.minor.patch"` strings name later revisions; no prerelease or build metadata; readers reject unsupported exact releases before semantic decoding | `docs/spec/ir/format-version.md`, both schemas, bead `morphir-l2p9` |
| Names: an initialism is an uppercase segment (`value-in-USD`); readers also accept the doubled-hyphen style and the legacy word array; document-tree filenames are an escape of the name (`value-in-_usd`) | [Decision 0001](/decisions/0001-name-canonicalization-and-initialism-encoding.md), [Decision 0002](/decisions/0002-both-name-encodings-behind-one-switch.md), both schemas, `docs/spec/draft/names.md`, the Rust naming module, `docs/spec/ir/fixtures/naming-conformance.json` |
| A bare array in type position is a Tuple. A parameterized reference always carries the `Reference` wrapper: `{"Reference": ["morphir/SDK:list#list", "a"]}` | `TupleType` and `ReferenceType` in the schema, `document-tree-files.md`, bead `morphir-j442` (closed 2026-08-30) |
| Access on a definition may be flattened: `{"access": "Public", "TypeAliasDefinition": {...}}` validates alongside the tag form `{"Public": {...}}` and the legacy `{access, value}` form | `AccessControlled` in the schema (third `anyOf` arm), bead `morphir-j442` |
| `{"OpaqueTypeSpecification": {}}` is valid | Schema, bead `morphir-j442` |
| Literal tags: `IntegerLiteral` replaces `WholeNumberLiteral`; decoders accept both | Schema, `whats-new.md`, Rust `literal.rs`, BDD `v4_compliance.feature` |
| Document tree: root file is `manifest.json` or `manifest.yaml`; definition files sit flat in the module directory as `NAME.type.EXT` and `NAME.value.EXT`; one profile per tree | `document-tree-files.md`, tree schema, and the CLI writer in `ecosystem/morphir-rust/.../document_tree.rs` (`pkg/{package}/{module}/{name}.type.{extension}`) |
| Both published v4 examples validate against the v4 schema, and all seven schemas pass the metaschema | `mise run examples:validate` and `mise run schema:validate` on 2026-09-03 |

## Live contradictions

Each row names the conflict, the sources on each side, and the resolution the stabilization rule implies. Rows
marked *mechanical* need no decision; rows marked *decision* appear again under [Open decisions](#open-decisions).

### Inside the schema

| Conflict | Side A | Side B | Resolution |
| -------- | ------ | ------ | ---------- |
| Bare array as a value | `Value` lists `type: array` as "Shorthand for List" | `ListValue` and `TupleValue` both say "Bare arrays are NOT allowed for values" | Decision. The design rationale for forbidding it (List and Tuple would be ambiguous) still holds, so the likely fix removes the arm. |
| `Hole`, `Native`, `External` missing from `Value` | The schema header, `whats-new.md`, the Rust `Value` enum, and the technical-writer checklist all list them as v4 value expressions | The `Value` `oneOf` has no arm for any of them | Mechanical once the field layout is chosen; see the vocabulary decision. |
| Attributes on values | `ValueAttributes` is defined, and the spec's own examples write `"attributes": {}` on `Variable`, `Apply`, `Reference`, `Field`, `Tuple`, `Constructor` | Only `LiteralValue` and `LiteralPattern` accept an `attributes` member; every other value wrapper is `additionalProperties: false` or a bare string | Decision. Either every value node gains an expanded form with attributes, or the spec examples drop them. |
| Legacy name array item pattern | `morphir-ir-v4.yaml` line 64: `^[a-z0-9]+$` | `morphir-ir-v4-document-tree-files.yaml` line 41: `^[a-z][a-z0-9]*$` | Mechanical. Pick one; the corpus decides. |
| `FileStem` pattern | `morphir-ir-v4.yaml`: allows a `__[0-9a-f]{8}` truncation suffix | `naming-conformance.json` `notes`: no suffix; tree schema: `FileStem` absent | Mechanical. Define `FileStem` once in the tree schema with the suffix. |
| Document-tree schema has no root | The file is a definitions-only catalog; nothing composes the four file kinds into a root | `document-tree-files.md` describes four validatable file kinds | Mechanical. Bead `morphir-bx6v`. Its metaschema finding is already fixed; the missing root is not. |
| Document-tree bodies are unvalidated | `TypeDefinition`, `TypeSpecification`, `ValueDefinition` in the tree schema are `additionalProperties: true` stubs with a comment "these would be `$ref` in practice" | The core schema defines them fully | Decision. Cross-file `$ref` to the core schema, or a build step that inlines it. |

### Between schema and prose

| Conflict | Prose says | Schema says | Resolution |
| -------- | ---------- | ----------- | ---------- |
| Bare array in type position | `whats-new.md` "Type Shorthand": an array is a parameterized type with the FQName first | A bare array is a `Tuple`; `Reference` never accepts a bare array | Mechanical. `whats-new.md` contradicts its own table twenty lines later and the closed decision. |
| Access control | `docs/spec/ir/schemas/v4/index.md` "Access Control: Same as V3", requiring `access` and `value` | Three accepted forms, tag form canonical | Mechanical. |
| Type expression field names | `index.md`: `Reference {fqname, args}` as the only form, `Function {argument, return}` | `Function {argumentType, returnType}`; `Reference` has four forms | Mechanical. |
| `IntegerLiteral` spelling | `docs/spec/draft/values.md` writes `IntLiteral` in every example; `whats-new.md` writes `{"IntegerLiteral": {"value": 42}}` as the v4 form | `{"IntegerLiteral": 42}` canonical; `IntLiteral` does not exist | Mechanical. |
| Tuple and List canonical form | `docs/spec/draft/types.md` and `values.md`: `{"Tuple": {"elements": [...]}}` is the form | `{"Tuple": [...]}` canonical; `elements` and `items` are the expanded forms | Mechanical. |
| Parameterized types in draft examples | `docs/spec/draft/types.md` lines 210, 344, 458 write bare arrays for `Maybe String` and `List a` | Bare array is a Tuple | Mechanical. |
| Retired name encoding | `docs/spec/ir/schemas/v4/index.md`, `whats-new.md`, `docs/spec/draft/modules.md`, `docs/design/draft/ir/naming.md`, the technical-writer checklist | Uppercase segments | Mechanical. Decision 0001 lists the files; `index.md` was not on its list. |
| Schema file layout | `docs/spec/draft/schemas.md` describes a nine-file `schemas/v4/{common,classic,tree}` hierarchy and a `format.json` | Two files exist, and the root file is `manifest.json` | Mechanical. The hierarchy was never built. |
| Distribution root layout | `docs/spec/draft/distribution.md` and `docs/design/draft/ir/distributions.md`: `format.json`, `types/` and `values/` subdirectories, `session.jsonl`, `deco/` | Flat module directory and `manifest.json`, as the CLI writes | Mechanical for the file name and layout. `session.jsonl` and `deco/` are a scope decision. |
| Migration guide encoding | `docs/spec/ir/schemas/migration-guide.md` V3 to V4 describes v4 as tagged arrays with attribute objects: `["Variable", {source, constraints, extensions}, name]`, and names as `"value-in-u-s-d"` | Wrapper objects, uppercase initialisms | Rewrite. The page describes a format that never existed. |
| Migration guide loss table | Lists `Constructor`, `List`, `FieldFunction`, `LetRecursion`, `Destructure`, `UpdateRecord`, `Unit` as v4-only and omits `Hole`, `Native`, `External`; treats V4 to V3 as lossy but possible | All seven exist in v3; the CLI refuses V4 to V3 with `unsupported_v4_downgrade` | Rewrite. Bead `morphir-diwy` owns the downgrade rules. |
| Module documentation | `docs/spec/ir/schemas/v4/index.md` shows `{doc, value}` nested under the access wrapper; `docs/design/draft/ir/packages.md` says no module docs | Schema accepts `doc` flattened beside `access` and the variant, and also the nested `{doc, value}` form; `ModuleDefinition.doc` exists | Decision on the canonical spelling; the nested form is the odd one out. |
| SDK package name | Spec pages and both examples write `morphir/sdk` | names-0004 decodes the legacy array to `morphir/SDK`, a different name under decision 0001 | Decision. Case names-0006, bead `morphir-ir-v4-stabilize.1`. |

### Between schema and implementations

| Conflict | Implementation | Schema | Resolution |
| -------- | -------------- | ------ | ---------- |
| Bare array in type position | Rust `serde_tagged.rs` `visit_seq`: an array whose first element contains `:` and `#` decodes as a parameterized `Reference`; no branch decodes a bare array as a `Tuple` | Bare array is a `Tuple` | Bug. The decoder implements the rule the closed decision rejected, so `["morphir/SDK:basics#int", "morphir/SDK:string#string"]` means different things in Rust and in the schema. |
| Attribute member name | Rust `serde_v4.rs` writes `attrs`; morphir-ui accepts `attributes` or `attrs` and locks `attrs` in a test | `attributes` | Decision on the vocabulary, then align. |
| `IfThenElse` members | Rust writes `condition`, `thenBranch`, `elseBranch` | `condition`, `then`, `else` | Same decision. |
| `Function` type members | Rust writes `arg`, `result` | `argumentType`, `returnType` | Same decision. |
| `Field` members | Rust writes `target`, `name`; spec examples write `subject`, `fieldName` | `target`, `name` | Same decision. |
| `LetDefinition` members | Spec examples write `valueName`, `valueDefinition`, `inValue` | `name`, `definition`, `in` | Same decision. |
| `Constructor` and `Tuple` expanded forms | Spec examples write `{"Constructor": {"attributes", "fqname", "args"}}` and `{"Tuple": {"attributes", "elements"}}` | `Constructor` is a bare FQName; `Tuple` forbids extra members | Same decision. |
| V4 to V3 downgrade | CLI refuses it | Migration guide documents it | Bead `morphir-diwy`. |
| Third v4 schema | `ecosystem/morphir-rust/schemas/morphir-ir-v4.json` is schemars-generated: `formatVersion` is any unsigned integer, so it admits `0` and rejects `"4.0.0"`; access is legacy-only | Spec schema | Mechanical. Delete it or generate it from the spec schema and drift-check it. |
| `pathBudget` and `fileNames` | Decision 0001 requires writers to set `pathBudget` and lets a module carry `fileNames` | Tree schema: `pathBudget` optional with a default, `fileNames` absent from `ModuleManifestFile` | Mechanical. Apply the decision's consequences 6 and 7 to the schema. |

### Fixtures and gates

| Gap | State on 2026-09-03 |
| --- | ------------------- |
| `tests/bdd/fixtures/ir/v4/v4-library-distribution.json` | A v3 tagged-array payload stamped `formatVersion: 4`. The Rust copies at `crates/integration-tests/fixtures/ir/v4/` and in morphir-core already carry the v4 object form; the BDD copy was never updated. |
| `fixtures:validate` | Its two fixture directories do not exist, so it validates nothing and returns success. |
| `mise run check` | No CI job runs it. The `docs` job runs one script that returns success on every path, and `tests/bdd/**` matches no path filter. |
| `examples:validate` | Passes, but does not scan `docs/spec/ir/fixtures/`. |
| `website/scripts/validate-migrated-ir.js` | Manual only; no task or job invokes it. |
| `website/static/ir/examples/v4/books-and-records-example.json` | Decodes in morphir-ui only after the retired `product-(i-d)` spelling is replaced; GitHub issue #793 owns the policy. |

## Open decisions

These cannot be closed by editing prose. Each needs a maintainer decision, and each has a bead.

1. **Value node vocabulary.** One table of member names for every value node, and one rule for where
   `attributes` may appear. Today the schema, the Rust encoder, morphir-ui, and the spec examples use four
   overlapping vocabularies. The schema's names are the least surprising candidate because they are shortest and
   already validate the examples. Whatever is chosen, `Hole`, `Native`, and `External` are added to `Value` in the
   same change.
2. **Bare arrays as values.** Keep the `Value` array shorthand for `List`, or delete it as the `ListValue` and
   `TupleValue` notes require. The design's reasoning favors deletion.
3. **Module and definition documentation cardinality.** Flattened `doc` beside `access` and the variant, or the
   nested `{doc, value}` wrapper. The tree schema, the CLI writer, and both examples use the flattened form.
4. **Document-tree validation strategy.** Cross-file `$ref` from the tree schema to the core schema, or inline the
   core definitions at build time. Until one is chosen, `*.type.*` and `*.value.*` bodies validate against nothing.
5. **Scope of design-only features for 4.0.0.** `DocumentLiteral`, layered decorations under `deco/`, `$meta`,
   `$ref`, and `session.jsonl` exist only in the design documents. Each either enters the schema or is marked as
   post-4.0.
6. **Exact-release support table.** The format-version contract's reference table is `3.0.0` and `4.0.0`, and
   distributions-0001 pins that a reader rejects `"4.1.0"` with `unsupported_format_version_revision`. What remains
   open, in bead `morphir-ir-v4-stabilize.8`, is where each implementation publishes its own table and what changes
   when a `4.1.0` revision is actually specified.
7. **Legacy-name compatibility boundary.** GitHub issue #793: migrate the books fixture to `product-ID`, or define
   a documented compatibility rule without weakening the canonical parser.
8. **Naming codec home.** [Decision 0003](/decisions/0003-the-naming-codec-is-modelled-in-morphir.md) is still
   Proposed, and its own unresolved section asks where the Morphir model lives and whether the Elm frontend can
   emit v4 at all.

## Alternatives considered

**Treat the design documents as the tiebreak.** Rejected. Their status table marks nothing Approved, and the one
place an implementation followed them over the schema (the Rust bare-array decoder) is now a bug against a closed
decision.

**Treat the Rust implementation as the tiebreak.** Rejected. It writes member names the schema rejects, and the
morphir-ui decoder had to grow a second spelling to read its output. An implementation cannot be the reference for
a format two other implementations must read.

**Rewrite the specification draft and design tree first, then fix the schema.** Rejected for ordering. The draft
pages are the most stale source, and rewriting them before the vocabulary decision would mean rewriting them twice.
The mechanical prose corrections in this note are limited to statements that already have a decision behind them.

## Unresolved

The tiebreak has moved from the schema to the corpus, and the specification of 2026-09-04 makes the schema a
generated artifact of the TypeScript codecs. What remains unresolved is the order in which a Morphir metamodel, if
one is written, replaces the TypeScript model as the root; nothing in the corpus depends on which comes first.

How often the vocabulary conflicts bite real users is unmeasured. Every v4 artifact in circulation today was written
by the Rust CLI, so the Rust vocabulary is what exists on disk, and changing the encoder without a migration note
would strand those files.

## The Morphir Compatibility Kit

`spec/ir/mck/README.md` is the contract. MCK is the branded name of the conformance corpus the specification of 2026-09-04 describes; the two terms mean the same thing. Every settled row in the tables above has an active case; every
decision row about a spelling has a `pending` case naming its bead; rows about schema structure (document-tree
body validation, the `session.jsonl` and `deco` scope) have none, because they are not spellings. Case IDs
(`types-0003`) are stable and are the way beads and decision records cite the kit.

Rejection-only cases such as names-0003 are active. The Record spelling case (types-0005) and the whole-document
case (distributions-0004) are pending on the vocabulary decision, and the review of the seed kit found that the
v4 schema validates any content inside an access-controlled definition, so it never decided that spelling.

## Tracking

The beads epic `morphir-ir-v4-stabilize` groups the work. Its fourteen children map one to one onto the
*decision* rows above, the *mechanical* rows, and the fixture and gate gaps.

Applied on 2026-09-03 under `morphir-ir-v4-stabilize.9`: the bare-array, access-control, type-expression,
`IntegerLiteral`, Tuple and List canonical form, retired name encoding, nonexistent schema hierarchy, and
`manifest.json` rows in the prose tables are corrected in `docs/spec/ir/schemas/v4/`, `docs/spec/draft/`, and the
design tree. Still carrying the retired name encoding as narrative: `docs/design/draft/ir/naming.md`, which
already opens with a superseded banner. The migration guide is owned by its own bead. Existing beads it adopts: `morphir-vibt` (schema versus
examples), `morphir-bx6v` (tree schema root), `morphir-l2p9` (formatVersion contract), `morphir-diwy` (v4 to v3
migration), `morphir-19s6` (Insight, gated on this note). GitHub issues #792 to #795 audit the ingestion routes and
feed findings back here.

Related: [Decision 0001](/decisions/0001-name-canonicalization-and-initialism-encoding.md),
[Decision 0002](/decisions/0002-both-name-encodings-behind-one-switch.md),
[Decision 0003](/decisions/0003-the-naming-codec-is-modelled-in-morphir.md).
