///|
test "a changed supplied source cannot look current through two matching old contexts" {
  let old = context(entities=[snapshot("requirement", "r1")], sources=[
    snapshot("urn:document:return", "doc-1"),
  ])
  let edited = @intent.adapt_kb_source(kb(revision="doc-2")).source
  let report = @intent.assess_claim(
    evidence_graph(old, old, source=Some(edited)),
    reference("claim"),
    old,
  )
  assert_eq(report.claim_freshness, Stale)
  assert_eq(report.observations[0].freshness, Stale)
}

///|
test "invalid contract subjects prevent PRD formalization links" {
  let graph = model(
    [
      requirement("requirement"),
      entity(
        "contract",
        Contract(
          reference("missing-declaration"),
          Postcondition,
          UnresolvedExpression(@intent.NonemptyText::parse("not elaborated")),
        ),
      ),
    ],
    relationships=[
      edge(
        "formalizes",
        Formalizes,
        "contract",
        Resolved(reference("requirement")),
      ),
    ],
  )
  let view = @intent.prd_view(graph)
  assert_true(view.inspection.has_errors())
  assert_true(view.rows[0].contracts.is_empty())
}

///|
test "evidence source refs also require document context" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let source = @intent.adapt_kb_source(kb()).source
  let graph = evidence_graph(c, c)
  let entities = graph.entities.map(e => {
    if e.identity.id == id("analysis") {
      { ..e, source_refs: [{ source_id: source.id, anchor: id("return"), }], }
    } else {
      e
    }
  })
  let report = @intent.assess_claim(
    { ..graph, entities, sources: [source], },
    reference("claim"),
    c,
  )
  assert_eq(report.observations[0].freshness, Inconclusive)
  assert_eq(report.observations[1].freshness, Current)
}

///|
test "duplicate dependency snapshots are invalid instead of selecting the first" {
  let dependency = model([entity("intent", Intent("External intent", None))])
  let root = {
    ..model([requirement("requirement")]),
    identity: snapshot("root", "root-1"),
    dependencies: [dependency, dependency],
  }
  assert_true(@intent.inspect(root).has_errors())
}

///|
test "explicit dependency references preserve exact model scope and cycles are rejected" {
  let dependency = {
    ..model([entity("intent", Intent("External intent", None))]),
    identity: snapshot("urn:dependency", "d1"),
  }
  let target : @intent.ResolvedRef = {
    model: dependency.identity,
    entity: snapshot("intent", "r1"),
  }
  let graph = {
    ..model([requirement("requirement")], relationships=[
      edge("external-refines", Refines, "requirement", Resolved(target)),
    ]),
    dependencies: [dependency],
  }
  let view = @intent.prd_view(graph)
  assert_true(!view.inspection.has_errors())
  assert_eq(view.rows[0].intents, [target])
  let wrong = { ..target, model: snapshot("urn:dependency", "d2"), }
  assert_true(
    has_code(
      @intent.inspect({
        ..graph,
        relationships: [edge("bad", Refines, "requirement", Resolved(wrong))],
      }),
      ReferenceRevision,
    ),
  )
  let cycle = model([])
  cycle.dependencies.push(cycle)
  assert_true(has_code(@intent.inspect(cycle), DuplicateIdentity))
}

///|
test "bound implementation revisions cannot be omitted" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let graph = evidence_graph(c, c)
  let declaration = entity(
    "operation",
    Declaration(Function, Some(reference("implementation"))),
  )
  let implementation = entity(
    "implementation",
    Implementation(snapshot("urn:artifact", "lib-1")),
  )
  let contract = entity(
    "contract",
    Contract(
      reference("operation"),
      Postcondition,
      UnresolvedExpression(@intent.NonemptyText::parse("not yet formalized")),
    ),
  )
  let linked = {
    ..graph,
    entities: joined(graph.entities, [declaration, implementation, contract]),
    relationships: joined(graph.relationships, [
      edge(
        "formalizes",
        Formalizes,
        "contract",
        Resolved(reference("requirement")),
      ),
    ]),
  }
  assert_eq(
    @intent.assess_claim(linked, reference("claim"), c).observations[0].freshness,
    Inconclusive,
  )
  let complete = context(
    entities=[
      snapshot("requirement", "r1"),
      snapshot("contract", "r1"),
      snapshot("operation", "r1"),
      snapshot("implementation", "r1"),
    ],
    implementations=[snapshot("urn:artifact", "lib-1")],
  )
  // An unresolved expression remains a semantic gap but does not erase the
  // currency of a review that explicitly names the complete dependency set.
  let updated = linked.entities.map(e => {
    match e.content {
      Claim(claim) => { ..e, content: Claim({ ..claim, context: complete, }), }
      Evidence(evidence) =>
        { ..e, content: Evidence({ ..evidence, context: complete, }), }
      _ => e
    }
  })
  assert_eq(
    @intent.assess_claim(
      { ..linked, entities: updated, },
      reference("claim"),
      complete,
    ).observations[0].freshness,
    Current,
  )
}

