///|
fn id(s : String) -> @intent.Id raise {
  @intent.Id::parse(s)
}

///|
fn rev(s : String) -> @intent.Revision raise {
  @intent.Revision::parse(s)
}

///|
fn snapshot(id_ : String, revision : String) -> @intent.Snapshot raise {
  { id: id(id_), revision: rev(revision), }
}

///|
fn kb(
  bundle~ : String = "morphir/intent",
  document~ : String = "urn:document:return",
  revision~ : String = "doc-1",
  locator~ : String = "morphir/intent:/0007-return.md",
  text~ : String = "Track returns.\r\n  Keep identity.\n",
  state~ : @intent.KbState? = Some(Backlog),
) -> @intent.KbSnapshot raise {
  {
    origin: {
      bundle: id(bundle),
      short_id: id("0007"),
      slug: "0007-return",
      state,
    },
    document: snapshot(document, revision),
    source_id: id("urn:source:return"),
    intent: snapshot("urn:intent:return", "i1"),
    name: "Returns",
    locator,
    fragment: { anchor: id("return"), text, },
    descriptive: None,
  }
}

///|
test "KB moves preserve caller identities and exact excerpts; edits retain old snapshot" {
  let before = @intent.adapt_kb_source(kb())
  let moved = @intent.adapt_kb_source(
    kb(locator="morphir/intent:/archive/0007-returns.md"),
  )
  let edited = @intent.adapt_kb_source({
    ..kb(revision="doc-2", text="Track partial returns.\n"),
    intent: snapshot("urn:intent:return", "i2"),
  })
  assert_eq(before.source.id, moved.source.id)
  assert_eq(before.source.document, moved.source.document)
  assert_eq(before.intent.identity, moved.intent.identity)
  assert_eq(
    before.source.fragments[0].text,
    "Track returns.\r\n  Keep identity.\n",
  )
  assert_eq(edited.source.document.revision, Some(rev("doc-2")))
  assert_eq(before.source.document.revision, Some(rev("doc-1")))
  assert_eq(before.intent.source_refs, moved.intent.source_refs)
  assert_eq(edited.intent.identity.id, before.intent.identity.id)
  assert_eq(edited.intent.identity.revision, rev("i2"))
}

///|
test "same short KB id in two bundles does not create document identity" {
  let a = @intent.adapt_kb_source(kb())
  let b = @intent.adapt_kb_source({
    ..kb(bundle="other/intent", document="urn:other:return"),
    source_id: id("urn:other:source"),
    intent: snapshot("urn:other:intent", "i1"),
  })
  assert_eq(a.origin.short_id, b.origin.short_id)
  assert_true(a.origin.bundle != b.origin.bundle)
  assert_true(a.source.document.id != b.source.document.id)
  assert_true(a.intent.identity.id != b.intent.identity.id)
  assert_true(
    !@intent.inspect(model([a.intent, b.intent], sources=[a.source, b.source])).has_errors(),
  )
}

///|
test "identity boundaries reject emptiness without normalizing opaque values" {
  try @intent.Id::parse("") catch {
    _ => ()
  } noraise {
    _ => fail("empty identity")
  }
  try @intent.Revision::parse("") catch {
    _ => ()
  } noraise {
    _ => fail("empty revision")
  }
  assert_eq(id("  exact ID  ").value(), "  exact ID  ")
  try @intent.NonemptyText::parse("") catch {
    _ => ()
  } noraise {
    _ => fail("empty explanation")
  }
  assert_eq(
    @intent.NonemptyText::parse("  not supplied\n").value(),
    "  not supplied\n",
  )
  try @intent.Category::parse("custom") catch {
    _ => ()
  } noraise {
    _ => fail("missing category namespace")
  }
  assert_eq(
    @intent.Category::parse("example:availability").value(),
    "example:availability",
  )
}

///|
test "KB adaptation rejects a colliding source and intent identity" {
  let input = kb()
  try @intent.adapt_kb_source({ ..input, source_id: input.intent.id, }) catch {
    _ => ()
  } noraise {
    _ => fail("source/entity collision")
  }
}
