///|
/// Stable boundary diagnostics. IR codec codes are retained unchanged.
pub(all) suberror BoundaryError {
  Invalid(String, String)
} derive(Eq, Debug)

///|
pub extend BoundaryError with Eq::{equal, not_equal}

///|
pub extend BoundaryError with @debug.Debug::{to_repr}

///|
/// Binary content is never implicitly interpreted as UTF-8 text.
pub(all) enum Content {
  Text(String)
  Binary(Bytes)
} derive(Eq, Debug)

///|
pub extend Content with Eq::{equal, not_equal}

///|
pub extend Content with @debug.Debug::{to_repr}

///|
/// IDs are logical identities supplied by a caller, not host filesystem paths.
pub(all) struct SourceSnapshot {
  unit_id : String
  content : Content
} derive(Eq, Debug)

///|
pub extend SourceSnapshot with Eq::{equal, not_equal}

///|
pub extend SourceSnapshot with @debug.Debug::{to_repr}

///|
pub(all) struct NodeMetadata {
  node_id : String
  data : @ion.IonValue
} derive(Debug)

///|
pub extend NodeMetadata with @debug.Debug::{to_repr}

///|
/// Rich metadata stays outside the JSON-shaped semantic IR extension model.
/// Structural transforms need a separate lineage contract; identity processing
/// can return this value unchanged.
pub(all) struct IRUnit {
  id : String
  distribution : @ir.IRFile
  metadata : Array[NodeMetadata]
  annotations : Array[@ion.SymbolToken]
  provenance : Array[@ion.IonValue]
} derive(Debug)

///|
pub extend IRUnit with @debug.Debug::{to_repr}

///|
pub fn IRUnit::new(
  id : String,
  distribution : @ir.IRFile,
  metadata~ : Array[NodeMetadata] = [],
) -> IRUnit {
  {
    id,
    distribution,
    metadata: metadata.copy(),
    annotations: [@ion.SymbolToken::new("morphir_pipeline")],
    provenance: [],
  }
}

///|
/// Validate a source frontend's rich output before components or serialization.
pub fn IRUnit::validate(
  self : IRUnit,
  limits~ : Limits = Limits::default(),
) -> Unit raise {
  if limits.max_bytes <= 0 || limits.max_depth < 0 || limits.max_values <= 0 {
    raise Invalid("data.invalid_limits", "Limits must be positive")
  }
  let envelope = write_envelope(self, limits)
  let owned = @identities.nodes(self.id, self.distribution)
  for entry in self.metadata {
    if !owned.contains(entry.node_id) {
      raise Invalid(
        "data.invalid_identity",
        "Unowned metadata node: " + entry.node_id,
      )
    }
  }
  check_content(Binary(@ion_binary.write_binary_value(envelope)), limits)
}

///|
/// These are acceptance/traversal budgets, not a streaming-parser guarantee.
pub(all) struct Limits {
  max_bytes : Int32
  max_depth : Int32
  max_values : Int32
} derive(Eq, Debug)

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub fn Limits::default() -> Limits {
  { max_bytes: 4 * 1024 * 1024, max_depth: 128, max_values: 100000, }
}

///|
pub(all) struct Codec {
  decode : (SourceSnapshot, Limits) -> IRUnit raise
  encode : (IRUnit, Limits) -> Content raise
}

///|
pub struct Registry {
  priv codecs : Map[String, Codec]
  priv limits : Limits
}

///|
pub const PROFILE : String = "morphir-pipeline-v1"
