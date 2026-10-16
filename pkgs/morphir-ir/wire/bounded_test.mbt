///|
test "bounded wire decoder retains duplicate and whole-document checks" {
  assert_eq(
    @wire.parse_bounded("{\"a\":[true,null]}").stringify(),
    "{\"a\":[true,null]}",
  )
  for source in ["{\"a\":1,\"\\u0061\":1}", "{} {}"] {
    let mut rejected = false
    ignore(@wire.parse_bounded(source)) catch {
      _ => rejected = true
    }
    assert_true(rejected)
  }
}

///|
test "bounded wire decoder checks budgets before recursive allocation" {
  assert_eq(
    @wire.parse_bounded("[[0]]", max_depth=2),
    Json::array([Json::array([Json::number(0)])]),
  )
  assert_eq(
    @wire.parse_bounded("[0]", max_nodes=2),
    Json::array([Json::number(0)]),
  )
  assert_eq(
    @wire.parse_bounded("{\"a\":\"😀\"}", max_string_units=3).stringify(),
    "{\"a\":\"😀\"}",
  )
  for source in ["[[[0]]]", "[0,1]", "{\"ab\":\"😀\"}"] {
    let mut rejected = false
    ignore(
      @wire.parse_bounded(source, max_depth=2, max_nodes=2, max_string_units=3),
    ) catch {
      _ => rejected = true
    }
    assert_true(rejected)
  }
}

///|
test "historical unbounded entry retains its depth diagnostic" {
  let mut code = "accepted"
  ignore(@wire.parse("[".repeat(513) + "0" + "]".repeat(513))) catch {
    @wire.Invalid(value, _) => code = value
  }
  assert_eq(code, "invalid_json")
}
