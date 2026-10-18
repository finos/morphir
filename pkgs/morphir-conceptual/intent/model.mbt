///|
pub(all) struct Entity {
  identity : Snapshot
  name : String
  source_refs : Array[SourceRef]
  content : Content
  descriptive : @ion.IonValue?
}

///|
pub(all) enum Content {
  Intent(String, String?)
  Requirement(Category, String, @ion.IonValue?)
  SourceFragment(SourceRef)
  Declaration(DeclarationRole, ResolvedRef?)
  Contract(ResolvedRef, ClauseKind, Expression)
  Scenario(@ion.IonValue)
  Implementation(Snapshot)
  Claim(Claim)
  Evidence(Evidence)
}

///|
/// These records are an inspection projection of constructed M1 inputs, not a
/// decoder or complete M1 structural validator. Fields outside this link slice
/// remain the caller's responsibility; descriptive rich values stay opaque.
pub(all) struct Model {
  identity : Snapshot
  sources : Array[Source]
  entities : Array[Entity]
  relationships : Array[Relationship]
  dependencies : Array[Model]
}

///|
pub(all) enum DeclarationRole {
  Function
  Type
  Field
  Parameter
  Result
}

///|
pub(all) enum ClauseKind {
  Refinement
  Invariant
  Precondition
  Postcondition
}

///|
pub(all) enum Expression {
  UnresolvedExpression(NonemptyText)
  ResolvedExpression(Id, @ion.IonValue)
}

///|
pub(all) enum EntityKind {
  IntentKind
  RequirementKind
  SourceFragmentKind
  DeclarationKind
  ContractKind
  ScenarioKind
  ImplementationKind
  ClaimKind
  EvidenceKind
} derive(Eq, Debug)

///|
pub extend EntityKind with Eq::{equal, not_equal}

///|
pub extend EntityKind with @debug.Debug::{to_repr}

///|
pub(all) enum EntityRef {
  Resolved(ResolvedRef)
  Unresolved(NonemptyText, EntityKind, NonemptyText)
}

///|
pub fn EntityRef::unresolved(
  locator : String,
  expected_kind : EntityKind,
  reason : String,
) -> EntityRef raise InvalidInput {
  Unresolved(
    NonemptyText::parse(locator),
    expected_kind,
    NonemptyText::parse(reason),
  )
}

///|
pub(all) enum Predicate {
  DerivedFrom
  Refines
  Formalizes
  GovernedBy
  Exercises
  Implements
  Supports
  Contradicts
} derive(Eq, Debug)

///|
pub extend Predicate with Eq::{equal, not_equal}

///|
pub extend Predicate with @debug.Debug::{to_repr}

///|
pub(all) struct Relationship {
  id : Id
  predicate : Predicate
  subject : ResolvedRef
  target : EntityRef
  source_refs : Array[SourceRef]
  descriptive : @ion.IonValue?
}

///|
fn Entity::kind(self : Entity) -> EntityKind {
  match self.content {
    Intent(_, _) => IntentKind
    Requirement(_, _, _) => RequirementKind
    SourceFragment(_) => SourceFragmentKind
    Declaration(_, _) => DeclarationKind
    Contract(_, _, _) => ContractKind
    Scenario(_) => ScenarioKind
    Implementation(_) => ImplementationKind
    Claim(_) => ClaimKind
    Evidence(_) => EvidenceKind
  }
}