///|
test "claim source refs require document context independently of subject source refs" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let graph = evidence_graph(c, c)
  let source = @intent.adapt_kb_source(kb()).source
  let entities = graph.entities.map(e => {
    if e.identity.id == id("claim") {
      { ..e, source_refs: [{ source_id: source.id, anchor: id("return"), }], }
    } else {
      e
    }
  })
  let report = @intent.assess_claim(
    { ..graph, entities, sources: [source], },
    reference("claim"),
    c,
  )
  assert_eq(report.claim_freshness, Inconclusive)
  assert_true(report.observations.all(o => o.freshness == Inconclusive))
}

///|
test "contract clause kinds retain M1 declaration role requirements" {
  let type_decl = entity("type", Declaration(Type, None))
  let function_decl = entity("function", Declaration(Function, None))
  let expression = @intent.Expression::UnresolvedExpression(
    @intent.NonemptyText::parse("pending"),
  )
  for kind in [@intent.ClauseKind::Refinement, Invariant] {
    let valid = entity(
      "contract",
      Contract(reference("type"), kind, expression),
    )
    let invalid = entity(
      "contract",
      Contract(reference("function"), kind, expression),
    )
    assert_true(!@intent.inspect(model([type_decl, valid])).has_errors())
    assert_true(@intent.inspect(model([function_decl, invalid])).has_errors())
  }
  for kind in [@intent.ClauseKind::Precondition, Postcondition] {
    let valid = entity(
      "contract",
      Contract(reference("function"), kind, expression),
    )
    let invalid = entity(
      "contract",
      Contract(reference("type"), kind, expression),
    )
    assert_true(!@intent.inspect(model([function_decl, valid])).has_errors())
    assert_true(@intent.inspect(model([type_decl, invalid])).has_errors())
  }
}

///|
test "run clause identities require complete context even when the claim omits them" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let graph = evidence_graph(c, c, with_evidence=false)
  let run : @intent.RunObservation = {
    value_profile: id("urn:values"),
    input: @ion_text.read_ion("[]"),
    output: Absent(NotInvoked),
    clauses: [
      {
        entity: snapshot("clause", "k1"),
        observation: InconclusiveObservation,
      },
    ],
    evaluator: {
      id: id("urn:evaluator"),
      version: rev("1.0.0"),
      profile: id("urn:profile"),
    },
    target: "wasm-gc",
    configuration: @ion_text.read_ion("{}"),
    limits: @intent.RunLimits::new(1, 1),
    generated_case: None,
    type_arguments: None,
  }
  let run_entity = entity(
    "run",
    Evidence({
      origin: "hand-authored-fixture",
      context: c,
      observation: Run(run),
    }),
  )
  let report = @intent.assess_claim(
    {
      ..graph,
      entities: joined(graph.entities, [run_entity]),
      relationships: [
        edge("run-edge", Supports, "run", Resolved(reference("claim"))),
      ],
    },
    reference("claim"),
    c,
  )
  assert_eq(report.observations[0].freshness, Inconclusive)

  let complete = context(entities=[
    snapshot("requirement", "r1"),
    snapshot("clause", "k2"),
  ])
  let entities = graph.entities.map(e => {
    match e.content {
      Claim(claim) => { ..e, content: Claim({ ..claim, context: complete, }), }
      _ => e
    }
  })
  let inconsistent_run = entity(
    "run",
    Evidence({
      origin: "hand-authored-fixture",
      context: complete,
      observation: Run(run),
    }),
  )
  let inconsistent = @intent.assess_claim(
    {
      ..graph,
      entities: joined(entities, [inconsistent_run]),
      relationships: [
        edge("run-edge", Supports, "run", Resolved(reference("claim"))),
      ],
    },
    reference("claim"),
    complete,
  )
  assert_eq(inconsistent.observations[0].freshness, Inconclusive)
}

///|
test "claims in explicitly supplied dependencies use their own model context" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let dependency = evidence_graph(c, c)
  let root = {
    ..model([]),
    identity: snapshot("outer", "outer-1"),
    dependencies: [dependency],
  }
  let assessment = @intent.assess_claim(root, reference("claim"), c)
  assert_eq(assessment.availability, Present)
  assert_eq(assessment.claim_freshness, Current)
  assert_eq(assessment.observations.length(), 2)
  assert_eq(assessment.observations[0].freshness, Current)
}

