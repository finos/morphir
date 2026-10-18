///|
fn entity(
  name : String,
  content : @intent.Content,
  refs~ : Array[@intent.SourceRef] = [],
) -> @intent.Entity raise {
  {
    identity: snapshot(name, "r1"),
    name,
    source_refs: refs,
    content,
    descriptive: None,
  }
}

///|
fn model(
  entities : Array[@intent.Entity],
  relationships~ : Array[@intent.Relationship] = [],
  sources~ : Array[@intent.Source] = [],
) -> @intent.Model raise {
  {
    identity: snapshot("urn:model", "m1"),
    sources,
    entities,
    relationships,
    dependencies: [],
  }
}

///|
fn reference(
  name : String,
  revision~ : String = "r1",
  model_revision~ : String = "m1",
) -> @intent.ResolvedRef raise {
  {
    model: snapshot("urn:model", model_revision),
    entity: snapshot(name, revision),
  }
}

///|
fn edge(
  name : String,
  predicate : @intent.Predicate,
  subject : String,
  target : @intent.EntityRef,
) -> @intent.Relationship raise {
  {
    id: id(name),
    predicate,
    subject: reference(subject),
    target,
    source_refs: [],
    descriptive: None,
  }
}

///|
fn requirement(
  name : String,
  category~ : String = "morphir:requirement-kind/functional",
) -> @intent.Entity raise {
  entity(
    name,
    Requirement(
      @intent.Category::parse(category),
      "  Exact requirement.\n",
      None,
    ),
  )
}

///|
fn has_code(report : @intent.Inspection, code : @intent.DiagnosticCode) -> Bool {
  report.diagnostics.any(d => d.code == code)
}

///|
fn scenario_dependency(revision : String) -> @intent.Model raise {
  let identity = snapshot("urn:dependency", revision)
  let operation : @intent.ResolvedRef = {
    model: identity,
    entity: snapshot("operation", "r1"),
  }
  let contract : @intent.ResolvedRef = {
    model: identity,
    entity: snapshot("contract", "r1"),
  }
  let scenario : @intent.ResolvedRef = {
    model: identity,
    entity: snapshot("scenario", "r1"),
  }
  let source = @intent.adapt_kb_source(kb()).source
  let exercises : @intent.Relationship = {
    id: id("link"),
    predicate: Exercises,
    subject: scenario,
    target: Resolved(contract),
    source_refs: [{ source_id: source.id, anchor: id("return"), }],
    descriptive: None,
  }
  {
    ..model(
      [
        entity("operation", Declaration(Function, None)),
        entity(
          "contract",
          Contract(
            operation,
            Postcondition,
            UnresolvedExpression(@intent.NonemptyText::parse("pending")),
          ),
        ),
        entity(
          "scenario",
          Scenario(@ion_text.read_ion("{inputs:[],expected:null}")),
        ),
      ],
      relationships=[exercises],
      sources=[source],
    ),
    identity,
  }
}

///|
test "dependency-owned scenarios satisfy PRD example links at the exact dependency revision" {
  let selected = scenario_dependency("d1")
  let other = scenario_dependency("d2")
  let contract : @intent.ResolvedRef = {
    model: selected.identity,
    entity: snapshot("contract", "r1"),
  }
  let formalizes : @intent.Relationship = {
    id: id("link"),
    predicate: Formalizes,
    subject: contract,
    target: Resolved(reference("requirement")),
    source_refs: [],
    descriptive: None,
  }
  let graph = {
    ..model([requirement("requirement")], relationships=[formalizes]),
    dependencies: [selected, other],
  }
  let view = @intent.prd_view(graph)
  assert_true(!view.inspection.has_errors())
  assert_eq(view.rows[0].contracts, [contract])
  assert_eq(view.rows[0].scenarios, [
    { model: selected.identity, entity: snapshot("scenario", "r1"), },
  ])
  assert_true(!has_code(view.inspection, MissingExamples))
  let wrong = {
    ..selected.relationships[0],
    target: Resolved({ ..contract, entity: snapshot("contract", "r0"), }),
  }
  let invalid = @intent.prd_view({
    ..graph,
    dependencies: [{ ..selected, relationships: [wrong], }, other],
  })
  assert_true(has_code(invalid.inspection, ReferenceRevision))
  assert_true(invalid.rows[0].scenarios.is_empty())
}

///|
fn[A] joined(a : Array[A], b : Array[A]) -> Array[A] {
  let result = a.copy()
  result.append(b)
  result
}

