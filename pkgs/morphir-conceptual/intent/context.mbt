///|
/// Exact caller-declared dependency set. Copies prevent a caller from adding a
/// duplicate or changing the set after construction. Lists retain authored order.
pub struct RevisionContext {
  model : Snapshot
  priv entity_revisions : Array[Snapshot]
  priv source_revisions : Array[Snapshot]
  priv implementation_revisions : Array[Snapshot]
}

///|
pub fn RevisionContext::new(
  model : Snapshot,
  entities~ : Array[Snapshot],
  sources~ : Array[Snapshot],
  implementations~ : Array[Snapshot],
) -> RevisionContext raise InvalidInput {
  for entries in [entities, sources, implementations] {
    let ids : Array[Id] = []
    for entry in entries {
      if ids.contains(entry.id) {
        raise InvalidInput(
          "Duplicate revision-context identity: " + entry.id.value(),
        )
      }
      ids.push(entry.id)
    }
  }
  {
    model,
    entity_revisions: entities.copy(),
    source_revisions: sources.copy(),
    implementation_revisions: implementations.copy(),
  }
}

///|
pub fn RevisionContext::entities(self : RevisionContext) -> Array[Snapshot] {
  self.entity_revisions.copy()
}

///|
pub fn RevisionContext::sources(self : RevisionContext) -> Array[Snapshot] {
  self.source_revisions.copy()
}

///|
pub fn RevisionContext::implementations(
  self : RevisionContext,
) -> Array[Snapshot] {
  self.implementation_revisions.copy()
}

///|
pub(all) enum Freshness {
  Current
  Stale
  Inconclusive
} derive(Eq, Debug)

///|
pub extend Freshness with Eq::{equal, not_equal}

///|
pub extend Freshness with @debug.Debug::{to_repr}

///|
fn includes_ids(entries : Array[Snapshot], required : Array[Id]) -> Bool {
  required.all(id => entries.any(entry => entry.id == id))
}

///|
fn same_set(a : Array[Snapshot], b : Array[Snapshot]) -> Bool {
  a.length() == b.length() && a.all(entry => b.contains(entry))
}

///|
priv struct RequiredContext {
  entities : Array[Id]
  sources : Array[Id]
  implementations : Array[Id]
  actual_model : Snapshot
  actual_entities : Array[Snapshot]
  actual_sources : Array[Snapshot]
  actual_implementations : Array[Snapshot]
  selected_entities : Array[Id]
  selected_sources : Array[Id]
  selected_implementations : Array[Id]
  mut unavailable : Bool
}

///|
fn compare_context(
  recorded : RevisionContext,
  requested : RevisionContext,
  required : RequiredContext,
) -> Freshness {
  if required.unavailable ||
    !includes_ids(recorded.entity_revisions, required.entities) ||
    !includes_ids(requested.entity_revisions, required.entities) ||
    !includes_ids(recorded.source_revisions, required.sources) ||
    !includes_ids(requested.source_revisions, required.sources) ||
    !includes_ids(recorded.implementation_revisions, required.implementations) ||
    !includes_ids(requested.implementation_revisions, required.implementations) {
    return Inconclusive
  }
  if recorded.model == requested.model &&
    requested.model == required.actual_model &&
    required.actual_entities.all(s => requested.entity_revisions.contains(s)) &&
    required.actual_sources.all(s => requested.source_revisions.contains(s)) &&
    required.actual_implementations.all(s => {
      requested.implementation_revisions.contains(s)
    }) &&
    same_set(recorded.entity_revisions, requested.entity_revisions) &&
    same_set(recorded.source_revisions, requested.source_revisions) &&
    same_set(
      recorded.implementation_revisions,
      requested.implementation_revisions,
    ) {
    Current
  } else {
    Stale
  }
}

///|
fn add_id(ids : Array[Id], id : Id) -> Unit {
  if !ids.contains(id) {
    ids.push(id)
  }
}

