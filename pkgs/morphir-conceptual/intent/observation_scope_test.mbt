///|
fn structured_run_graph(c : @intent.RevisionContext) -> @intent.Model raise {
  let base = evidence_graph(c, c, with_evidence=false)
  let source = @intent.adapt_kb_source(kb()).source
  let clause = entity(
    "clause",
    Contract(
      reference("operation"),
      Postcondition,
      UnresolvedExpression(@intent.NonemptyText::parse("pending")),
    ),
    refs=[{ source_id: source.id, anchor: id("return"), }],
  )
  let operation = entity(
    "operation",
    Declaration(Function, Some(reference("implementation"))),
  )
  let implementation = entity(
    "implementation",
    Implementation(snapshot("library", "lib1")),
  )
  let run : @intent.RunObservation = {
    value_profile: id("values"),
    input: @ion_text.read_ion("[]"),
    output: Absent(NotInvoked),
    clauses: [
      {
        entity: snapshot("clause", "r1"),
        observation: InconclusiveObservation,
      },
    ],
    evaluator: {
      id: id("evaluator"),
      version: rev("1"),
      profile: id("profile"),
    },
    target: "wasm-gc",
    configuration: @ion_text.read_ion("{}"),
    limits: @intent.RunLimits::new(1, 1),
    generated_case: None,
    type_arguments: None,
  }
  let record = entity(
    "run",
    Evidence({
      origin: "hand-authored-fixture",
      context: c,
      observation: Run(run),
    }),
  )
  {
    ..base,
    entities: joined(base.entities, [clause, operation, implementation, record]),
    sources: [source],
    relationships: [
      edge("support", Supports, "run", Resolved(reference("claim"))),
    ],
  }
}

///|
fn structured_run_context() -> @intent.RevisionContext raise {
  context(
    entities=[
      snapshot("requirement", "r1"),
      snapshot("clause", "r1"),
      snapshot("operation", "r1"),
      snapshot("implementation", "r1"),
    ],
    sources=[snapshot("urn:document:return", "doc-1")],
    implementations=[snapshot("library", "lib1")],
  )
}

///|
test "run clause source dependencies must appear in both contexts" {
  let complete = structured_run_context()
  let missing = context(
    entities=complete.entities(),
    implementations=complete.implementations(),
  )
  let assessment = @intent.assess_claim(
    structured_run_graph(missing),
    reference("claim"),
    missing,
  )
  assert_true(!assessment.inspection.has_errors())
  assert_eq(assessment.observations[0].freshness, Inconclusive)
  assert_true(has_code(assessment.inspection, InconclusiveEvidence))
  assert_eq(
    @intent.assess_claim(
      structured_run_graph(complete),
      reference("claim"),
      complete,
    ).observations[0].freshness,
    Current,
  )
}

///|
test "run clauses traverse their declaration dependencies" {
  let complete = structured_run_context()
  let missing = context(
    entities=complete.entities().filter(s => s.id != id("operation")),
    sources=complete.sources(),
    implementations=complete.implementations(),
  )
  let assessment = @intent.assess_claim(
    structured_run_graph(missing),
    reference("claim"),
    missing,
  )
  assert_true(!assessment.inspection.has_errors())
  assert_eq(assessment.observations[0].freshness, Inconclusive)
}

///|
test "run clause declarations traverse their implementation bindings" {
  let complete = structured_run_context()
  let missing = context(
    entities=complete.entities().filter(s => s.id != id("implementation")),
    sources=complete.sources(),
    implementations=complete.implementations(),
  )
  let assessment = @intent.assess_claim(
    structured_run_graph(missing),
    reference("claim"),
    missing,
  )
  assert_true(!assessment.inspection.has_errors())
  assert_eq(assessment.observations[0].freshness, Inconclusive)
}

///|
test "run clause bindings require artifact revisions" {
  let complete = structured_run_context()
  let missing = context(
    entities=complete.entities(),
    sources=complete.sources(),
  )
  let assessment = @intent.assess_claim(
    structured_run_graph(missing),
    reference("claim"),
    missing,
  )
  assert_true(!assessment.inspection.has_errors())
  assert_eq(assessment.observations[0].freshness, Inconclusive)
}

///|
test "inspection includes root-owned evidence for dependency-owned claims" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let old = context(model_revision="m0", entities=c.entities())
  let dependency = evidence_graph(c, c, with_evidence=false)
  let record = evidence_graph(c, old).entities[2]
  let outer = snapshot("outer", "o1")
  let link : @intent.Relationship = {
    id: id("support"),
    predicate: Supports,
    subject: { model: outer, entity: record.identity, },
    target: Resolved(reference("claim")),
    source_refs: [],
    descriptive: None,
  }
  let graph = {
    ..model([record], relationships=[link]),
    identity: outer,
    dependencies: [dependency],
  }
  let assessment = @intent.assess_claim(graph, reference("claim"), c)
  assert_true(!assessment.inspection.has_errors())
  assert_eq(assessment.observations[0].freshness, Stale)
  assert_true(has_code(assessment.inspection, StaleEvidence))
  assert_true(
    !assessment.inspection.diagnostics.any(d => {
      d.code == MissingEvidence &&
      (d.owner == id("claim") || d.owner == id("requirement"))
    }),
  )
  assert_true(
    assessment.inspection.diagnostics.any(d => {
      d.code == StaleEvidence &&
      d.path == "/dependencies/0/entities/1/content/context"
    }),
  )
}

