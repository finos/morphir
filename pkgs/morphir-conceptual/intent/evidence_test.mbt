///|
fn context(
  model_revision~ : String = "m1",
  entities~ : Array[@intent.Snapshot] = [],
  sources~ : Array[@intent.Snapshot] = [],
  implementations~ : Array[@intent.Snapshot] = [],
) -> @intent.RevisionContext raise {
  @intent.RevisionContext::new(
    snapshot("urn:model", model_revision),
    entities~,
    sources~,
    implementations~,
  )
}

///|
fn evidence_graph(
  claim_context : @intent.RevisionContext,
  evidence_context : @intent.RevisionContext,
  source~ : @intent.Source? = None,
  with_evidence~ : Bool = true,
  model_revision~ : String = "m1",
) -> @intent.Model raise {
  let refs : Array[@intent.SourceRef] = match source {
    Some(s) => [{ source_id: s.id, anchor: id("return"), }]
    None => []
  }
  let req = entity(
    "requirement",
    Requirement(
      @intent.Category::parse("morphir:requirement-kind/functional"),
      "Keep identity",
      None,
    ),
    refs~,
  )
  let claim = entity(
    "claim",
    Claim({
      subject: reference("requirement", model_revision~),
      proposition: "The return preserves identity",
      author: id("human:reviewer"),
      scope: @ion_text.read_ion("{environment:demo}"),
      context: claim_context,
    }),
  )
  let analysis = entity(
    "analysis",
    Evidence({
      origin: "hand-authored-fixture",
      context: evidence_context,
      observation: Analysis(
        {
          id: id("urn:analyzer"),
          version: rev("1.0.0"),
          profile: id("urn:type-check/1"),
        },
        @ion_text.read_ion("{}"),
        @ion_text.read_ion("{wellTyped:true}"),
      ),
    }),
  )
  let review = entity(
    "review",
    Evidence({
      origin: "hand-authored-fixture",
      context: evidence_context,
      observation: Review(
        id("human:reviewer"),
        Rejected,
        "A counterexample remains.",
      ),
    }),
  )
  let entities = if with_evidence {
    [req, claim, analysis, review]
  } else {
    [req, claim]
  }
  let relationships = if with_evidence {
    [
      edge("support", Supports, "analysis", Resolved(reference("claim"))),
      edge("contradict", Contradicts, "review", Resolved(reference("claim"))),
    ]
  } else {
    []
  }
  let graph = model(
    entities,
    relationships~,
    sources=match source {
      Some(s) => [s]
      None => []
    },
  )
  let identity = snapshot("urn:model", model_revision)
  let relationships = graph.relationships.map(link => {
    ..link,
    subject: { ..link.subject, model: identity, },
    target: match link.target {
      Resolved(target) => Resolved({ ..target, model: identity, })
      other => other
    },
  })
  { ..graph, identity, relationships, }
}

///|
fn declared_dependencies_graph(
  entity_revision~ : String = "r7",
  document_revision~ : String = "doc-1",
  artifact_revision~ : String = "lib-1",
) -> (@intent.Model, @intent.RevisionContext) raise {
  let declared = context(
    entities=[snapshot("requirement", "r1"), snapshot("other", "r7")],
    sources=[snapshot("urn:document:return", "doc-1")],
    implementations=[snapshot("urn:library", "lib-1")],
  )
  let base = evidence_graph(declared, declared)
  let other = {
    ..entity("other", Intent("Unlinked dependency", None)),
    identity: snapshot("other", entity_revision),
  }
  let implementation = entity(
    "unlinked-implementation",
    Implementation(snapshot("urn:library", artifact_revision)),
  )
  (
    {
      ..base,
      entities: joined(base.entities, [other, implementation]),
      sources: [@intent.adapt_kb_source(kb(revision=document_revision)).source],
    },
    declared,
  )
}

///|
test "declared unlinked entity revisions are checked against supplied entities" {
  let (baseline, declared) = declared_dependencies_graph()
  assert_eq(
    @intent.assess_claim(baseline, reference("claim"), declared).observations[0].freshness,
    Current,
  )
  let (changed, _) = declared_dependencies_graph(entity_revision="r8")
  let assessed = @intent.assess_claim(changed, reference("claim"), declared)
  assert_eq(assessed.claim_freshness, Stale)
  assert_true(assessed.observations.all(o => o.freshness == Stale))
}

