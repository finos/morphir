///|
fn scalar_type(text : String) -> @model.Type raise {
  read_type(@core_json.parse(text))
}

///|
test "scalar Union decodes one interpretation and collapses duplicate members" {
  let t = scalar_type(
    "{\"Union\":[\"morphir/SDK:string#string\",\"morphir/SDK:string#string\"]}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Decoded(StringLiteral("ok")),
  )
  assert_eq(decode_scalar_json("false", t, StrictJsonScalars), Rejected)
}

///|
test "scalar Union treats Int and Float as distinct and supports integral decimal tokens" {
  let t = scalar_type(
    "{\"Union\":[\"morphir/SDK:basics#int\",\"morphir/SDK:basics#float\"]}",
  )
  for text in ["1", "1.0", "1e0"] {
    guard decode_scalar_json(text, t, StrictJsonScalars) is Ambiguous(xs) else {
      fail("numeric ambiguity lost")
    }
    assert_eq(xs.length(), 2)
    assert_true(xs.contains(IntegerLiteral("1")))
    assert_true(xs.contains(FloatLiteral(1.0)))
  }
  assert_eq(
    decode_scalar_json("1", t, IntegerTokenAsInt),
    Decoded(IntegerLiteral("1")),
  )
  assert_eq(
    decode_scalar_json("1.0", t, IntegerTokenAsInt),
    Decoded(IntegerLiteral("1")),
  )
  assert_eq(
    decode_scalar_json("1e0", t, IntegerTokenAsInt),
    Decoded(IntegerLiteral("1")),
  )
}

///|
test "scalar Union unsupported arms prevent a uniqueness claim" {
  let t = scalar_type(
    "{\"Union\":[\"morphir/SDK:string#string\",\"example:opaque#id\"]}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Unsupported(UnsupportedType),
  )
}

///|
test "scalar Union retains outer refinement obligations and rejects wrong scalar shapes" {
  let t = scalar_type(
    "{\"Union\":{\"attributes\":{\"extensions\":{\"unknown\":true}},\"alternatives\":[\"morphir/SDK:string#string\",\"morphir/SDK:basics#int\"]}}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Unsupported(UnsupportedRefinement),
  )
  assert_eq(decode_scalar_json("false", t, StrictJsonScalars), Rejected)
}

///|
test "scalar Union checks member refinements and preserves proved numeric ambiguity" {
  let t = scalar_type(
    "{\"Union\":[{\"Reference\":{\"attributes\":{\"extensions\":{\"unknown\":true}},\"fqname\":\"morphir/SDK:basics#int\"}},\"morphir/SDK:string#string\"]}",
  )
  assert_eq(
    decode_scalar_json("1", t, StrictJsonScalars),
    Unsupported(UnsupportedRefinement),
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Decoded(StringLiteral("ok")),
  )
  let ambiguous = scalar_type(
    "{\"Union\":[\"morphir/SDK:basics#float\",\"example:opaque#id\",\"morphir/SDK:basics#int\"]}",
  )
  assert_true(
    decode_scalar_json("1", ambiguous, StrictJsonScalars) is Ambiguous(_),
  )
}

///|
test "scalar codec refuses unknown profiles and numeric precision outside its bound" {
  try ScalarProfile::parse("guess-first") catch {
    @wire.Invalid(code, _) => assert_eq(code, "unsupported_scalar_profile")
  } noraise {
    _ => fail("unknown profile accepted")
  }
  let t = scalar_type("\"morphir/SDK:basics#float\"")
  for text in ["9007199254740993", "1e-999"] {
    assert_eq(
      decode_scalar_json(text, t, StrictJsonScalars),
      Unsupported(NumericLimit),
    )
  }
  let arm = scalar_type("\"morphir/SDK:string#string\"")
  let big : @model.Type = Union(Default::default(), Array::make(300, arm))
  assert_eq(
    decode_scalar_json("\"ok\"", big, StrictJsonScalars),
    Unsupported(WorkLimit),
  )
}

///|
test "scalar decoder resolves visible alias overlap and retains alias occurrence obligations" {
  let file = read(
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"example\",\"def\":{\"modules\":{\"types\":{\"Public\":{\"types\":{\"label\":{\"Public\":{\"value\":{\"TypeAliasDefinition\":{\"typeParams\":[],\"typeExp\":\"morphir/SDK:string#string\"}}}},\"cycle\":{\"Public\":{\"value\":{\"TypeAliasDefinition\":{\"typeParams\":[],\"typeExp\":\"example:types#cycle\"}}}}},\"values\":{}}}}}}}}",
  )
  let decoder = ScalarDecoder::from(file, StrictJsonScalars)
  let overlap = scalar_type(
    "{\"Union\":[\"morphir/SDK:string#string\",\"example:types#label\"]}",
  )
  assert_eq(decoder.decode("\"ok\"", overlap), Decoded(StringLiteral("ok")))
  assert_eq(
    decoder.decode("1", scalar_type("\"example:types#cycle\"")),
    Unsupported(CyclicAlias),
  )
  let refined = scalar_type(
    "{\"Reference\":{\"attributes\":{\"extensions\":{\"unknown\":true}},\"fqname\":\"example:types#label\"}}",
  )
  assert_eq(
    decoder.decode("\"ok\"", refined),
    Unsupported(UnsupportedRefinement),
  )
}