///|
test "assessments retain relationship model revisions for repeated local IDs" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let records = evidence_graph(c, c)
  let shared = { ..records, relationships: [], }
  let assertion = records.relationships[0]
  let inner = {
    ..model([], relationships=[assertion]),
    identity: snapshot("asserting-model", "a1"),
    dependencies: [shared],
  }
  let root = {
    ..model([], relationships=[assertion]),
    identity: snapshot("asserting-model", "a2"),
    dependencies: [inner],
  }
  let assessment = @intent.assess_claim(root, reference("claim"), c)
  assert_true(!assessment.inspection.has_errors())
  assert_eq(assessment.observations.length(), 2)
  assert_true(
    assessment.observations.all(o => {
      o.relationship == id("support") &&
      o.reference == reference("analysis") &&
      o.freshness == Current
    }),
  )
  assert_eq(
    assessment.observations[0].relationship_model,
    snapshot("asserting-model", "a2"),
  )
  assert_eq(
    assessment.observations[1].relationship_model,
    snapshot("asserting-model", "a1"),
  )
}

///|
test "run clause traversal uses evidence owner scope despite root shadows" {
  let c = structured_run_context()
  let supplied = structured_run_graph(c)
  let dependency = { ..supplied, relationships: [], }
  let root_identity = snapshot("outer", "o1")
  let root_clause = entity(
    "clause",
    Contract(
      reference("operation"),
      Postcondition,
      UnresolvedExpression(@intent.NonemptyText::parse("root shadow")),
    ),
    refs=[{ source_id: id("urn:source:return"), anchor: id("return"), }],
  )
  let root = {
    ..model(
      [root_clause],
      sources=[@intent.adapt_kb_source(kb(revision="doc-2")).source],
      relationships=supplied.relationships,
    ),
    identity: root_identity,
    dependencies: [dependency],
  }
  let result = @intent.assess_claim(root, reference("claim"), c)
  assert_true(!result.inspection.has_errors())
  assert_eq(result.observations[0].freshness, Current)
  assert_true(!has_code(result.inspection, InconclusiveEvidence))
  assert_true(!has_code(result.inspection, StaleEvidence))
}

///|
test "ambiguous run clause ownership cannot select the first matching snapshot" {
  let c = structured_run_context()
  let supplied = structured_run_graph(c)
  let claim_context = context(entities=[snapshot("requirement", "r1")])
  let minimal_claim_entities = supplied.entities.map(e => {
    match e.content {
      Claim(claim) =>
        { ..e, content: Claim({ ..claim, context: claim_context, }), }
      _ => e
    }
  })
  // Keep the same clause snapshot in another model without duplicating a model
  // snapshot in the supplied closure. Its declaration is owned by that model.
  let other_ref : @intent.ResolvedRef = {
    model: snapshot("other", "o1"),
    entity: snapshot("operation", "r1"),
  }
  let other = {
    ..model([
      entity(
        "clause",
        Contract(
          other_ref,
          Postcondition,
          UnresolvedExpression(@intent.NonemptyText::parse("other")),
        ),
      ),
      entity("operation", Declaration(Function, None)),
    ]),
    identity: snapshot("other", "o1"),
  }
  let root = {
    ..supplied,
    entities: minimal_claim_entities,
    dependencies: [other],
  }
  let result = @intent.assess_claim(root, reference("claim"), c)
  assert_true(!result.inspection.has_errors())
  assert_eq(result.observations[0].freshness, Inconclusive)
}

///|
test "inspection resolves cross-owner assertion source refs in the asserting model" {
  let c = context(entities=[snapshot("requirement", "r1")], sources=[
    snapshot("urn:document:return", "doc-1"),
  ])
  let dependency = evidence_graph(c, c, with_evidence=false)
  let record = evidence_graph(c, c).entities[2]
  let outer = snapshot("outer", "o1")
  let source = @intent.adapt_kb_source(kb(revision="doc-2")).source
  let link : @intent.Relationship = {
    id: id("support"),
    predicate: Supports,
    subject: { model: outer, entity: record.identity, },
    target: Resolved(reference("claim")),
    source_refs: [{ source_id: source.id, anchor: id("return"), }],
    descriptive: None,
  }
  let graph = {
    ..model([record], sources=[source], relationships=[link]),
    identity: outer,
    dependencies: [dependency],
  }
  let result = @intent.assess_claim(graph, reference("claim"), c)
  assert_true(!result.inspection.has_errors())
  assert_eq(result.observations[0].freshness, Stale)
  assert_true(has_code(result.inspection, StaleEvidence))
  assert_true(!has_code(result.inspection, MissingEvidence))
}
