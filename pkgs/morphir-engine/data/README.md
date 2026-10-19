# Portable pipeline data boundaries

`finos/morphir-engine/data` supplies registered codecs for a typed `IRUnit` and
engine-owned Ion metadata. It is callable from a memory snapshot on native, JS,
WASM and WASM-GC. It performs no filesystem, network, process or compiler effects.

Morphir JSON remains supported. `morphir-json` reads the existing versioned JSON
schema and explicitly migrates it to current IR. `ion-text` and `ion-binary` read
the profile below into the same typed contract. `Registry::checkpoint` defaults
to Ion binary. Selecting JSON as a source does not change that default.

`morphir-yaml` reads the bounded normative YAML profile into the same typed IR.
Use the closed `ModelFormat` domain at file and command boundaries:
`ModelFormat::from_control`, `infer_path`, `codec_id` and `is_binary`.
`decode_model(format, bytes, unit_id~, limits~)` validates UTF-8 and dispatches
through shared codecs. `decode_model_tree(files, unit_id~, limits~)` accepts
relative paths and captured bytes for qualified v4/v3.1 trees. It bounds the
whole capture and ignores binary sidecars outside the physical tree profile.
Adapters check `model_tree_file_limit` before inserting captured files.
See the [YAML package](../../morphir-ir/yaml/README.md) for resource budgets.
YAML encoding is not implemented; retain original bytes or export normalized JSON.

```moonbit
let registry = @data.Registry::new()
let unit = registry.decode("morphir-json", {
  unit_id: "Pricing",
  content: Text(json_source),
})
let checkpoint = registry.checkpoint(unit) // Binary(Bytes), never UTF-8 text
let restored = registry.decode("ion-binary", {
  unit_id: "Pricing",
  content: checkpoint,
})
```

`Registry::open_checkpoint(codec, content)` opens a self-contained saved model.
For Ion it adopts the embedded logical unit ID, then applies the same strict
profile, metadata and budget validation as `decode`. JSON has no embedded unit
identity and receives the local default `workbench`. This logical identity grants
no filesystem or provider authority. Use `decode` when the caller already knows
and needs to enforce the expected unit ID.

`Registry::inspect_checkpoint(codec, content)` also returns the input checkpoint's
`original_format_version` as a validated `FormatVersion`, alongside the migrated
`unit`. Both opening methods use the same profile, metadata and resource checks.
For Ion, the source format is read from the embedded IR before migration. It is
independent of the Ion encoding, envelope profile and current semantic version.
The caller must retain original bytes separately. This result does not identify
a provider response as an original file or grant a retained-model handle.

The module depends on the exact registry release `moonrockz/ion@0.5.0`, using its
synchronous annotated value, text and binary packages. Async streaming is not
part of this portable callback contract.

The Ion readers reject containers nested deeper than 128 levels, even when the
registry's `max_depth` is higher. This reader ceiling is separate from the
registry's tree budget. Both `decode` and `open_checkpoint` report the reader's
`LimitExceeded` error as `data.tree_limit`. The library's stack-safe walkers and
writers do not provide a memory bound; the registry still checks its own budgets.

`IRUnit::validate(limits?)` validates rich source-frontend output before processing.
It checks the envelope profile, duplicate metadata, tree depth/value budgets,
metadata ownership against the distribution's stable node IDs, and the canonical
binary Ion byte budget. These are validation limits; serialization allocates before
the byte check and does not provide a streaming memory bound. Codec import/export
behavior remains governed by the selected registry format.

## IR-unit profile

### Conceptual graph adapter

`IRUnit::with_conceptual_graph(Graph)` attaches the complete draft conceptual
graph at `unit:<id>` using the existing metadata entry. It refuses an occupied
owner with `conceptual.metadata_owner_conflict` and leaves the input unchanged.
`IRUnit::conceptual_graph()` reads that owner; graph-free legacy units return
`None`. A recognized malformed or unsupported conceptual profile raises an error.
Graph entity IDs stay inside the graph and never become IR metadata owners.

`IRUnit::conceptual_specification()` extracts a Library's public signatures,
retaining the entire graph, annotations, provenance and valid sidecar metadata.
It hides private constructors and excludes private declarations. A public
declaration without a representable signature or a sidecar whose owner disappears
causes `data.lossy_conversion`; the adapter does not drop that data. Existing
Specs pass through. Application projection requires a separate linking policy
and is unsupported here. Projection does not lower conceptual declarations or
interpret their traits, and retained `projectionGaps` remain visible.

These methods use the existing `morphir-pipeline-v1` carrier and registered codecs.
Both Ion codecs retain the rich graph. Bare `morphir-json` export continues to
refuse metadata loss. They add no MEP tuple or model envelope. See the
[model API and limits](../../morphir-conceptual/model/README.md).

### Wire shape

The initial `morphir-pipeline-v1` contract is `ir-unit`. It keeps the profile
version separate from the nested IR format version and Ion 1.0 encoding. Text and
binary carry the same value model. The source snapshot supplies an expected
logical unit ID; an envelope containing another ID is refused.

```ion
morphir_pipeline::{
  profile: "morphir-pipeline-v1",
  contract: "ir-unit",
  unit_id: "Pricing",
  ir: {
    formatVersion: 4,
    distribution: {
      Library: {
        packageName: "pricing",
        dependencies: {},
        def: {modules: {}}
      }
    }
  },
  metadata: [
    {node_id: "value:Pricing.quote/body", data: hint::12.340d0}
  ]
}
```