///|
test "PRD retains mixed categories and many-to-many intent links without inventing formalization" {
  let categories = [
    "functional", "data", "performance", "operational", "regulatory",
  ]
  let requirements = categories.map(c => {
    requirement(c, category="morphir:requirement-kind/" + c)
  })
  requirements.push(requirement("extension", category="example:availability"))
  let graph = model(
    joined(requirements, [
      entity("i1", Intent("Desired outcome", None)),
      entity("i2", Intent("Other outcome", None)),
    ]),
    relationships=[
      edge("e1", Refines, "functional", Resolved(reference("i1"))),
      edge("e2", Refines, "functional", Resolved(reference("i2"))),
      edge("e3", Refines, "data", Resolved(reference("i1"))),
    ],
  )
  let view = @intent.prd_view(graph)
  assert_eq(view.rows.length(), 6)
  assert_eq(view.rows[0].text, "  Exact requirement.\n")
  assert_eq(view.rows[0].intents.length(), 2)
  assert_eq(view.rows[1].intents.length(), 1)
  assert_eq(view.rows[5].category.value(), "example:availability")
  assert_true(
    view.rows.all(r => r.contracts.is_empty() && r.scenarios.is_empty()),
  )
  assert_true(has_code(view.inspection, MissingFormalization))
  assert_true(has_code(view.inspection, MissingExamples))
  assert_true(has_code(view.inspection, MissingEvidence))
}

///|
test "PRD exposes formalization examples and evidence as assertions with separate gaps" {
  let current = context(entities=[snapshot("requirement", "r1")])
  let base = evidence_graph(current, current)
  let contract = entity(
    "contract",
    Contract(
      reference("operation"),
      Postcondition,
      UnresolvedExpression(@intent.NonemptyText::parse("predicate pending")),
    ),
  )
  let operation = entity("operation", Declaration(Function, None))
  let generated = entity(
    "scenario",
    Scenario(
      @ion_text.read_ion(
        "{origin:{kind:generated,generator:{id:demo,version:\"1.0.0\"}},inputs:[],expected:null}",
      ),
    ),
  )
  let graph = {
    ..base,
    entities: joined(base.entities, [contract, operation, generated]),
    relationships: joined(base.relationships, [
      edge(
        "formalization",
        Formalizes,
        "contract",
        Resolved(reference("requirement")),
      ),
      edge("exercise", Exercises, "scenario", Resolved(reference("contract"))),
    ]),
  }
  let view = @intent.prd_view(graph)
  assert_eq(view.rows[0].contracts, [reference("contract")])
  assert_eq(view.rows[0].scenarios, [reference("scenario")])
  assert_eq(view.rows[0].claims, [reference("claim")])
  assert_eq(view.rows[0].evidence, [reference("analysis"), reference("review")])
  assert_true(!has_code(view.inspection, MissingFormalization))
  assert_true(!has_code(view.inspection, MissingExamples))
  assert_true(has_code(view.inspection, ImplementationUnbound))
  assert_true(has_code(view.inspection, InconclusiveEvidence))
  assert_true(has_code(view.inspection, UnresolvedReference))
}

///|
test "inspection reports stale evidence against the supplied source snapshot" {
  let old = context(entities=[snapshot("requirement", "r1")], sources=[
    snapshot("urn:document:return", "doc-1"),
  ])
  let source = @intent.adapt_kb_source(kb(revision="doc-2")).source
  assert_true(
    has_code(
      @intent.inspect(evidence_graph(old, old, source=Some(source))),
      StaleEvidence,
    ),
  )
}

///|
test "derived source fragments retain exact text and independent rich notation" {
  let source = @intent.adapt_kb_source(kb()).source
  let source_ref : @intent.SourceRef = {
    source_id: source.id,
    anchor: id("return"),
  }
  let notation = @ion_text.read_ion(
    "ears::{pattern:eventDriven,verbatim:\"  When a return arrives...\\n\"}",
  )
  let requirement = entity(
    "requirement",
    Requirement(
      @intent.Category::parse("morphir:requirement-kind/functional"),
      "Keep identity",
      Some(notation),
    ),
  )
  let fragment = entity("fragment", SourceFragment(source_ref))
  let link = edge(
    "source-link",
    DerivedFrom,
    "requirement",
    Resolved(reference("fragment")),
  )
  let graph = model([requirement, fragment], sources=[source], relationships=[
    link,
  ])
  let view = @intent.prd_view(graph)
  assert_true(!view.inspection.has_errors())
  assert_eq(view.rows[0].sources, [reference("fragment")])
  guard view.rows[0].notation is Some(retained) else { fail("lost notation") }
  assert_eq(@ion_text.write_ion(retained), @ion_text.write_ion(notation))
  assert_eq(source.fragments[0].text, "Track returns.\r\n  Keep identity.\n")
  let duplicate = @intent.prd_view({ ..graph, relationships: [link, link], })
  assert_true(has_code(duplicate.inspection, DuplicateIdentity))
  assert_true(duplicate.rows[0].sources.is_empty())
  let duplicate_anchor = {
    ..source,
    fragments: [source.fragments[0], source.fragments[0]],
  }
  assert_true(
    has_code(
      @intent.inspect({ ..graph, sources: [duplicate_anchor], }),
      InvalidSource,
    ),
  )
}