///|
fn context_dependency(
  model_revision : String,
  entity_revision : String,
  source_revision : String,
  artifact_revision : String,
) -> @intent.Model raise {
  let identity = snapshot("urn:context-dependency", model_revision)
  let source = @intent.adapt_kb_source(kb(revision=source_revision)).source
  let implementation = entity(
    "implementation",
    Implementation(snapshot("urn:library", artifact_revision)),
  )
  let binding : @intent.ResolvedRef = {
    model: identity,
    entity: implementation.identity,
  }
  let declaration = {
    ..entity("other", Declaration(Function, Some(binding)), refs=[
      { source_id: source.id, anchor: id("return"), },
    ]),
    identity: snapshot("other", entity_revision),
  }
  { ..model([declaration, implementation], sources=[source]), identity, }
}

///|
test "unlinked declared revisions in dependency snapshots cannot select a first matching candidate" {
  let c = context(
    entities=[snapshot("requirement", "r1"), snapshot("other", "r7")],
    sources=[snapshot("urn:document:return", "doc-1")],
    implementations=[snapshot("urn:library", "lib-1")],
  )
  let base = evidence_graph(c, c)
  let chosen = context_dependency("d1", "r7", "doc-1", "lib-1")
  assert_eq(
    @intent.assess_claim(
      { ..base, dependencies: [chosen], },
      reference("claim"),
      c,
    ).claim_freshness,
    Current,
  )
  for
    changed in [
      context_dependency("d2", "r8", "doc-1", "lib-1"),
      context_dependency("d2", "r7", "doc-2", "lib-1"),
      context_dependency("d2", "r7", "doc-1", "lib-2"),
    ] {
    let drift = @intent.assess_claim(
      { ..base, dependencies: [changed], },
      reference("claim"),
      c,
    )
    assert_eq(drift.claim_freshness, Stale)
    let ambiguous = @intent.assess_claim(
      { ..base, dependencies: [chosen, changed], },
      reference("claim"),
      c,
    )
    assert_eq(ambiguous.claim_freshness, Inconclusive)
    assert_true(ambiguous.observations.all(o => o.freshness == Inconclusive))
  }
}

///|
test "explicitly linked dependency revisions are not replaced by other supplied snapshots" {
  let chosen = context_dependency("d1", "r7", "doc-1", "lib-1")
  let other = context_dependency("d2", "r8", "doc-2", "lib-2")
  let c = context(
    entities=[snapshot("other", "r7"), snapshot("implementation", "r1")],
    sources=[snapshot("urn:document:return", "doc-1")],
    implementations=[snapshot("urn:library", "lib-1")],
  )
  let base = evidence_graph(c, c)
  let subject : @intent.ResolvedRef = {
    model: chosen.identity,
    entity: snapshot("other", "r7"),
  }
  let entities = base.entities.map(e => {
    match e.content {
      Claim(claim) => { ..e, content: Claim({ ..claim, subject, }), }
      _ => e
    }
  })
  let report = @intent.assess_claim(
    { ..base, entities, dependencies: [chosen, other], },
    reference("claim"),
    c,
  )
  assert_eq(report.claim_freshness, Current)
  assert_true(report.observations.all(o => o.freshness == Current))
}

///|
test "claim-owned exact source refs take precedence over unlinked supplied revisions" {
  let c = context(entities=[snapshot("requirement", "r1")], sources=[
    snapshot("urn:document:return", "doc-1"),
  ])
  let base = evidence_graph(c, c)
  let source = @intent.adapt_kb_source(kb()).source
  let sources : Array[@intent.SourceRef] = [
    { source_id: source.id, anchor: id("return"), },
  ]
  let entities = base.entities.map(e => {
    if e.content is Claim(_) {
      { ..e, source_refs: sources, }
    } else {
      e
    }
  })
  let other = context_dependency("d2", "r8", "doc-2", "lib-2")
  let report = @intent.assess_claim(
    { ..base, entities, sources: [source], dependencies: [other], },
    reference("claim"),
    c,
  )
  assert_eq(report.claim_freshness, Current)
  assert_true(report.observations.all(o => o.freshness == Current))
}