An envelope must contain the `morphir_pipeline` annotation. Additional ordered
annotations are retained. Schema records reject duplicate/unknown fields.
Metadata records have unique, nonempty node IDs and an unrestricted Ion `data`
value, subject to budgets. That value retains annotations, duplicate struct
fields, exact decimals, typed nulls, timestamps, symbols, blobs/clobs and other
Ion kinds. IDs are caller-supplied semantic identities, not array positions or
filesystem paths. This slice supports identity processing. Structural rewrites
need the separately planned lineage and metadata policy contract.

The nested `ir` follows the supported Morphir IR wire shape. It reuses the existing
validated versioned IR codecs through an explicit schema mapping. Rich metadata
never goes through a JSON projection or the JSON-shaped `Data` extension model.
Native Ion integers retain arbitrary magnitude. A numeric JSON lexeme whose
spelling could change, including `-0`, decimal scale or exponents, has the explicit
representation `morphir_json_number::"1e-400"`. It is validated as a JSON number
before semantic decoding. Canonical integers use native Ion integers. Decimal
literal strings retain their original spelling under the existing IR schema.

Unsupported annotations or richer kinds inside the semantic `ir` subtree are
refused, rather than silently discarded. Put rich engine metadata in `metadata`.
This first profile does not automatically extract annotations from arbitrary IR
nodes or extend the current semantic IR vocabulary. JSON object field order is
not a semantic identity; the Ion semantic subtree is emitted in sorted field
order for deterministic checkpoints.

## Selection and diagnostics

`Registry::register` adds a named codec with typed decode/encode callbacks.
Duplicate IDs fail. A binary codec requires `Binary(Bytes)` and a text codec
requires `Text(String)`; there is no implicit encoding or format fallback.
Callbacks are trusted local components and receive the configured limits.
Registry checks also apply to their accepted results and output byte sizes.

`morphir-json` writes standard current Morphir JSON. It refuses units containing
engine metadata or additional envelope annotations with `data.lossy_conversion`.
A JSON-only component uses this semantic representation while the engine retains
the native Ion sidecar through its component/lineage adapter. The project CLI
selects these boundaries explicitly.

Errors have a stable code and detail in `BoundaryError::Invalid`. Existing IR
codec/version diagnostics are retained, including migration failures. Boundary
codes include `data.profile_mismatch`, `data.unit_mismatch`,
`data.encoding_mismatch`, `data.duplicate_field`, `data.profile_value_unsupported`,
`data.symbol_catalog_missing`, `data.unknown_codec`, and `data.codec_conflict`.
Unresolved shared-symbol imports require a catalog and fail explicitly in this
self-contained profile. Invalid Unicode is refused rather than replaced on write.

## Budgets and acceptance

Defaults are 4 MiB per source/output, depth 128, and 100,000 values/annotations.
Byte limits run before decoding and after encoding. Tree budgets apply to accepted
envelopes and before Ion emission. The synchronous Ion parsers construct a value
tree before its depth/value validation; these budgets do not promise bounded
parser allocation, interruption, or a streaming security sandbox. Parser-level
depth/number limits and host streaming are separate work. Public typed IR is
trusted application data and uses the existing IR traversal/codec rules.

The focused tests verify equivalent JSON/Ion input, migration, semantic IR and
exact-number preservation, rich metadata text/binary round trips, loss refusal,
registration conflicts, malformed input, identity checks, and byte/tree budgets
on all four portable targets:

```sh
mise exec -- moon test -p finos/morphir-engine/data --target all
```

An in-memory example is runnable with:

```sh
mise exec -- moon run pkgs/morphir-engine/data/examples --target native
```

The engine and CLI now support filesystem byte I/O, configured checkpoints,
component lineage, generated projects and explicit build validation. Arbitrary
annotated semantic IR imports remain outside this envelope profile.

Typed components retain the engine's Ion metadata sidecar. A JSON-only component
receives the explicit semantic projection from `semantic_json`, which is a
standard current Morphir JSON file. It returns semantic IR and optional lineage;
it never receives a JSON encoding of the rich sidecar. Whole-unit JSON export
still refuses metadata, additional annotations or rewrite provenance loss.

Structural rewrites require complete lineage. Every source identity is retained
or explicitly removed; every output identity is retained or derived from named
source identities. Retained metadata preserves the original Ion value. Derived
metadata uses a registered policy. The default `retain` policy refuses inherited
metadata on derived nodes; `copy-single-origin` copies one annotated origin and
refuses implicit merges. Ordered unknown annotations remain intact. Removed
metadata is recorded in an Ion provenance event instead of disappearing.

`fill_lineage(before, after)` builds the lineage of a rewrite that changes only
attributes and the variables of `before` that carry the unknown marker, such as
an inference fill. It joins nodes by logical path
(`@identities.logical_nodes`), so a node keeps its identity when its compact
JSON form becomes expanded:

- A node with the same logical path in both files is retained. A replaced
  marker variable is retained, because its replacement has its logical path.
- A node only in `after` is derived from the nearest node above it that
  `before` has: a new attribute node from its owner, a node under a replaced
  marker from the marker.
- A node only in `before` is removed.

Any other difference raises `data.not_attribute_only` with the logical path.
`MetadataPolicy::no_derived()` attaches no metadata to a derived node. Inference
uses it, because a type that a fill writes has no metadata of its own; the
`retain` policy would refuse the derived nodes of an annotated owner.

The optional `provenance` list in the pipeline profile preserves native Ion
rewrite records through checkpoints and into generated symbol files. Existing
profile files without it remain supported. `finos/morphir-ir/identities` supplies
stable declaration IDs and JSON-pointer child suffixes; pair-array indices denote
positions, so reordering requires declared lineage. Identity traversal is bounded
to depth 128 and 100,000 identities.
