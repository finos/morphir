///|
fn ancestor_ref(name : String) -> @intent.ResolvedRef raise {
  { model: snapshot("ancestor", "a1"), entity: snapshot(name, "r1"), }
}

///|
fn ancestor_context() -> @intent.RevisionContext raise {
  context(
    entities=[
      snapshot("requirement", "r1"),
      snapshot("contract", "r1"),
      snapshot("operation", "r1"),
      snapshot("scenario", "r1"),
      snapshot("implementation", "r1"),
    ],
    sources=[
      snapshot("claim-document", "doc-1"),
      snapshot("link-document", "doc-2"),
    ],
    implementations=[snapshot("library", "lib1")],
  )
}

///|
fn ancestor_graph(c : @intent.RevisionContext) -> @intent.Model raise {
  let base = evidence_graph(c, c)
  let claim_source = @intent.adapt_kb_source(kb(document="claim-document")).source
  let link_source = @intent.adapt_kb_source(
      kb(document="link-document", revision="doc-2"),
    ).source
  let refs : Array[@intent.SourceRef] = [
    { source_id: claim_source.id, anchor: id("return"), },
  ]
  let entities = base.entities.map(e => {
    match e.content {
      Claim(_) => { ..e, source_refs: refs, }
      _ => e
    }
  })
  let dependency = {
    ..base,
    entities: joined(entities, [
      entity(
        "contract",
        Contract(
          reference("operation"),
          Postcondition,
          UnresolvedExpression(@intent.NonemptyText::parse("pending")),
        ),
        refs~,
      ),
      entity("operation", Declaration(Function, None)),
    ]),
    sources: [claim_source],
  }
  let formalizes : @intent.Relationship = {
    id: id("formalizes"),
    predicate: Formalizes,
    subject: reference("contract"),
    target: Resolved(reference("requirement")),
    source_refs: [{ source_id: link_source.id, anchor: id("return"), }],
    descriptive: None,
  }
  let exercises : @intent.Relationship = {
    id: id("exercises"),
    predicate: Exercises,
    subject: ancestor_ref("scenario"),
    target: Resolved(reference("contract")),
    source_refs: [],
    descriptive: None,
  }
  let implements : @intent.Relationship = {
    id: id("implements"),
    predicate: Implements,
    subject: ancestor_ref("implementation"),
    target: Resolved(reference("operation")),
    source_refs: [],
    descriptive: None,
  }
  {
    ..model(
      [
        entity("scenario", Scenario(@ion_text.read_ion("{}"))),
        entity("implementation", Implementation(snapshot("library", "lib1"))),
      ],
      relationships=[formalizes, exercises, implements],
      sources=[link_source],
    ),
    identity: snapshot("ancestor", "a1"),
    dependencies: [dependency],
  }
}

///|
test "ancestor assertions contribute every linked entity to dependency claim context" {
  let complete = ancestor_context()
  for missing_id in ["contract", "operation", "scenario", "implementation"] {
    let incomplete = context(
      entities=complete.entities().filter(s => s.id != id(missing_id)),
      sources=complete.sources(),
      implementations=complete.implementations(),
    )
    let result = @intent.assess_claim(
      ancestor_graph(incomplete),
      reference("claim"),
      incomplete,
    )
    assert_true(!result.inspection.has_errors())
    assert_eq(result.claim_freshness, Inconclusive)
    assert_true(result.observations.all(o => o.freshness == Inconclusive))
    assert_true(has_code(result.inspection, InconclusiveEvidence))
  }
}

///|
test "ancestor implementation assertions require their artifact revision" {
  let complete = ancestor_context()
  let incomplete = context(
    entities=complete.entities(),
    sources=complete.sources(),
  )
  let result = @intent.assess_claim(
    ancestor_graph(incomplete),
    reference("claim"),
    incomplete,
  )
  assert_true(!result.inspection.has_errors())
  assert_eq(result.claim_freshness, Inconclusive)
  assert_true(result.observations.all(o => o.freshness == Inconclusive))
}