///|
test "declared unlinked document revisions are checked against supplied sources" {
  let (changed, declared) = declared_dependencies_graph(
    document_revision="doc-2",
  )
  let assessed = @intent.assess_claim(changed, reference("claim"), declared)
  assert_eq(assessed.claim_freshness, Stale)
  assert_true(assessed.observations.all(o => o.freshness == Stale))
}

///|
test "declared unlinked artifact revisions are checked against supplied implementations" {
  let (changed, declared) = declared_dependencies_graph(
    artifact_revision="lib-2",
  )
  let assessed = @intent.assess_claim(changed, reference("claim"), declared)
  assert_eq(assessed.claim_freshness, Stale)
  assert_true(assessed.observations.all(o => o.freshness == Stale))
}

///|
fn observation_only_context(
  dimension : Int32,
) -> (@intent.RevisionContext, @intent.RevisionContext) raise {
  let claim = context(entities=[snapshot("requirement", "r1")])
  let observation = context(
    entities=if dimension == 0 {
      [snapshot("requirement", "r1"), snapshot("observation-input", "r1")]
    } else {
      claim.entities()
    },
    sources=if dimension == 1 {
      [snapshot("observation-document", "s1")]
    } else {
      []
    },
    implementations=if dimension == 2 {
      [snapshot("observation-artifact", "i1")]
    } else {
      []
    },
  )
  (claim, observation)
}

///|
test "observation-only entity dependencies missing from requested context are inconclusive" {
  let (claim, observation) = observation_only_context(0)
  let graph = evidence_graph(claim, observation)
  assert_eq(
    @intent.assess_claim(graph, reference("claim"), claim).observations[0].freshness,
    Inconclusive,
  )
  assert_eq(
    @intent.assess_claim(graph, reference("claim"), observation).observations[0].freshness,
    Current,
  )
}

///|
test "observation-only source dependencies missing from requested context are inconclusive" {
  let (claim, observation) = observation_only_context(1)
  let graph = evidence_graph(claim, observation)
  assert_eq(
    @intent.assess_claim(graph, reference("claim"), claim).observations[0].freshness,
    Inconclusive,
  )
  assert_eq(
    @intent.assess_claim(graph, reference("claim"), observation).observations[0].freshness,
    Current,
  )
}

///|
test "observation-only implementation dependencies missing from requested context are inconclusive" {
  let (claim, observation) = observation_only_context(2)
  let graph = evidence_graph(claim, observation)
  assert_eq(
    @intent.assess_claim(graph, reference("claim"), claim).observations[0].freshness,
    Inconclusive,
  )
  assert_eq(
    @intent.assess_claim(graph, reference("claim"), observation).observations[0].freshness,
    Current,
  )
}

///|
test "current analysis and contradictory review remain distinct observations, not proof" {
  let current = context(entities=[snapshot("requirement", "r1")])
  let graph = evidence_graph(current, current)
  let report = @intent.assess_claim(graph, reference("claim"), current)
  assert_eq(report.availability, Present)
  assert_eq(report.claim_freshness, Current)
  assert_eq(report.observations.length(), 2)
  assert_eq(report.observations[0].polarity, Supporting)
  assert_eq(report.observations[1].polarity, Contradicting)
  assert_true(report.observations.all(o => o.freshness == Current))
  assert_true(report.observations[0].evidence.observation is Analysis(_, _, _))
  assert_true(
    report.observations[1].evidence.observation is Review(_, Rejected, _),
  )
  let empty = @intent.assess_claim(
    evidence_graph(current, current, with_evidence=false),
    reference("claim"),
    current,
  )
  assert_eq(empty.availability, Unknown)
  assert_true(empty.observations.is_empty())
}

