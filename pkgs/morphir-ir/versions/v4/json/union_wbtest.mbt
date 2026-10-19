///|
test "Union accepts compact syntax and preserves nested duplicate alternatives" {
  let wire = @core_json.parse("{\"Union\":[\"a\",{\"Union\":[\"a\",\"a\"]}]}")
  assert_eq(write_type(read_type(wire)), wire)
}

///|
test "Union expanded empty attributes canonicalize independently of members" {
  let wire = @core_json.parse(
    "{\"Union\":{\"attributes\":{},\"alternatives\":[\"a\",\"b\"]}}",
  )
  assert_eq(
    write_type(read_type(wire)),
    @core_json.parse("{\"Union\":[\"a\",\"b\"]}"),
  )
}

///|
test "Union rejects insufficient authored arity" {
  for wire in ["{\"Union\":[]}", "{\"Union\":[\"a\"]}"] {
    try read_type(@core_json.parse(wire)) catch {
      @wire.Invalid(code, _) => assert_eq(code, "invalid_arity")
      _ => fail("Expected invalid_arity")
    } noraise {
      _ => fail("Expected invalid_arity")
    }
  }
}

///|
test "Union nested wire forms preserve outer and member attributes in signatures and facts" {
  let union = "{\"Union\":{\"attributes\":{\"source\":{\"startLine\":1,\"startColumn\":2,\"endLine\":3,\"endColumn\":4},\"extensions\":{\"note\":\"outer\"}},\"alternatives\":[{\"Reference\":{\"attributes\":{\"constraints\":{\"positive\":true},\"extensions\":{\"note\":\"member\"}},\"fqname\":\"morphir/SDK:basics#int\",\"args\":[]}},\"morphir/SDK:string#string\"]}}"
  let function = "{\"Function\":{\"parameterType\":{\"Record\":{\"fields\":{\"value\":" +
    union +
    "}}},\"returnType\":" +
    union +
    "}}"
  let wire = @core_json.parse(function)
  assert_eq(write_type(read_type(wire)), wire)
  let alias_wire = @core_json.parse(
    "{\"TypeAliasDefinition\":{\"typeParams\":[],\"typeExp\":" + function + "}}",
  )
  assert_eq(write_type_definition(read_type_definition(alias_wire)), alias_wire)
  let hole_wire = @core_json.parse(
    "{\"Hole\":{\"attributes\":{\"inferredType\":" +
    union +
    "},\"reason\":{\"DeletedDuringRefactor\":{\"tx-id\":\"x\"}},\"expectedType\":" +
    union +
    "}}",
  )
  assert_eq(write_value(read_value(hole_wire)), hole_wire)
}

///|
test "Union writer and malformed decoder refuse invalid authored forms" {
  for xs in [[], [@model.Type::Unit(Default::default())]] {
    try write_type(@model.Type::Union(Default::default(), xs)) catch {
      @wire.Invalid(code, _) => assert_eq(code, "invalid_arity")
      _ => fail("wrong error")
    } noraise {
      _ => fail("invalid Union written")
    }
  }
  for
    text in [
      "{\"Union\":{}}", "{\"Union\":{\"alternatives\":true}}", "{\"Union\":[true,\"a\"]}",
      "{\"Union\":[\"a\",\"b\"],\"Tuple\":[]}",
    ] {
    try read_type(@core_json.parse(text)) catch {
      @wire.Invalid(_, _) => ()
      _ => fail("wrong error")
    } noraise {
      _ => fail("malformed Union accepted")
    }
  }
}