///|
test "unresolved targets are gaps; fabricated resolution and wrong kinds are errors" {
  let entities = [requirement("r"), entity("i", Intent("Intent", None))]
  let unresolved = @intent.EntityRef::unresolved(
    "external#text",
    SourceFragmentKind,
    "not supplied",
  )
  let valid = @intent.inspect(
    model(entities, relationships=[edge("u", DerivedFrom, "r", unresolved)]),
  )
  assert_true(!valid.has_errors())
  assert_true(has_code(valid, UnresolvedReference))
  let absent = @intent.inspect(
    model(entities, relationships=[
      edge("a", DerivedFrom, "r", Resolved(reference("missing"))),
    ]),
  )
  assert_true(absent.has_errors())
  assert_true(has_code(absent, MissingResolvedTarget))
  let wrong = @intent.prd_view(
    model(entities, relationships=[
      edge("w", Formalizes, "i", Resolved(reference("r"))),
    ]),
  )
  assert_true(has_code(wrong.inspection, RelationshipKind))
  assert_true(wrong.rows[0].contracts.is_empty())
  let wrong_unresolved = @intent.inspect(
    model(entities, relationships=[
      edge(
        "wu",
        DerivedFrom,
        "r",
        @intent.EntityRef::unresolved("external", IntentKind, "not supplied"),
      ),
    ]),
  )
  assert_true(has_code(wrong_unresolved, RelationshipKind))
  let stale_ref = @intent.inspect(
    model(entities, relationships=[
      edge("s", Refines, "r", Resolved(reference("i", revision="r0"))),
    ]),
  )
  assert_true(has_code(stale_ref, ReferenceRevision))
}

///|
test "duplicate identities and missing fragments are invalid; unresolved unpinned source remains visible" {
  let source = @intent.adapt_kb_source(kb()).source
  let bad = entity(
    "r",
    Requirement(
      @intent.Category::parse("morphir:requirement-kind/data"),
      "data",
      None,
    ),
    refs=[{ source_id: source.id, anchor: id("missing"), }],
  )
  let report = @intent.inspect(model([bad, bad], sources=[source]))
  assert_true(has_code(report, DuplicateIdentity))
  assert_true(has_code(report, MissingSourceFragment))
  let unavailable : @intent.Source = {
    ..source,
    document: { id: source.document.id, revision: None, },
    resolution: Unresolved(@intent.NonemptyText::parse("not supplied")),
    fragments: [],
  }
  let gap = @intent.inspect(model([], sources=[unavailable]))
  assert_true(!gap.has_errors())
  assert_true(has_code(gap, SourceUnpinned))
  assert_true(has_code(gap, UnresolvedReference))
}

///|
test "all KB lifecycle states and absent state are read-only; Ion metadata survives" {
  let rich = @ion_text.read_ion(
    "note::{n:9007199254740993,d:123.4500,s:pending,t:null.string}",
  )
  let states : Array[@intent.KbState?] = [
    Some(Backlog),
    Some(Refinement),
    Some(InProgress),
    Some(Released),
    Some(Cancelled),
    Some(Superseded),
    None,
  ]
  for state in states {
    let input = { ..kb(state~), descriptive: Some(rich), }
    let adapted = @intent.adapt_kb_source(input)
    let graph = model([adapted.intent, requirement("r")], sources=[
      adapted.source,
    ])
    let view = @intent.prd_view(graph)
    assert_true(view.rows[0].contracts.is_empty())
    assert_true(view.rows[0].scenarios.is_empty())
    assert_eq(adapted.origin.state, state)
    guard adapted.intent.descriptive is Some(retained) else {
      fail("lost descriptive data")
    }
    assert_eq(@ion_text.write_ion(retained), @ion_text.write_ion(rich))
  }
}