///|
test "complete context compares every revision dimension and ignores member order" {
  let entities = [snapshot("requirement", "r1"), snapshot("other", "r7")]
  let sources = [snapshot("urn:document:return", "doc-1")]
  let implementations = [snapshot("urn:library", "lib-1")]
  let expected = context(entities~, sources~, implementations~)
  let graph = evidence_graph(expected, expected)
  let reordered = context(
    entities=[entities[1], entities[0]],
    sources~,
    implementations~,
  )
  assert_eq(
    @intent.assess_claim(graph, reference("claim"), reordered).observations[0].freshness,
    Current,
  )
  let changes = [
    context(model_revision="m2", entities~, sources~, implementations~),
    context(
      entities=[snapshot("requirement", "r2"), entities[1]],
      sources~,
      implementations~,
    ),
    context(
      entities~,
      sources=[snapshot("urn:document:return", "doc-2")],
      implementations~,
    ),
    context(entities~, sources~, implementations=[
      snapshot("urn:library", "lib-2"),
    ]),
    context(
      entities=joined(entities, [snapshot("extra", "r1")]),
      sources~,
      implementations~,
    ),
    context(
      entities~,
      sources=joined(sources, [snapshot("extra-source", "s1")]),
      implementations~,
    ),
    context(
      entities~,
      sources~,
      implementations=joined(implementations, [snapshot("extra-impl", "i1")]),
    ),
  ]
  for changed in changes {
    let assessment = @intent.assess_claim(graph, reference("claim"), changed)
    assert_eq(assessment.claim_freshness, Stale)
    assert_eq(assessment.observations[0].freshness, Stale)
  }
}

///|
test "missing context and duplicate context members cannot appear current" {
  let current = context(
    entities=[snapshot("requirement", "r1")],
    sources=[snapshot("source-document", "s1")],
    implementations=[snapshot("library", "i1")],
  )
  let incomplete = context(entities=[snapshot("requirement", "r1")])
  let missing = @intent.assess_claim(
    evidence_graph(current, incomplete),
    reference("claim"),
    current,
  )
  assert_eq(missing.observations[0].freshness, Inconclusive)
  let empty = context()
  let empty_both = @intent.assess_claim(
    evidence_graph(empty, empty),
    reference("claim"),
    empty,
  )
  assert_eq(empty_both.claim_freshness, Inconclusive)
  assert_eq(empty_both.observations[0].freshness, Inconclusive)
  let duplicates = [snapshot("duplicate", "r1"), snapshot("duplicate", "r2")]
  for which in [0, 1, 2] {
    try
      ignore(
        context(
          entities=if which == 0 { duplicates } else { [] },
          sources=if which == 1 { duplicates } else { [] },
          implementations=if which == 2 { duplicates } else { [] },
        ),
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("duplicate context IDs must fail")
    }
  }
  let owned = [snapshot("requirement", "r1")]
  let copied = context(entities=owned)
  owned.clear()
  assert_eq(copied.entities().length(), 1)
  copied.entities().clear()
  assert_eq(copied.entities().length(), 1)
}

///|
test "source moves retain current evidence; edits make historical evidence stale and omitted source inconclusive" {
  let before = @intent.adapt_kb_source(kb()).source
  let moved = @intent.adapt_kb_source(
      kb(locator="morphir/intent:/archive/0007-return.md"),
    ).source
  let edited = @intent.adapt_kb_source(
      kb(revision="doc-2", text="Accept partial returns.\n"),
    ).source
  let c1 = context(entities=[snapshot("requirement", "r1")], sources=[
    snapshot("urn:document:return", "doc-1"),
  ])
  let c2 = context(
    model_revision="m2",
    entities=[snapshot("requirement", "r1")],
    sources=[snapshot("urn:document:return", "doc-2")],
  )
  assert_eq(
    @intent.assess_claim(
      evidence_graph(c1, c1, source=Some(before)),
      reference("claim"),
      c1,
    ).observations[0].freshness,
    Current,
  )
  assert_eq(
    @intent.assess_claim(
      evidence_graph(c1, c1, source=Some(moved)),
      reference("claim"),
      c1,
    ).observations[0].freshness,
    Current,
  )
  assert_eq(
    @intent.assess_claim(
      evidence_graph(c2, c1, source=Some(edited), model_revision="m2"),
      reference("claim", model_revision="m2"),
      c2,
    ).observations[0].freshness,
    Stale,
  )
  let unpinned = context(entities=[snapshot("requirement", "r1")])
  assert_eq(
    @intent.assess_claim(
      evidence_graph(unpinned, unpinned, source=Some(before)),
      reference("claim"),
      unpinned,
    ).observations[0].freshness,
    Inconclusive,
  )
  let wrong_id = context(entities=[snapshot("requirement", "r1")], sources=[
    snapshot("urn:source:return", "doc-1"),
  ])
  assert_eq(
    @intent.assess_claim(
      evidence_graph(wrong_id, wrong_id, source=Some(before)),
      reference("claim"),
      wrong_id,
    ).observations[0].freshness,
    Inconclusive,
  )
}
