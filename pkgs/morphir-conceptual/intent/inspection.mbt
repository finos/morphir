///|
pub(all) enum DiagnosticCode {
  DuplicateIdentity
  RelationshipKind
  MissingResolvedTarget
  ReferenceRevision
  MissingSourceFragment
  InvalidSource
  UnresolvedReference
  SourceUnpinned
  MissingFormalization
  MissingExamples
  MissingEvidence
  StaleEvidence
  InconclusiveEvidence
  ImplementationUnbound
  UnsupportedSemantics
} derive(Eq, Debug)

///|
pub extend DiagnosticCode with Eq::{equal, not_equal}

///|
pub extend DiagnosticCode with @debug.Debug::{to_repr}

///|
pub(all) struct Diagnostic {
  code : DiagnosticCode
  owner : Id
  path : String
}

///|
pub(all) struct Inspection {
  diagnostics : Array[Diagnostic]
}

///|
fn DiagnosticCode::is_error(self : DiagnosticCode) -> Bool {
  match self {
    DuplicateIdentity
    | RelationshipKind
    | MissingResolvedTarget
    | ReferenceRevision
    | MissingSourceFragment
    | InvalidSource => true
    _ => false
  }
}

///|
pub fn Inspection::has_errors(self : Inspection) -> Bool {
  self.diagnostics.any(d => d.code.is_error())
}

///|
fn model_closure(
  model : Model,
) -> (Array[(Model, String)], Array[(Snapshot, String)]) {
  let pending = [(model, "")]
  let found : Array[(Model, String)] = []
  let duplicates : Array[(Snapshot, String)] = []
  let mut index = 0
  while index < pending.length() {
    let (current, path) = pending[index]
    index += 1
    if found.any(entry => entry.0.identity == current.identity) {
      duplicates.push((current.identity, path))
    } else {
      found.push((current, path))
      for i, dependency in current.dependencies {
        pending.push((dependency, "\{path}/dependencies/\{i}"))
      }
    }
  }
  (found, duplicates)
}

///|
fn find_model(model : Model, identity : Snapshot) -> Model? {
  for (candidate, _) in model_closure(model).0 {
    if candidate.identity == identity {
      return Some(candidate)
    }
  }
  None
}

///|
fn resolve(
  model : Model,
  reference : ResolvedRef,
) -> Result[Entity, DiagnosticCode] {
  guard find_model(model, reference.model) is Some(owner) else {
    return Err(ReferenceRevision)
  }
  let found = owner.entities.filter(e => e.identity.id == reference.entity.id)
  if found.length() > 1 {
    return Err(DuplicateIdentity)
  }
  guard found.get(0) is Some(entity) else { return Err(MissingResolvedTarget) }
  if entity.identity != reference.entity {
    return Err(ReferenceRevision)
  }
  Ok(entity)
}

///|
fn Predicate::signature(self : Predicate) -> (EntityKind, EntityKind) {
  match self {
    DerivedFrom => (RequirementKind, SourceFragmentKind)
    Refines => (RequirementKind, IntentKind)
    Formalizes => (ContractKind, RequirementKind)
    GovernedBy => (DeclarationKind, ContractKind)
    Exercises => (ScenarioKind, ContractKind)
    Implements => (ImplementationKind, DeclarationKind)
    Supports | Contradicts => (EvidenceKind, ClaimKind)
  }
}

///|
fn relationship_error(
  model : Model,
  relationship : Relationship,
) -> DiagnosticCode? {
  let (expected_subject, expected_target) = relationship.predicate.signature()
  let subject = match resolve(model, relationship.subject) {
    Ok(e) => e
    Err(e) => return Some(e)
  }
  if subject.kind() != expected_subject {
    return Some(RelationshipKind)
  }
  match relationship.target {
    Unresolved(_, kind, _) =>
      if kind != expected_target {
        Some(RelationshipKind)
      } else {
        Some(UnresolvedReference)
      }
    Resolved(reference) => {
      let target = match resolve(model, reference) {
        Ok(e) => e
        Err(e) => return Some(e)
      }
      if target.kind() != expected_target {
        return Some(RelationshipKind)
      }
      match (relationship.predicate, subject.content, target.content) {
        (
          GovernedBy,
          Declaration(Function | Type, _),
          Contract(contract_subject, _, _),
        ) =>
          if contract_subject == relationship.subject {
            None
          } else {
            Some(RelationshipKind)
          }
        (GovernedBy, _, _) => Some(RelationshipKind)
        (Implements, _, Declaration(Function, _)) => None
        (Implements, _, _) => Some(RelationshipKind)
        _ => None
      }
    }
  }
}

