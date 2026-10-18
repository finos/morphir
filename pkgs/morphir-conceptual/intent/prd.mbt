///|
pub(all) struct PrdRow {
  requirement : ResolvedRef
  name : String
  category : Category
  text : String
  notation : @ion.IonValue?
  source_refs : Array[SourceRef]
  intents : Array[ResolvedRef]
  sources : Array[ResolvedRef]
  contracts : Array[ResolvedRef]
  scenarios : Array[ResolvedRef]
  claims : Array[ResolvedRef]
  evidence : Array[ResolvedRef]
}

///|
pub(all) struct PrdView {
  model : Snapshot
  rows : Array[PrdRow]
  inspection : Inspection
}

///|
/// Authored order is retained. A row is an identified requirement, never a new
/// authority. Link assertions do not establish fulfillment or prose equivalence.
pub fn prd_view(model : Model) -> PrdView {
  let rows : Array[PrdRow] = []
  let inspection = inspect(model)
  let links = if inspection.has_errors() {
    []
  } else {
    usable_relationship_closure(model)
  }
  for entity in model.entities {
    if entity.content is Requirement(category, text, notation) {
      let requirement : ResolvedRef = {
        model: model.identity,
        entity: entity.identity,
      }
      let intents = []
      let sources = []
      let contracts = []
      for link in links {
        if link.target is Resolved(target) {
          if link.subject == requirement {
            match link.predicate {
              Refines => intents.push(target)
              DerivedFrom => sources.push(target)
              _ => ()
            }
          }
          if link.predicate == Formalizes && target == requirement {
            contracts.push(link.subject)
          }
        }
      }
      let scenarios = links
        .filter(r => {
          r.predicate == Exercises &&
          r.target is Resolved(target) &&
          contracts.contains(target)
        })
        .map(r => r.subject)
      let claims = if inspection.has_errors() {
        []
      } else {
        model.entities
        .filter(e => e.content is Claim(claim) && claim.subject == requirement)
        .map(e => ({ model: model.identity, entity: e.identity, } : ResolvedRef))
      }
      let evidence = links
        .filter(r => {
          (r.predicate == Supports || r.predicate == Contradicts) &&
          r.target is Resolved(target) &&
          claims.contains(target)
        })
        .map(r => r.subject)
      rows.push({
        requirement,
        name: entity.name,
        category,
        text,
        notation,
        source_refs: entity.source_refs.copy(),
        intents,
        sources,
        contracts,
        scenarios,
        claims,
        evidence,
      })
    }
  }
  { model: model.identity, rows, inspection, }
}
