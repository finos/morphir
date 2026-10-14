///|
test "with_unknown adds the marker and keeps other extensions" {
  let attrs : @v4.TypeAttributes = {
    source: None,
    constraints: Map([]),
    extensions: Map([("other", @v4.Data::Text("x"))]),
  }
  assert_false(attrs.is_unknown())
  let marked = attrs.with_unknown()
  assert_true(marked.is_unknown())
  assert_eq(marked.extensions.get("other"), Some(@v4.Data::Text("x")))
  assert_eq(
    marked.extensions.get(@v4.INFERENCE_EXTENSION),
    Some(@v4.Data::Text(@v4.UNKNOWN_MARKER)),
  )
}

///|
test "another value under the inference key is not the marker" {
  let attrs : @v4.TypeAttributes = {
    source: None,
    constraints: Map([]),
    extensions: Map([(@v4.INFERENCE_EXTENSION, @v4.Data::Text("solved"))]),
  }
  assert_false(attrs.is_unknown())
}
