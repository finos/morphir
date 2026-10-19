///|
pub(all) suberror GenerationError {
  Invalid(String, String, String)
} derive(Eq, Debug)

///|
pub extend GenerationError with Eq::{equal, not_equal}

///|
pub extend GenerationError with @debug.Debug::{to_repr}

///|
pub(all) struct NodeMetadata {
  node_id : String
  data : @ion.IonValue
}

///|
/// A portable generator contract, independent of engine and host types.
pub(all) struct Input {
  unit_id : String
  ir : @ir.IRFile
  metadata : Array[NodeMetadata]
  annotations : Array[@ion.SymbolToken]
  provenance : Array[@ion.IonValue]
}

///|
pub fn Input::new(unit_id : String, ir : @ir.IRFile) -> Input {
  { unit_id, ir, metadata: [], annotations: [], provenance: [], }
}

///|
pub(all) enum Content {
  Text(String)
  Binary(Bytes)
} derive(Eq, Debug)

///|
pub extend Content with Eq::{equal, not_equal}

///|
pub extend Content with @debug.Debug::{to_repr}

///|
pub(all) enum ArtifactRole {
  Source
  ModuleManifest
  PackageManifest
  Metadata
} derive(Eq, Debug)

///|
pub extend ArtifactRole with Eq::{equal, not_equal}

///|
pub extend ArtifactRole with @debug.Debug::{to_repr}

///|
pub(all) struct Artifact {
  path : String
  role : ArtifactRole
  content : Content
} derive(Eq, Debug)

///|
pub extend Artifact with Eq::{equal, not_equal}

///|
pub extend Artifact with @debug.Debug::{to_repr}

///|
/// A semantic requirement, not evidence that a dependency has been resolved.
pub(all) struct Dependency {
  module_name : String
  version : String
  api_profile : String
  semantic_pin : String
} derive(Eq, Debug)

///|
pub extend Dependency with Eq::{equal, not_equal}

///|
pub extend Dependency with @debug.Debug::{to_repr}

///|
pub(all) struct Project {
  module_name : String
  root : String
  members : Array[String]
  dependencies : Array[Dependency]
} derive(Eq, Debug)

///|
pub extend Project with Eq::{equal, not_equal}

///|
pub extend Project with @debug.Debug::{to_repr}

///|
pub(all) struct Symbol {
  fqname : String
  generated_name : String
  public : Bool
  source_node : String
  generated_node : String
  origins : Array[String]
} derive(Eq, Debug)

///|
pub extend Symbol with Eq::{equal, not_equal}

///|
pub extend Symbol with @debug.Debug::{to_repr}

///|
pub(all) struct Output {
  project : Project
  artifacts : Array[Artifact]
  symbols : Array[Symbol]
  invocations : Array[InvocationEntry]
  invocation_codecs : String
  invocation_types : Array[@execution.CustomType]
  invocation_rejections : Array[(String, String)]
  naming_style : NamingStyle
  naming_facts : @linked_metadata.Interpretation
  naming_allocations : Array[NamingAllocation]
  warnings : Array[@diagnostics.Warning]
}

///|
pub(all) struct Limits {
  max_declarations : Int32
  max_bytes : Int32
}

///|
pub fn Limits::default() -> Limits {
  { max_declarations: 10000, max_bytes: 4 * 1024 * 1024, }
}

///|
priv enum Scalar {
  SignedInt32
  BoundedInteger(String)
  Integer
  Float
  Float32
  Boolean
  Text
  Character
  Decimal
  Unit
} derive(Eq)

///|
priv struct Declaration {
  fqname : @ir.FQName
  doc : String?
  module_name : @ir.ModuleName
  public : Bool
  /// Visible to the other modules of the package: the value's own access is Public.
  exposed : Bool
  output : Lowered
  inputs : Array[(@ir.Name, Lowered)]
  body : @ir.Value
}

///|
priv enum Lowered {
  Atom(Scalar)
  Product(Array[Lowered])
  Shape(String, Array[(@ir.Name, Lowered)])
  Arrow(Lowered, Lowered)
  Sequence(Lowered)
  Optional(Lowered)
  Outcome(Lowered, Lowered)
  Nominal(@ir.FQName)
} derive(Eq)

///|
priv struct TypeEntry {
  definition : @ir.TypeDefinition
  public : Bool
  /// The type's own access is Public, whatever the module's access.
  exposed : Bool
}

///|
priv struct ConstructorEntry {
  output : Lowered
  inputs : Array[Lowered]
  public : Bool
  /// Visible to the other modules of the package: the type and the constructors are Public.
  exposed : Bool
  module_name : @ir.ModuleName
}

///|
priv struct Lowering {
  types : Map[@ir.FQName, TypeEntry]
  constructors : Map[@ir.FQName, ConstructorEntry]
  values : Map[@ir.FQName, Declaration]
  shapes : Map[String, Array[(@ir.Name, Lowered)]]
  exported_shapes : Map[String, Bool]
  /// Types that are not `public` but that a `pub` signature or a `pub` type names: they are emitted abstract.
  abstract_types : Map[@ir.FQName, Bool]
  imports : Map[String, Bool]
  source_extensions : Map[String, Bool]
  names : TargetNames
  mut locals : LocalNames?
}