///|
test "scalar Union textual provenance is descriptive on outer and member types" {
  for
    text in [
      "{\"Union\":{\"attributes\":{\"extensions\":{\"example/union:provenance#note\":\"note\"}},\"alternatives\":[\"morphir/SDK:string#string\",\"morphir/SDK:basics#int\"]}}",
      "{\"Union\":[{\"Reference\":{\"attributes\":{\"extensions\":{\"example/union:provenance#note\":\"note\"}},\"fqname\":\"morphir/SDK:string#string\"}},\"morphir/SDK:basics#int\"]}",
    ] {
    assert_eq(
      decode_scalar_json("\"ok\"", scalar_type(text), StrictJsonScalars),
      Decoded(StringLiteral("ok")),
    )
  }
  let invalid = scalar_type(
    "{\"Union\":{\"attributes\":{\"extensions\":{\"example/union:provenance#note\":true}},\"alternatives\":[\"morphir/SDK:string#string\",\"morphir/SDK:basics#int\"]}}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", invalid, StrictJsonScalars),
    Unsupported(UnsupportedRefinement),
  )
}

///|
fn application_scalar_decoder() -> ScalarDecoder raise {
  let text =
    #|{"formatVersion":4,"distribution":{"Application":{
    #|  "packageName":"app",
    #|  "dependencies":{
    #|    "shared":{"modules":{
    #|      "types":{"Public":{"types":{
    #|        "label":{"Public":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"morphir/SDK:string#string"}}}},
    #|        "transitive":{"Public":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"other:types#base"}}}},
    #|        "hidden":{"Private":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"morphir/SDK:string#string"}}}},
    #|        "via-hidden":{"Public":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"shared:types#hidden"}}}},
    #|        "refined":{"Public":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":{"Reference":{"attributes":{"extensions":{"unknown":true}},"fqname":"morphir/SDK:string#string"}}}}}},
    #|        "generic":{"Public":{"value":{"TypeAliasDefinition":{"typeParams":["a"],"typeExp":"morphir/SDK:string#string"}}}},
    #|        "custom":{"Public":{"value":{"CustomTypeDefinition":{"typeParams":[],"access":"Public","constructors":{"custom":[]}}}}},
    #|        "opaque":{"Public":{"value":{"CustomTypeDefinition":{"typeParams":[],"access":"Private","constructors":{"opaque":[]}}}}}
    #|      },"values":{}}},
    #|      "private-module":{"Private":{"types":{
    #|        "label":{"Public":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"morphir/SDK:string#string"}}}}
    #|      },"values":{}}}
    #|    }},
    #|    "other":{"modules":{"types":{"Public":{"types":{
    #|      "base":{"Public":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"morphir/SDK:string#string"}}}}
    #|    },"values":{}}}}}
    #|  },
    #|  "def":{"modules":{"internal":{"Private":{"types":{
    #|    "label":{"Private":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"morphir/SDK:string#string"}}}}
    #|  },"values":{}}}}},
    #|  "entryPoints":{}
    #|}}}
  ScalarDecoder::from(read(text), StrictJsonScalars)
}

///|
test "Application scalar decoder resolves public bundled aliases and overlap" {
  let decoder = application_scalar_decoder()
  for
    text in [
      "\"shared:types#label\"", "\"shared:types#transitive\"", "\"app:internal#label\"",
      "{\"Union\":[\"morphir/SDK:string#string\",\"shared:types#label\"]}",
    ] {
    assert_eq(
      decoder.decode("\"ok\"", scalar_type(text)),
      Decoded(StringLiteral("ok")),
    )
  }
}

///|
test "Application scalar decoder respects bundled visibility and scalar support bounds" {
  let decoder = application_scalar_decoder()
  for
    text in [
      "\"shared:types#hidden\"", "\"shared:private-module#label\"", "\"shared:types#via-hidden\"",
      "\"shared:types#custom\"", "\"shared:types#opaque\"", "{\"Reference\":{\"fqname\":\"shared:types#generic\",\"args\":[\"morphir/SDK:string#string\"]}}",
    ] {
    assert_eq(
      decoder.decode("\"ok\"", scalar_type(text)),
      Unsupported(UnsupportedType),
    )
  }
}

///|
test "Application scalar alias decoding retains reference and body obligations" {
  let decoder = application_scalar_decoder()
  let occurrence = scalar_type(
    "{\"Reference\":{\"attributes\":{\"extensions\":{\"unknown\":true}},\"fqname\":\"shared:types#label\"}}",
  )
  assert_eq(
    decoder.decode("\"ok\"", occurrence),
    Unsupported(UnsupportedRefinement),
  )
  let body = scalar_type("\"shared:types#refined\"")
  assert_eq(decoder.decode("\"ok\"", body), Unsupported(UnsupportedRefinement))
  assert_eq(decoder.decode("1", body), Rejected)
}