///|
fn add_actual(
  required : RequiredContext,
  entries : Array[Snapshot],
  snapshot : Snapshot,
) -> Unit {
  if entries.any(entry => entry.id == snapshot.id && entry != snapshot) {
    required.unavailable = true
  }
  if !entries.contains(snapshot) {
    entries.push(snapshot)
  }
}

///|
fn require_source(
  required : RequiredContext,
  owner : Model,
  reference : SourceRef,
) -> Unit {
  guard owner.sources.filter(s => s.id == reference.source_id).get(0)
    is Some(found) else {
    required.unavailable = true
    return
  }
  add_id(required.sources, found.document.id)
  add_id(required.selected_sources, found.document.id)
  match found.document.revision {
    Some(revision) =>
      add_actual(required, required.actual_sources, {
        id: found.document.id,
        revision,
      })
    None => required.unavailable = true
  }
  if found.resolution is Unresolved(_) {
    required.unavailable = true
  }
}

///|
/// A declared dependency is relevant even without a relationship. Exact linked
/// references already select its snapshot; otherwise inspect every candidate in
/// the owner's supplied closure. Conflicting revisions remain inconclusive.
fn include_declared_context(
  required : RequiredContext,
  owner : Model,
  declared : RevisionContext,
) -> Unit {
  for entry in declared.entity_revisions {
    add_id(required.entities, entry.id)
  }
  for entry in declared.source_revisions {
    add_id(required.sources, entry.id)
  }
  for entry in declared.implementation_revisions {
    add_id(required.implementations, entry.id)
  }
  let entities = declared.entity_revisions
    .filter(entry => !required.selected_entities.contains(entry.id))
    .map(entry => entry.id)
  let sources = declared.source_revisions
    .filter(entry => !required.selected_sources.contains(entry.id))
    .map(entry => entry.id)
  let implementations = declared.implementation_revisions
    .filter(entry => !required.selected_implementations.contains(entry.id))
    .map(entry => entry.id)
  for (candidate, _) in model_closure(owner).0 {
    for entity in candidate.entities {
      if entities.contains(entity.identity.id) {
        add_actual(required, required.actual_entities, entity.identity)
      }
      if entity.content is Implementation(artifact) &&
        implementations.contains(artifact.id) {
        add_actual(required, required.actual_implementations, artifact)
      }
    }
    for source in candidate.sources {
      if sources.contains(source.document.id) {
        match source.document.revision {
          Some(revision) =>
            add_actual(required, required.actual_sources, {
              id: source.document.id,
              revision,
            })
          None => required.unavailable = true
        }
        if source.resolution is Unresolved(_) {
          required.unavailable = true
        }
      }
    }
  }
}

///|
/// Collect a selected entity's structured dependencies within the supplied scope.
fn require_entity_context(
  model : Model,
  required : RequiredContext,
  selected : ResolvedRef,
) -> Unit {
  let visited : Array[ResolvedRef] = []
  fn visit(reference : ResolvedRef) -> Unit {
    if visited.contains(reference) {
      return
    }
    visited.push(reference)
    add_id(required.entities, reference.entity.id)
    let entity = match resolve(model, reference) {
      Ok(e) => e
      Err(_) => {
        required.unavailable = true
        return
      }
    }
    add_actual(required, required.actual_entities, entity.identity)
    add_id(required.selected_entities, entity.identity.id)
    guard find_model(model, reference.model) is Some(owner) else {
      required.unavailable = true
      return
    }
    for source_reference in entity.source_refs {
      require_source(required, owner, source_reference)
    }
    match entity.content {
      SourceFragment(source_reference) =>
        require_source(required, owner, source_reference)
      Contract(subject, _, _) => visit(subject)
      Declaration(_, Some(binding)) => visit(binding)
      Implementation(artifact) => {
        add_id(required.implementations, artifact.id)
        add_id(required.selected_implementations, artifact.id)
        add_actual(required, required.actual_implementations, artifact)
      }
      _ => ()
    }
    for (link_owner, _) in model_closure(model).0 {
      for link in link_owner.relationships {
        let follows = link.subject == reference &&
          (
            link.predicate == Refines ||
            link.predicate == DerivedFrom ||
            link.predicate == GovernedBy
          )
        let reverses = link.target is Resolved(target) &&
          target == reference &&
          (
            link.predicate == Formalizes ||
            link.predicate == Exercises ||
            link.predicate == Implements
          )
        if follows || reverses {
          for source_reference in link.source_refs {
            require_source(required, link_owner, source_reference)
          }
          if relationship_error(link_owner, link) is Some(_) {
            required.unavailable = true
          }
          if follows {
            match link.target {
              Resolved(target) => visit(target)
              Unresolved(_, _, _) => required.unavailable = true
            }
          }
          if reverses {
            visit(link.subject)
          }
        }
      }
    }
  }
  visit(selected)
}

