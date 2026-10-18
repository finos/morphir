///|
fn graph(text : String) -> @model.Graph raise {
  @model.Graph::decode(@ion_text.read_ion(text[:]))
}

///|
test "fixed M1 prose graph exposes records and exact retained source wording" {
  let model = graph(@fixtures.prose_only)
  assert_eq(model.identity().id.value(), "urn:example:lending")
  assert_eq(model.identity().revision.value(), "model-1")
  assert_eq(model.entities().length(), 4)
  let borrower = model.entity("urn:example:concept:borrower").unwrap()
  assert_true(borrower.kind() is Concept)
  assert_eq(borrower.identity().revision.value(), "c1")
  assert_eq(
    model.sources()[0].fragments()[0].text,
    "Track what borrowers still owe.\n\n  Retain the loan identity.\n",
  )
  assert_true(model.relationships()[2].target() is Unresolved(_, _, _))
  assert_true(
    model.to_ion().equals(@ion_text.read_ion(@fixtures.prose_only[:])),
  )
}

///|
test "fixed rich graphs retain every record including traits and concern fields" {
  for
    fixture in [
      @fixtures.mixed, @fixtures.independent_concerns, @fixtures.contract_kinds,
      @fixtures.traits, @fixtures.dictionary,
    ] {
    let model = graph(fixture)
    assert_true(model.to_ion().equals(@ion_text.read_ion(fixture[:])))
  }
  let model = graph(@fixtures.traits)
  assert_eq(model.trait_definitions().length(), 6)
  assert_eq(model.trait_applications().length(), 1)
  let app = model.trait_applications()[0]
  assert_eq(app.identity().id.value(), "urn:example:application:label")
  assert_true(app.payload().equals(@ion.IonValue::string("Quantity")))
  assert_true(
    app
    .provenance()
    .field("agent")
    .unwrap()
    .equals(@ion.IonValue::string("fixture-author")),
  )
}
