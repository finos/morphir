///|
fn profile(tpe : Json, definitions~ : Array[Json] = []) -> Json {
  { "inputs": [{ "label": "input", "type": tpe }], "definitions": definitions }
}

///|
test "typed edits preserve exact scalar payloads and numeric drafts" {
  let initial = "[{\"type\":\"decimal\",\"coefficient\":\"9007199254740993\",\"exponent\":0}]"
  let draft = @arguments.edit(
    initial,
    Scalar([Index(0), Field("exponent")], "float", "-"),
  )
  assert_eq(
    @arguments.typed_form_error(profile({ "type": "decimal" }), draft),
    None,
  )
  let complete = @arguments.edit(
    draft,
    Scalar([Index(0), Field("exponent")], "float", "-2"),
  )
  assert_eq(
    @wire.field(@wire.array(@wire.parse(complete))[0], "coefficient"),
    Json::string("9007199254740993"),
  )
  let negative_zero = @arguments.edit(
    "[{\"type\":\"float64\",\"bits\":\"0\"}]",
    Float64([Index(0), Field("bits")], "-0.0"),
  )
  let value = @wire.array(@wire.parse(negative_zero))[0]
  assert_eq(@wire.field(value, "bits"), Json::string("9223372036854775808"))
  assert_eq(@arguments.float64_text(value), "-0.0")
  let partial = @arguments.edit(
    negative_zero,
    Float64([Index(0), Field("bits")], "1e"),
  )
  assert_eq(
    @arguments.typed_form_error(profile({ "type": "float64" }), partial),
    None,
  )
  assert_eq(@arguments.float64_text(@wire.array(@wire.parse(partial))[0]), "1e")
}

///|
test "text edits preserve UTF16 pairs while isolated units stay editable" {
  let text = @arguments.edit(
    "[{\"type\":\"text\",\"units\":[]}]",
    TextUnits([Index(0), Field("units")], "A😀\n"),
  )
  let value = @wire.array(@wire.parse(text))[0]
  assert_eq(
    @wire.field(value, "units"),
    Json::array([
      Json::number(65),
      Json::number(55357),
      Json::number(56832),
      Json::number(10),
    ]),
  )
  assert_eq(@arguments.unicode_text(value), Some("A😀\n"))
  let isolated : Json = { "type": "text", "units": [55296, 0] }
  assert_eq(@arguments.unicode_text(isolated), None)
  assert_eq(
    @arguments.typed_form_error(
      profile({ "type": "text" }),
      Json::array([isolated]).stringify(),
    ),
    None,
  )
}

///|
test "record order is retained and incompatible tags owners fields remain intact" {
  let schema : Json = {
    "type": "record",
    "fields": [
      { "name": "a", "type": { "type": "int" } },
      { "name": "b", "type": { "type": "bool" } },
    ],
  }
  let original : Json = [
    {
      "type": "record",
      "fields": [
        { "name": "b", "value": { "type": "bool", "value": true } },
        { "name": "a", "value": { "type": "int", "value": "9" } },
      ],
    },
  ]
  assert_eq(
    @arguments.typed_form_error(profile(schema), original.stringify()),
    None,
  )
  let edited = @arguments.edit(
    original.stringify(),
    Scalar(
      [Index(0), Field("fields"), Index(1), Field("value"), Field("value")],
      "int",
      "9007199254740993",
    ),
  )
  let fields = @wire.array(
    @wire.field(@wire.array(@wire.parse(edited))[0], "fields"),
  )
  assert_eq(@wire.field(fields[0], "name"), Json::string("b"))
  assert_eq(
    @wire.field(@wire.field(fields[0], "value"), "value"),
    Json::boolean(true),
  )
  let invalid : Array[Json] = [
    [{ "type": "int", "value": "0" }],
    [
      {
        "type": "record",
        "fields": [
          { "name": "a", "value": { "type": "int", "value": "0" } },
          { "name": "a", "value": { "type": "int", "value": "1" } },
        ],
      },
    ],
    [
      {
        "type": "record",
        "fields": [
          { "name": "a", "value": { "type": "int", "value": "0" } },
          { "name": "b", "value": { "type": "bool", "value": true } },
        ],
        "extra": true,
      },
    ],
  ]
  for value in invalid {
    assert_true(
      @arguments.typed_form_error(profile(schema), value.stringify()) is Some(_),
    )
  }
}

///|
test "recursive registries have bounded defaults and forms with JSON fallback" {
  let schema : Json = { "type": "custom", "name": "demo:tree#tree" }
  let definitions : Array[Json] = [
    {
      "name": "demo:tree#tree",
      "constructors": [
        { "name": "demo:tree#branch", "inputs": [schema] },
        { "name": "demo:tree#empty", "inputs": [] },
      ],
    },
  ]
  let default_value = @arguments.typed_default(schema, definitions)
  assert_eq(@wire.field(default_value, "tag"), Json::string("demo:tree#empty"))
  let nested : Json = {
    "type": "custom",
    "owner": "demo:tree#tree",
    "tag": "demo:tree#branch",
    "items": [default_value],
  }
  assert_eq(
    @arguments.typed_form_error(
      profile(schema, definitions~),
      Json::array([nested]).stringify(),
    ),
    None,
  )
  let wrong_owner : Json = {
    "type": "custom",
    "owner": "other:tree#tree",
    "tag": "demo:tree#empty",
    "items": [],
  }
  assert_true(
    @arguments.typed_form_error(
      profile(schema, definitions~),
      Json::array([wrong_owner]).stringify(),
    )
    is Some(_),
  )
  let large : Json = [
    {
      "type": "list",
      "items": Array::make(250, ({ "type": "int", "value": "0" } : Json)),
    },
  ]
  assert_true(
    @arguments.typed_form_error(
      profile({ "type": "list", "item": { "type": "int" } }),
      large.stringify(),
    )
    .unwrap()
    .contains("too large"),
  )
  let impossible : Array[Json] = [
    {
      "name": "demo:tree#tree",
      "constructors": [{ "name": "demo:tree#branch", "inputs": [schema] }],
    },
  ]
  assert_true(
    try {
      ignore(@arguments.typed_default(schema, impossible))
      false
    } catch {
      _ => true
    },
  )
}