///|
fn source_ref_valid(model : Model, reference : SourceRef) -> Bool {
  let sources = model.sources.filter(s => s.id == reference.source_id)
  sources.length() == 1 &&
  sources[0].fragments.filter(f => f.anchor == reference.anchor).length() == 1
}

///|
fn usable_relationships(model : Model) -> Array[Relationship] {
  model.relationships.filter(r => {
    model.relationships.filter(other => other.id == r.id).length() == 1 &&
    relationship_error(model, r) is None &&
    r.source_refs.all(reference => source_ref_valid(model, reference))
  })
}

///|
/// Validate in the asserting model's scope, then retain exact endpoint refs.
/// Relationship IDs are local to that model, so equal IDs in distinct supplied
/// models must not be deduplicated or resolved against the root by accident.
fn usable_relationship_closure(model : Model) -> Array[Relationship] {
  let relationships : Array[Relationship] = []
  for (owner, _) in model_closure(model).0 {
    relationships.append(usable_relationships(owner))
  }
  relationships
}

///|
/// Reports link structure and independent gaps; does not type-check or execute.
fn inspect_local(root : Model, model : Model) -> Inspection {
  let diagnostics : Array[Diagnostic] = []
  let add = fn(code, owner, path) { diagnostics.push({ code, owner, path, }) }
  let seen : Array[Id] = []
  let identity = fn(id, path) {
    if seen.contains(id) {
      add(DuplicateIdentity, id, path)
    }
    seen.push(id)
  }
  let refs = fn(references : Array[SourceRef], owner, path) {
    for index, reference in references {
      if !source_ref_valid(model, reference) {
        add(MissingSourceFragment, owner, "\{path}/\{index}")
      }
    }
  }
  for index, source in model.sources {
    let path = "/sources/\{index}"
    identity(source.id, path)
    if source.document.revision is None {
      add(SourceUnpinned, source.id, path + "/document")
    }
    match source.resolution {
      Retained =>
        if source.fragments.is_empty() {
          add(InvalidSource, source.id, path + "/fragments")
        }
      Unresolved(_) => add(UnresolvedReference, source.id, path)
    }
    let anchors : Array[Id] = []
    for index, fragment in source.fragments {
      if anchors.contains(fragment.anchor) {
        add(InvalidSource, source.id, "\{path}/fragments/\{index}")
      }
      anchors.push(fragment.anchor)
    }
  }
  for index, entity in model.entities {
    let path = "/entities/\{index}"
    identity(entity.identity.id, path)
    refs(entity.source_refs, entity.identity.id, path + "/sourceRefs")
    match entity.content {
      SourceFragment(reference) =>
        if !source_ref_valid(model, reference) {
          add(MissingSourceFragment, entity.identity.id, path + "/content")
        }
      Declaration(_, None) =>
        add(ImplementationUnbound, entity.identity.id, path)
      Declaration(_, Some(binding)) =>
        match resolve(model, binding) {
          Err(code) => add(code, entity.identity.id, path + "/content/binding")
          Ok(e) =>
            if e.kind() != ImplementationKind {
              add(
                RelationshipKind,
                entity.identity.id,
                path + "/content/binding",
              )
            }
        }
      Contract(subject, clause_kind, expression) => {
        match resolve(model, subject) {
          Err(code) => add(code, entity.identity.id, path + "/content/subject")
          Ok(e) =>
            if !(match (clause_kind, e.content) {
                (Refinement | Invariant, Declaration(Type, _)) => true
                (Precondition | Postcondition, Declaration(Function, _)) => true
                _ => false
              }) {
              add(
                RelationshipKind,
                entity.identity.id,
                path + "/content/subject",
              )
            }
        }
        match expression {
          UnresolvedExpression(_) =>
            add(
              UnresolvedReference,
              entity.identity.id,
              path + "/content/expression",
            )
          ResolvedExpression(_, _) =>
            add(
              UnsupportedSemantics,
              entity.identity.id,
              path + "/content/expression",
            )
        }
      }
      Claim(claim) =>
        match resolve(model, claim.subject) {
          Err(code) => add(code, entity.identity.id, path + "/content/subject")
          Ok(_) => ()
        }
      _ => ()
    }
  }
  for index, relationship in model.relationships {
    let path = "/relationships/\{index}"
    identity(relationship.id, path)
    refs(relationship.source_refs, relationship.id, path + "/sourceRefs")
    if relationship_error(model, relationship) is Some(code) {
      add(code, relationship.id, path)
    }
  }
  let links = usable_relationship_closure(root)
  let evidence_links : Array[(Model, Relationship)] = []
  for (owner, _) in model_closure(root).0 {
    for link in usable_relationships(owner) {
      if link.predicate == Supports || link.predicate == Contradicts {
        evidence_links.push((owner, link))
      }
    }
  }
  for index, entity in model.entities {
    if entity.kind() == RequirementKind {
      let reference : ResolvedRef = {
        model: model.identity,
        entity: entity.identity,
      }
      let contracts = links.filter(r => {
        r.predicate == Formalizes &&
        r.target is Resolved(target) &&
        target == reference
      })
      if contracts.is_empty() {
        add(MissingFormalization, entity.identity.id, "/entities/\{index}")
      }
      if !contracts.any(c => {
          links.any(r => {
            r.predicate == Exercises &&
            r.target is Resolved(target) &&
            target == c.subject
          })
        }) {
        add(MissingExamples, entity.identity.id, "/entities/\{index}")
      }
      let claims = model.entities.filter(e => {
        e.content is Claim(claim) && claim.subject == reference
      })
      if !claims.any(claim => {
          evidence_links.any(entry => {
            let r = entry.1
            r.target is Resolved(target) &&
            target == { model: model.identity, entity: claim.identity, }
          })
        }) {
        add(MissingEvidence, entity.identity.id, "/entities/\{index}")
      }
    }
    if entity.content is Claim(claim) {
      let reference : ResolvedRef = {
        model: model.identity,
        entity: entity.identity,
      }
      let observations = evidence_links.filter(entry => {
        let r = entry.1
        r.target is Resolved(target) && target == reference
      })
      if observations.is_empty() {
        add(MissingEvidence, entity.identity.id, "/entities/\{index}")
      }
      let required = required_context(root, model, claim, entity.source_refs)
      for (link_owner, link) in observations {
        if resolve(link_owner, link.subject) is Ok(evidence_entity) &&
          evidence_entity.content is Evidence(evidence) {
          match
            compare_context(
              evidence.context,
              claim.context,
              observation_context(
                root, required, link_owner, link, evidence_entity, evidence,
              ),
            ) {
            Current => ()
            Stale =>
              add(
                StaleEvidence,
                evidence_entity.identity.id,
                "/entities/\{index}/content/context",
              )
            Inconclusive =>
              add(
                InconclusiveEvidence,
                evidence_entity.identity.id,
                "/entities/\{index}/content/context",
              )
          }
        }
      }
    }
  }
  { diagnostics, }
}

///|
pub fn inspect(model : Model) -> Inspection {
  let (models, duplicates) = model_closure(model)
  let diagnostics : Array[Diagnostic] = []
  for (owner, path) in models {
    for diagnostic in inspect_local(model, owner).diagnostics {
      diagnostics.push({ ..diagnostic, path: path + diagnostic.path, })
    }
  }
  for (snapshot, path) in duplicates {
    diagnostics.push({ code: DuplicateIdentity, owner: snapshot.id, path, })
  }
  { diagnostics, }
}
