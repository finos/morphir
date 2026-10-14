///|
test "result projection preserves exact arithmetic and IEEE bits" {
  let runtime = @scheme.Runtime::new()
  assert_eq(
    @wire.field(result_tree(runtime.eval("9007199254740993")), "text"),
    @wire.text("9007199254740993"),
  )
  assert_eq(
    @wire.field(result_tree(runtime.eval("(/ 1 3)")), "text"),
    @wire.text("1/3"),
  )
  let negative_zero = result_tree(@scheme.Number(@scheme.Real(-0.0)))
  assert_eq(
    @wire.field(negative_zero, "bits"),
    @wire.text("9223372036854775808"),
  )
  assert_eq(@wire.field(negative_zero, "kind"), @wire.text("float"))
}

///|
test "result projection preserves records tuples constructors and improper tails" {
  let value = @scheme.Record(
    Map([
      ("z", @scheme.Tagged("example:main#some", [@scheme.Text("<script>\n")])),
      (
        "a",
        @scheme.Vector([@scheme.Boolean(true), @scheme.list([@scheme.Unit])]),
      ),
    ]),
  )
  let fields = @wire.array(@wire.field(result_tree(value), "fields"))
  assert_eq(@wire.field(fields[0], "name"), @wire.text("a"))
  assert_eq(
    @wire.field(@wire.field(fields[0], "value"), "kind"),
    @wire.text("tuple"),
  )
  let variant = @wire.field(fields[1], "value")
  assert_eq(@wire.field(variant, "tag"), @wire.text("example:main#some"))
  assert_eq(
    @wire.field(@wire.array(@wire.field(variant, "items"))[0], "text"),
    @wire.text(Json::string("<script>\n").stringify()),
  )
  let runtime = @scheme.Runtime::new()
  let pair = result_tree(runtime.eval("'(1 2 . 3)"))
  assert_eq(@wire.array(@wire.field(pair, "items")).length(), 2)
  assert_eq(@wire.field(@wire.field(pair, "tail"), "text"), @wire.text("3"))
}

///|
test "result projection bounds list size depth and scalar display" {
  let list = @scheme.list(Array::make(10000, @scheme.Boolean(true)))
  let items = @wire.array(@wire.field(result_tree(list), "items"))
  assert_eq(items.length(), 500)
  assert_eq(@wire.field(items[499], "kind"), @wire.text("truncated"))
  let mut deep = @scheme.Unit
  for _ in 0..<100 {
    deep = @scheme.Vector([deep])
  }
  let mut result = result_tree(deep)
  for _ in 0..<33 {
    result = @wire.array(@wire.field(result, "items"))[0]
  }
  assert_eq(@wire.field(result, "kind"), @wire.text("truncated"))
  let mut wide : @scheme.Value = @scheme.Vector(
    Array::make(10000, @scheme.Unit),
  )
  for _ in 0..<32 {
    wide = @scheme.Vector([wide])
  }
  let mut projected = result_tree(wide)
  for _ in 0..<32 {
    projected = @wire.array(@wire.field(projected, "items"))[0]
  }
  assert_true(@wire.array(@wire.field(projected, "items")).length() <= 500)
  let huge = Array::make(20000, "x").join("")
  assert_eq(
    @wire.field(result_tree(@scheme.Text(huge)), "kind"),
    @wire.text("truncated"),
  )
  assert_eq(
    @wire.field(result_tree(@scheme.Native("+")), "kind"),
    @wire.text("opaque"),
  )
}

///|
test "typed presentation truncates without changing canonical values" {
  let canonical : Json = {
    "type": "list",
    "items": Array::make(
      600,
      ({ "type": "int", "value": "9007199254740993" } : Json),
    ),
  }
  let tree = @outcomes.value_tree(canonical)
  let items = @wire.array(@wire.field(tree, "items"))
  assert_eq(items.length(), 500)
  assert_eq(@wire.field(items[499], "kind"), Json::string("truncated"))
  assert_eq(@wire.array(@wire.field(canonical, "items")).length(), 600)
  assert_eq(@wire.field(items[0], "text"), Json::string("9007199254740993"))
}
