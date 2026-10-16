///|
pub const TARGET_NAMES_PREDICATE : String = "morphir://ir/pkg/morphir/naming?format=4.1.0#/module/naming/value/target-names"

///|
pub const ADAPTER_PROFILE : String = "morphir_linked_metadata_v1"

///|
pub(all) suberror MetadataError {
  Invalid(String, String, String)
} derive(Eq, Debug)

///|
pub extend MetadataError with Eq::{equal, not_equal}

///|
pub extend MetadataError with @debug.Debug::{to_repr}

///|
pub(all) struct TargetNames {
  frontend : Map[String, String]
  backend : Map[String, String]
} derive(Eq, Debug)

///|
pub extend TargetNames with Eq::{equal, not_equal}

///|
pub extend TargetNames with @debug.Debug::{to_repr}

///|
/// Each authored carrier stays in the original Ion payload. This identifies the
/// assertion consumed by this interpreter, not a new authored assertion.
pub(all) struct Assertion {
  holder : String
  document : String
  carrier : String
  subject : String
  predicate : String
  property : String
  ordinal : Int32
  object_ordinal : Int32
}

///|
pub(all) struct NamingFact {
  owner : String
  names : TargetNames
  assertions : Array[Assertion]
  provider_revision : String
}

///|
pub(all) struct MetadataEntry {
  node_id : String
  data : @ion.IonValue
}

///|
/// The trusted host must freshly authenticate and restore the signed Library
/// before returning this projection. The core has no signature verifier or
/// ambient registry. Wire metadata cannot supply this capability.
/// `core` is the supported semantic projection; `format` is the native release.
pub(all) struct RestoredLibrary {
  core : @ir.IRFile
  format : String
  revision : String
  document : String
  document_metadata : @ion.IonValue
}

///|
pub(all) struct ContextDocument {
  url : String
  bytes : Bytes
  sha256 : String
}

///|
/// Host capabilities perform authenticated Library restoration and bounded
/// context acquisition. A digest checks context bytes; it does not admit a provider.
pub(all) struct Capabilities {
  restore_library : ((String) -> RestoredLibrary raise)?
  load_context : ((String, String) -> ContextDocument raise)?
  target_names_interpreter : Bool
  provider_observer : ProviderObserver
}

///|
pub fn Capabilities::unavailable() -> Capabilities {
  {
    restore_library: None,
    load_context: None,
    target_names_interpreter: false,
    provider_observer: ProviderObserver::noop(),
  }
}

///|
pub(all) struct Interpretation {
  facts : Array[NamingFact]
  unvalidated_predicates : Array[String]
}