///|
test "ancestor structural assertions use exact entity and relationship source owners" {
  let complete = ancestor_context()
  let graph = ancestor_graph(complete)
  let current = @intent.assess_claim(graph, reference("claim"), complete)
  assert_eq(current.claim_freshness, Current)
  assert_true(current.observations.all(o => o.freshness == Current))
  let changed = {
    ..graph,
    sources: [
      @intent.adapt_kb_source(kb(document="link-document", revision="doc-3")).source,
    ],
  }
  let stale = @intent.assess_claim(changed, reference("claim"), complete)
  assert_true(!stale.inspection.has_errors())
  assert_eq(stale.claim_freshness, Stale)
  assert_true(stale.observations.all(o => o.freshness == Stale))
  let missing_source = context(
    entities=complete.entities(),
    sources=[snapshot("claim-document", "doc-1")],
    implementations=complete.implementations(),
  )
  let omitted = @intent.assess_claim(
    ancestor_graph(missing_source),
    reference("claim"),
    missing_source,
  )
  assert_eq(omitted.claim_freshness, Inconclusive)
}

///|
test "ancestor-owned formalizations and examples satisfy dependency inspection gaps" {
  let report = @intent.inspect(ancestor_graph(ancestor_context()))
  assert_true(!report.has_errors())
  assert_true(!has_code(report, MissingFormalization))
  assert_true(!has_code(report, MissingExamples))
}

///|
test "ancestor example links to another contract snapshot do not fill the selected gap" {
  let graph = ancestor_graph(ancestor_context())
  let other = scenario_dependency("d2")
  let other_contract : @intent.ResolvedRef = {
    model: other.identity,
    entity: snapshot("contract", "r1"),
  }
  let links = graph.relationships.map(r => {
    if r.predicate == Exercises {
      { ..r, target: Resolved(other_contract), }
    } else {
      r
    }
  })
  let report = @intent.inspect({
    ..graph,
    relationships: links,
    dependencies: joined(graph.dependencies, [other]),
  })
  assert_true(!report.has_errors())
  assert_true(
    report.diagnostics.any(d => {
      d.code == MissingExamples && d.owner == id("requirement")
    }),
  )
  assert_true(!has_code(report, MissingFormalization))
}

///|
test "ancestor assertions also contribute dependencies of an observation-only clause" {
  let c = structured_run_context()
  let dependency = structured_run_graph(c)
  let exercises : @intent.Relationship = {
    id: id("exercises"),
    predicate: Exercises,
    subject: ancestor_ref("scenario"),
    target: Resolved(reference("clause")),
    source_refs: [],
    descriptive: None,
  }
  let graph = {
    ..model([entity("scenario", Scenario(@ion_text.read_ion("{}")))], relationships=[
      exercises,
    ]),
    identity: snapshot("ancestor", "a1"),
    dependencies: [dependency],
  }
  let result = @intent.assess_claim(graph, reference("claim"), c)
  assert_true(!result.inspection.has_errors())
  assert_eq(result.claim_freshness, Current)
  assert_eq(result.observations[0].freshness, Inconclusive)
  let complete = context(
    entities=joined(c.entities(), [snapshot("scenario", "r1")]),
    sources=c.sources(),
    implementations=c.implementations(),
  )
  let completed = @intent.assess_claim(
    { ..graph, dependencies: [structured_run_graph(complete)], },
    reference("claim"),
    complete,
  )
  assert_eq(completed.observations[0].freshness, Current)
}

///|
test "ancestor formalization targets retain their exact model revision" {
  let graph = ancestor_graph(ancestor_context())
  let other = {
    ..model([requirement("requirement")]),
    identity: snapshot("urn:model", "m2"),
  }
  let links = graph.relationships.map(r => {
    if r.predicate == Formalizes {
      { ..r, target: Resolved(reference("requirement", model_revision="m2")), }
    } else {
      r
    }
  })
  let report = @intent.inspect({
    ..graph,
    relationships: links,
    dependencies: joined(graph.dependencies, [other]),
  })
  assert_true(!report.has_errors())
  assert_true(
    report.diagnostics.any(d => {
      d.code == MissingFormalization && d.path == "/dependencies/0/entities/0"
    }),
  )
  assert_true(
    !report.diagnostics.any(d => {
      d.code == MissingFormalization && d.path == "/dependencies/1/entities/0"
    }),
  )
}
