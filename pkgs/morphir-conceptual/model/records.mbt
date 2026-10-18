///|
pub const PROFILE : String = "morphir-conceptual/0.1.0-draft.1"

///|
pub const TRAITS_PROFILE : String = "morphir-traits/0.1.0-draft.1"

///|
pub const RECORD_VERSION : String = "0.1.0-draft.1"

///|
pub using @intent {
  type Id,
  type Revision,
  type Snapshot,
  type ResolvedRef,
  type SourceRef,
}

///|
pub(all) struct Diagnostic {
  code : String
  path : String
  related_path : String?
} derive(Eq, Debug)

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub(all) suberror ModelError {
  Invalid(Diagnostic)
} derive(Debug)

///|
pub extend ModelError with @debug.Debug::{to_repr}

///|
/// A lossless record view. Values returned to callers never alias its storage.
pub struct Record {
  priv value : @ion.IonValue
  priv fields : Map[String, @ion.IonValue]
  priv path : String
}

///|
pub fn Record::field(self : Record, name : String) -> @ion.IonValue? {
  self.fields.get(name).map(copy_value)
}

///|
pub fn Record::to_ion(self : Record) -> @ion.IonValue {
  copy_value(self.value)
}

///|
pub(all) enum EntityKind {
  Intent
  Requirement
  Concept
  DataElement
  SourceFragment
  Declaration
  Contract
  Scenario
  Implementation
  Claim
  Evidence
  Unknown(String)
} derive(Eq, Debug)

///|
pub extend EntityKind with Eq::{equal, not_equal}

///|
pub extend EntityKind with @debug.Debug::{to_repr}

///|
pub(all) enum Reference {
  Resolved(ResolvedRef)
  Unresolved(String, String, String)
} derive(Eq, Debug)

///|
pub extend Reference with Eq::{equal, not_equal}

///|
pub extend Reference with @debug.Debug::{to_repr}

///|
pub struct Entity {
  priv record : Record
  priv identity : Snapshot
  priv kind : EntityKind
  priv content : Record?
}

///|
pub fn Entity::identity(self : Entity) -> Snapshot {
  self.identity
}

///|
pub fn Entity::kind(self : Entity) -> EntityKind {
  self.kind
}

///|
pub fn Entity::record(self : Entity) -> Record {
  self.record
}

///|
pub fn Entity::content(self : Entity) -> @ion.IonValue {
  copy_value(self.record.fields["content"])
}

///|
pub fn Entity::content_field(self : Entity, name : String) -> @ion.IonValue? {
  match self.content {
    Some(r) => r.field(name)
    None => None
  }
}

///|
/// Each concern is independent; absence means that no fact was recorded.
pub fn Entity::concern(
  self : Entity,
  name : String,
) -> Record? raise ModelError {
  if !["elaboration", "definition", "recovery", "review", "implementation"].contains(
      name,
    ) {
    return None
  }
  self.record.fields
  .get(name)
  .map(v => record(v, self.record.path + "/" + name))
}

///|
pub(all) struct Fragment {
  anchor : Id
  text : String
}

///|
pub struct Source {
  priv record : Record
  priv id : Id
  priv fragments : Array[Fragment]
}

///|
pub fn Source::id(self : Source) -> Id {
  self.id
}

///|
pub fn Source::record(self : Source) -> Record {
  self.record
}

///|
pub fn Source::fragments(self : Source) -> Array[Fragment] {
  self.fragments.copy()
}

///|
pub struct Relationship {
  priv record : Record
  priv id : Id
  priv predicate : String
  priv subject : Reference
  priv target : Reference
}

///|
pub fn Relationship::id(self : Relationship) -> Id {
  self.id
}

///|
pub fn Relationship::predicate(self : Relationship) -> String {
  self.predicate
}

///|
pub fn Relationship::subject(self : Relationship) -> Reference {
  self.subject
}

///|
pub fn Relationship::target(self : Relationship) -> Reference {
  self.target
}

///|
pub fn Relationship::record(self : Relationship) -> Record {
  self.record
}

///|
pub struct TraitDefinition {
  priv record : Record
  priv identity : Snapshot
}

///|
pub fn TraitDefinition::identity(self : TraitDefinition) -> Snapshot {
  self.identity
}

///|
pub fn TraitDefinition::record(self : TraitDefinition) -> Record {
  self.record
}

///|
pub struct TraitApplication {
  priv record : Record
  priv identity : Snapshot
  priv definition : Reference
  priv provenance : Record
}

///|
pub fn TraitApplication::identity(self : TraitApplication) -> Snapshot {
  self.identity
}

///|
pub fn TraitApplication::record(self : TraitApplication) -> Record {
  self.record
}

///|
pub fn TraitApplication::definition(self : TraitApplication) -> Reference {
  self.definition
}

///|
pub fn TraitApplication::payload(self : TraitApplication) -> @ion.IonValue {
  copy_value(self.record.fields["payload"])
}