///|
test "observation relationship source refs retain their owner's exact document snapshot" {
  let claim_context = context(entities=[snapshot("requirement", "r1")])
  let observed_context = context(entities=claim_context.entities(), sources=[
    snapshot("urn:document:return", "doc-1"),
  ])
  let base = evidence_graph(claim_context, observed_context)
  let source = @intent.adapt_kb_source(kb()).source
  let relationships = base.relationships.map(link => {
    if link.predicate == Supports {
      {
        ..link,
        source_refs: [{ source_id: source.id, anchor: id("return"), }],
      }
    } else {
      link
    }
  })
  let other = context_dependency("d2", "r8", "doc-2", "lib-2")
  let report = @intent.assess_claim(
    { ..base, relationships, sources: [source], dependencies: [other], },
    reference("claim"),
    observed_context,
  )
  assert_eq(report.observations[0].freshness, Current)
  assert_eq(report.observations[1].freshness, Inconclusive)
}

///|
test "unlinked declarations from distinct claim and evidence owners retain conflicting snapshots" {
  let c = context(entities=[snapshot("requirement", "r1")], sources=[
    snapshot("urn:document:return", "doc-1"),
  ])
  let claim_owner = {
    ..evidence_graph(c, c, with_evidence=false),
    sources: [@intent.adapt_kb_source(kb()).source],
  }
  let records = evidence_graph(c, c).entities.filter(e => {
    e.content is Evidence(_)
  })
  let evidence_owner = {
    ..model(records, sources=[
      @intent.adapt_kb_source(kb(revision="doc-2")).source,
    ]),
    identity: snapshot("urn:observations", "o1"),
  }
  let support : @intent.Relationship = {
    id: id("support"),
    predicate: Supports,
    subject: {
      model: evidence_owner.identity,
      entity: snapshot("analysis", "r1"),
    },
    target: Resolved(reference("claim")),
    source_refs: [],
    descriptive: None,
  }
  let graph = {
    ..model([], relationships=[support]),
    identity: snapshot("urn:outer", "outer-1"),
    dependencies: [claim_owner, evidence_owner],
  }
  let report = @intent.assess_claim(graph, reference("claim"), c)
  assert_eq(report.claim_freshness, Current)
  assert_eq(report.observations[0].freshness, Inconclusive)
}

///|
test "run evidence retains null versus absent, limits, clauses and rich values" {
  let c = context(entities=[snapshot("requirement", "r1")])
  let graph = evidence_graph(c, c, with_evidence=false)
  let rich = @ion_text.read_ion(
    "note::{integer:9007199254740993,decimal:123.4500,symbol:pending,typed:null.string}",
  )
  let run : @intent.RunObservation = {
    value_profile: id("urn:value-profile"),
    input: rich,
    output: Observed(@ion_text.read_ion("null")),
    clauses: [],
    evaluator: {
      id: id("urn:evaluator"),
      version: rev("1.0.0"),
      profile: id("urn:evaluation-profile"),
    },
    target: "wasm-gc",
    configuration: rich,
    limits: @intent.RunLimits::new(1000, 10),
    generated_case: Some(rich),
    type_arguments: None,
  }
  let observed = entity(
    "run",
    Evidence({
      origin: "hand-authored-fixture",
      context: c,
      observation: Run(run),
    }),
  )
  let absent = entity(
    "absent",
    Evidence({
      origin: "hand-authored-fixture",
      context: c,
      observation: Run({ ..run, output: Absent(NotInvoked), }),
    }),
  )
  let accepted = entity(
    "accepted",
    Evidence({
      origin: "hand-authored-fixture",
      context: c,
      observation: Review(
        id("human:reviewer"),
        Accepted,
        "Agreed interpretation",
      ),
    }),
  )
  let with_runs = {
    ..graph,
    entities: joined(graph.entities, [observed, absent, accepted]),
    relationships: [
      edge("run-link", Supports, "run", Resolved(reference("claim"))),
      edge("absent-link", Supports, "absent", Resolved(reference("claim"))),
      edge("review-link", Supports, "accepted", Resolved(reference("claim"))),
    ],
  }
  let report = @intent.assess_claim(with_runs, reference("claim"), c)
  assert_eq(report.observations.length(), 3)
  guard report.observations[0].evidence.observation is Run(retained) else {
    fail("lost run kind")
  }
  assert_true(retained.output is Observed(_))
  assert_eq(@ion_text.write_ion(retained.input), @ion_text.write_ion(rich))
  guard report.observations[1].evidence.observation is Run(missing) else {
    fail("lost absent run")
  }
  assert_true(missing.output is Absent(NotInvoked))
  assert_true(
    report.observations[2].evidence.observation is Review(_, Accepted, _),
  )
  assert_true(@intent.prd_view(with_runs).rows[0].contracts.is_empty())
  try @intent.RunLimits::new(0, 1) catch {
    _ => ()
  } noraise {
    _ => fail("zero steps")
  }
  try @intent.RunLimits::new(1, -1) catch {
    _ => ()
  } noraise {
    _ => fail("negative depth")
  }
}