///|
/// Discover structural assertions throughout the supplied root closure while
/// keeping the claim's model revision and local provenance in its owning scope.
fn required_context(
  root : Model,
  model : Model,
  claim : Claim,
  source_refs : Array[SourceRef],
) -> RequiredContext {
  let required : RequiredContext = {
    entities: claim.context.entity_revisions.map(s => s.id),
    sources: claim.context.source_revisions.map(s => s.id),
    implementations: claim.context.implementation_revisions.map(s => s.id),
    actual_model: model.identity,
    actual_entities: [],
    actual_sources: [],
    actual_implementations: [],
    selected_entities: [],
    selected_sources: [],
    selected_implementations: [],
    unavailable: false,
  }
  require_entity_context(root, required, claim.subject)
  for reference in source_refs {
    require_source(required, model, reference)
  }
  include_declared_context(required, model, claim.context)
  required
}

///|
fn observation_context(
  model : Model,
  base : RequiredContext,
  link_owner : Model,
  link : Relationship,
  entity : Entity,
  evidence : Evidence,
) -> RequiredContext {
  let required : RequiredContext = {
    entities: base.entities.copy(),
    sources: base.sources.copy(),
    implementations: base.implementations.copy(),
    actual_model: base.actual_model,
    actual_entities: base.actual_entities.copy(),
    actual_sources: base.actual_sources.copy(),
    actual_implementations: base.actual_implementations.copy(),
    selected_entities: base.selected_entities.copy(),
    selected_sources: base.selected_sources.copy(),
    selected_implementations: base.selected_implementations.copy(),
    unavailable: base.unavailable,
  }
  if find_model(model, link.subject.model) is Some(owner) {
    for reference in entity.source_refs {
      require_source(required, owner, reference)
    }
  }
  for reference in link.source_refs {
    require_source(required, link_owner, reference)
  }
  if evidence.observation is Run(run) {
    for clause in run.clauses {
      add_id(required.entities, clause.entity.id)
      if !evidence.context.entity_revisions.contains(clause.entity) {
        required.unavailable = true
      }
      // M1 clause results carry an entity snapshot, not a model reference.
      // Resolve only inside the evidence owner's closure and require a unique
      // supplied owner; equal entity snapshots in distinct models are ambiguous.
      let candidates : Array[ResolvedRef] = []
      if find_model(model, link.subject.model) is Some(owner) {
        for (candidate, _) in model_closure(owner).0 {
          for entity in candidate.entities {
            if entity.identity == clause.entity && entity.kind() == ContractKind {
              candidates.push({
                model: candidate.identity,
                entity: entity.identity,
              })
            }
          }
        }
        if candidates.length() == 1 {
          require_entity_context(model, required, candidates[0])
        } else {
          required.unavailable = true
        }
      } else {
        required.unavailable = true
      }
    }
  }
  if find_model(model, link.subject.model) is Some(owner) {
    include_declared_context(required, owner, evidence.context)
  }
  required
}