///|
pub fn TraitApplication::provenance(self : TraitApplication) -> Record {
  self.provenance
}

///|
/// Structural preservation is distinct from semantic validation and execution.
pub struct Graph {
  priv record : Record
  priv identity : Snapshot
  priv sources : Array[Source]
  priv entities : Array[Entity]
  priv relationships : Array[Relationship]
  priv capabilities : Array[Record]
  priv definitions : Array[TraitDefinition]
  priv applications : Array[TraitApplication]
  priv references : Array[(Reference, String)]
  priv source_refs : Array[(SourceRef, String)]
  priv records : Array[Record]
}

///|
pub fn Graph::identity(self : Graph) -> Snapshot {
  self.identity
}

///|
pub fn Graph::record(self : Graph) -> Record {
  self.record
}

///|
pub fn Graph::to_ion(self : Graph) -> @ion.IonValue {
  self.record.to_ion()
}

///|
pub fn Graph::sources(self : Graph) -> Array[Source] {
  self.sources.copy()
}

///|
pub fn Graph::entities(self : Graph) -> Array[Entity] {
  self.entities.copy()
}

///|
pub fn Graph::relationships(self : Graph) -> Array[Relationship] {
  self.relationships.copy()
}

///|
pub fn Graph::capabilities(self : Graph) -> Array[Record] {
  self.capabilities.copy()
}

///|
pub fn Graph::trait_definitions(self : Graph) -> Array[TraitDefinition] {
  self.definitions.copy()
}

///|
pub fn Graph::trait_applications(self : Graph) -> Array[TraitApplication] {
  self.applications.copy()
}

///|
pub fn Graph::entity(self : Graph, id : String) -> Entity? {
  for e in self.entities {
    if e.identity.id.value() == id {
      return Some(e)
    }
  }
  None
}

///|
fn fail(
  code : String,
  path : String,
  related_path~ : String? = None,
) -> Unit raise ModelError {
  raise Invalid({ code, path, related_path, })
}

///|
fn pointer(name : String) -> String {
  name.replace(old="~", new="~0").replace(old="/", new="~1")
}

///|
fn copy_value(value : @ion.IonValue) -> @ion.IonValue {
  let kind = match value.kind() {
    Blob(bytes) =>
      @ion.IonValueKind::Blob(Bytes::makei(bytes.length(), i => bytes[i]))
    Clob(bytes) =>
      @ion.IonValueKind::Clob(Bytes::makei(bytes.length(), i => bytes[i]))
    List(xs) => @ion.IonValueKind::List(xs.map(copy_value))
    Sexp(xs) => @ion.IonValueKind::Sexp(xs.map(copy_value))
    Struct(xs) =>
      @ion.IonValueKind::Struct(
        xs.map(f => @ion.Field::from_token(f.name(), copy_value(f.value()))),
      )
    other => other
  }
  @ion.IonValue::new(kind).with_annotations(value.annotations().copy())
}

///|
pub(all) enum TraitInterpretation {
  Descriptive
  Semantic(Array[Id])
}

///|
pub(all) enum Multiplicity {
  One
  Many
}

///|
pub(all) enum TraitTargetKind {
  ConceptTarget
  TypeTarget
  MemberTarget
  FunctionTarget
  OperationTarget
  ServiceBindingTarget
} derive(Eq)

///|
pub extend TraitTargetKind with Eq::{equal, not_equal}

///|
pub(all) enum TraitTarget {
  ModelTarget(Snapshot)
  ModuleTarget(Snapshot, String)
  EntityTarget(TraitTargetKind, Reference)
  ProfileTarget(TraitTargetKind, Id, Reference)
  UnknownTarget(Record)
}

///|
pub(all) enum Origin {
  Authored
  Imported
  Derived
}

///|
pub fn TraitDefinition::interpretation(
  self : TraitDefinition,
) -> TraitInterpretation raise ModelError {
  trait_interpretation(child(self.record, "interpretation"))
}

///|
pub fn TraitApplication::interpretation(
  self : TraitApplication,
) -> TraitInterpretation raise ModelError {
  trait_interpretation(child(self.record, "interpretation"))
}

///|
pub fn TraitDefinition::multiplicity(
  self : TraitDefinition,
) -> Multiplicity raise ModelError {
  match text(self.record, "multiplicity") {
    "one" => One
    "many" => Many
    _ => {
      fail("conceptual.unsupported_variant", self.record.path + "/multiplicity")
      abort("unreachable")
    }
  }
}

///|
pub fn TraitApplication::target(
  self : TraitApplication,
) -> TraitTarget raise ModelError {
  trait_target(child(self.record, "target"))
}

///|
pub fn TraitApplication::origin(
  self : TraitApplication,
) -> Origin raise ModelError {
  match text(self.provenance, "origin") {
    "authored" => Authored
    "imported" => Imported
    "derived" => Derived
    _ => {
      fail("conceptual.unsupported_variant", self.provenance.path + "/origin")
      abort("unreachable")
    }
  }
}
