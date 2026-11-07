///|
pub const LEGACY_BOOL_PROFILE : String = "moonbit-model-bool-v1"

///|
pub const PARSER_VERSION : String = "0.4.5"

///|
pub(all) struct Input {
  unit_id : String
  package_name : String
  module_name : String
  source : String
}

///|
#derive(Eq, Debug)
pub(all) struct Limits {
  max_bytes : Int32
  max_parameters : Int32
  max_depth : Int32
  max_expressions : Int32
}

///|
pub fn Limits::default() -> Limits {
  {
    max_bytes: 65536,
    max_parameters: 16,
    max_depth: 64,
    max_expressions: 4096,
  }
}

///|
#derive(Debug)
pub(all) struct Diagnostic {
  code : String
  detail : String
  source : @ir.SourceLocation?
}

///|
#derive(Debug)
pub(all) suberror FrontendError {
  Invalid(Diagnostic)
}

///|
pub(all) struct NodeMetadata {
  node_id : String
  data : @ion.IonValue
}

///|
/// Applications adapt this contract to IRUnit without an engine dependency here.
pub(all) struct Output {
  unit_id : String
  ir : @ir.IRFile
  entry : @ir.FQName
  public : Bool
  metadata : Array[NodeMetadata]
  annotations : Array[@ion.SymbolToken]
  provenance : Array[@ion.IonValue]
  warnings : Array[@diagnostics.Warning]
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend FrontendError with @debug.Debug::{to_repr}
