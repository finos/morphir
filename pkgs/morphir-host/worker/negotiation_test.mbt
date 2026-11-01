///|
/// The compile tuples of IR 3.0.0, which come after those of IR 4.0.0.
let ion_tuple_ir3 : @worker.ModelTuple = @worker.ModelTuple::new(
  CompileModel,
  MorphirModel,
  IonBinary,
  V0_1_0Draft1,
  V3_0_0,
)

///|
let json_tuple_ir3 : @worker.ModelTuple = @worker.ModelTuple::new(
  CompileModel,
  MorphirIr,
  MorphirJson,
  V0_1_0Draft1,
  V3_0_0,
)

///|
fn ir_name(text : String) -> @worker.IrVersionName {
  @worker.IrVersionName::parse(text) catch {
    error => abort(error.to_string())
  }
}

///|
fn claims_of(tuples : Array[@worker.ModelTuple]) -> @worker.Claims {
  @worker.Claims::from_describe(model_result(tuples)) catch {
    error => abort(error.to_string())
  }
}

///|
/// Selects an offer and gives the tuples, or the refusal code.
fn selected(
  claims : @worker.Claims,
  operation~ : @worker.Operation = CompileModel,
  codec? : @worker.ModelCodec,
  ir_version? : String,
) -> Result[@worker.Offer, @worker.RefusalCode] {
  try
    @worker.Offer::select(
      claims,
      operation,
      codec?,
      ir_version?=ir_version.map(ir_name),
    )
  catch {
    Refusal(code~, ..) => Err(code)
  } noraise {
    offer => Ok(offer)
  }
}

///|
test "IR version: both tuple versions decode, and others stay outside the closed set" {
  let tuple = @worker.ModelTuple::parse(
    "morphir.frontend.compileModel", "morphir-ir", "morphir-json", "0.1.0-draft.1",
    "3.0.0",
  )
  assert_eq(tuple, json_tuple_ir3)
  assert_eq(tuple.ir_version.to_string(), "3.0.0")
  let unknown = try
    @worker.ModelTuple::parse(
      "morphir.frontend.compileModel", "morphir-ir", "morphir-json", "0.1.0-draft.1",
      "5.0.0",
    )
  catch {
    UnknownModelTuplePart(part) => Some(part)
    _ => None
  } noraise {
    _ => None
  }
  assert_eq(unknown, Some("5.0.0"))
  // The versions order by number, so the highest is the newest.
  assert_true(@worker.IrVersion::V3_0_0 < @worker.IrVersion::V4_0_0)
}

///|
test "IR version: a selection names one version exactly, or a major" {
  let serves = (version : String, selected : String) => {
    ir_name(version).serves(ir_name(selected))
  }
  assert_true(serves("4.0.0", "4.0.0"))
  assert_true(serves("4.0.0", "4"))
  assert_true(serves("4.1.0", "4"))
  assert_true(serves("4", "4"))
  // A full selection does not match a major-only version, or another minor.
  assert_false(serves("4", "4.0.0"))
  assert_false(serves("4.2.0", "4.1.0"))
  assert_false(serves("3.0.0", "4"))
  // A major is the whole first part: `4` does not select `40.0.0`.
  assert_false(serves("40.0.0", "4"))
  assert_false(serves("3.0.0", "3.0"))
  assert_true(@worker.IrVersion::V3_0_0.serves(ir_name("3")))
  assert_true(@worker.IrVersion::V3_0_0.serves(ir_name("3.0.0")))
  assert_false(@worker.IrVersion::V3_0_0.serves(ir_name("4")))
  assert_false(@worker.IrVersion::V4_0_0.serves(ir_name("4.0")))
}

///|
test "host tuples: IR 4.0.0 first, each IR with Ion then JSON, for each model operation" {
  assert_eq(@worker.ModelOperation::CompileModel.host_tuples(), [
    ion_tuple, json_compile_tuple, ion_tuple_ir3, json_tuple_ir3,
  ])
  let generate = @worker.ModelOperation::GenerateModel.host_tuples()
  assert_eq(generate.length(), 4)
  assert_true(generate.iter().all(tuple => tuple.operation is GenerateModel))
  assert_eq(generate.map(tuple => tuple.ir_version.to_string()), [
    "4.0.0", "4.0.0", "3.0.0", "3.0.0",
  ])
  assert_eq(generate.map(tuple => tuple.codec.to_string()), [
    "ion-binary", "morphir-json", "ion-binary", "morphir-json",
  ])
}

///|
test "offer selection: without a requirement the host offers all four tuples, also to a guest with one" {
  let every : @worker.Offer = Model([
    ion_tuple, json_compile_tuple, ion_tuple_ir3, json_tuple_ir3,
  ])
  // Only an IR 3 guest: it is still offered IR 4 first, so the order stays the
  // only signal of the default.
  assert_eq(selected(claims_of([json_tuple_ir3])), Ok(every))
  assert_eq(selected(claims_of([ion_tuple])), Ok(every))
}

///|
test "offer selection: --ir-version narrows the offer to the tuples of that version" {
  let python = claims_of([json_tuple_ir3, json_compile_tuple])
  let ir3 : @worker.Offer = Model([ion_tuple_ir3, json_tuple_ir3])
  let ir4 : @worker.Offer = Model([ion_tuple, json_compile_tuple])
  assert_eq(selected(python, ir_version="3"), Ok(ir3))
  assert_eq(selected(python, ir_version="3.0.0"), Ok(ir3))
  assert_eq(selected(python, ir_version="4"), Ok(ir4))
  assert_eq(selected(python, ir_version="4.0.0"), Ok(ir4))
}

///|
test "offer selection: --ir-version with no matching tuple is tuple_unavailable" {
  // The MoonBit guest claims only IR 4.0.0.
  let ir4_only = claims_of([ion_tuple, json_compile_tuple])
  assert_eq(selected(ir4_only, ir_version="3"), Err(TupleUnavailable))
  assert_eq(selected(ir4_only, ir_version="3.0.0"), Err(TupleUnavailable))
  // A guest with only IR 3 tuples cannot serve IR 4.
  let ir3_only = claims_of([json_tuple_ir3])
  assert_eq(selected(ir3_only, ir_version="4"), Err(TupleUnavailable))
  // A version that the host has no tuple for, and a minor that no tuple has.
  let both = claims_of([json_tuple_ir3, json_compile_tuple])
  assert_eq(selected(both, ir_version="5"), Err(TupleUnavailable))
  assert_eq(selected(both, ir_version="4.1.0"), Err(TupleUnavailable))
  assert_eq(selected(both, ir_version="4.0"), Err(TupleUnavailable))
}

///|
test "offer selection: --ir-version and --model-format intersect" {
  let both = claims_of([
    ion_tuple, json_compile_tuple, ion_tuple_ir3, json_tuple_ir3,
  ])
  assert_eq(
    selected(both, codec=MorphirJson, ir_version="3"),
    Ok(Model([json_tuple_ir3])),
  )
  assert_eq(
    selected(both, codec=IonBinary, ir_version="4.0.0"),
    Ok(Model([ion_tuple])),
  )
  // --model-format alone keeps each IR version of that format, IR 4.0.0 first.
  assert_eq(
    selected(both, codec=MorphirJson),
    Ok(Model([json_compile_tuple, json_tuple_ir3])),
  )
  // Each flag has a match; together they have none.
  let crossed = claims_of([ion_tuple, json_tuple_ir3])
  assert_eq(
    selected(crossed, codec=IonBinary, ir_version="3"),
    Err(TupleUnavailable),
  )
  assert_eq(
    selected(crossed, codec=MorphirJson, ir_version="4"),
    Err(TupleUnavailable),
  )
  assert_eq(
    selected(crossed, codec=MorphirJson, ir_version="3"),
    Ok(Model([json_tuple_ir3])),
  )
}

///|
test "offer selection: the generate operation narrows by IR version too" {
  let generate_ir3 = @worker.ModelTuple::new(
    GenerateModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V3_0_0,
  )
  let claims = claims_of([generate_ir3])
  guard selected(claims, operation=GenerateModel, ir_version="3")
    is Ok(Model(tuples)) else {
    fail("no IR 3 generate offer")
  }
  assert_true(tuples.contains(generate_ir3))
  assert_true(tuples.iter().all(tuple => tuple.ir_version is V3_0_0))
  assert_eq(
    selected(claims, operation=GenerateModel, ir_version="4"),
    Err(TupleUnavailable),
  )
}

///|
test "compile line: a guest that claims the model line compiles on it, only a legacy guest on MEP 0.1" {
  assert_eq(legacy_claims().compile_operation(), Compile)
  assert_eq(
    claims_of([json_tuple_ir3, json_compile_tuple]).compile_operation(),
    CompileModel,
  )
  // Both lines and both compile methods: the model line. There is no choice
  // of MEP 0.1 from the requested IR version.
  let both_lines = @worker.Claims::new(
    @worker.ExtensionId::parse("both"),
    @worker.ExtensionVersion::parse("1"),
    protocol_lines=[Mep0_1, Mep0_2Draft1],
    operations=[Compile, CompileModel],
    model_tuples=[json_compile_tuple],
  )
  assert_eq(both_lines.compile_operation(), CompileModel)
  assert_eq(selected(both_lines, ir_version="3"), Err(TupleUnavailable))
  // A model transport on a guest that claims only MEP 0.1 enables nothing.
  let legacy_with_tuples = @worker.Claims::new(
    @worker.ExtensionId::parse("legacy"),
    @worker.ExtensionVersion::parse("1"),
    protocol_lines=[Mep0_1],
    operations=[Compile, CompileModel],
    model_tuples=[json_compile_tuple],
  )
  assert_eq(legacy_with_tuples.compile_operation(), Compile)
}

///|
test "compile line: both lines with no compile tuple is tuple_unavailable, not MEP 0.1" {
  let legacy_compile_only = @worker.Claims::new(
    @worker.ExtensionId::parse("both"),
    @worker.ExtensionVersion::parse("1"),
    protocol_lines=[Mep0_1, Mep0_2Draft1],
    operations=[Compile, GenerateModel],
    model_tuples=[json_generate_tuple],
  )
  assert_eq(legacy_compile_only.compile_operation(), CompileModel)
  assert_eq(selected(legacy_compile_only), Err(TupleUnavailable))
  // A guest on the model line alone does not compile at all.
  let generate_only = @worker.Claims::new(
    @worker.ExtensionId::parse("generate"),
    @worker.ExtensionVersion::parse("1"),
    protocol_lines=[Mep0_2Draft1],
    operations=[Compile, GenerateModel],
    model_tuples=[json_generate_tuple],
  )
  assert_eq(selected(generate_only), Err(CapabilityUnavailable))
}

///|
test "session: an IR 3 agreement sets the output and the session uses it" {
  let claims = claims_of([json_tuple_ir3, json_compile_tuple])
  let offer = @worker.Offer::select(
    claims,
    CompileModel,
    ir_version=ir_name("3"),
  )
  assert_eq(offer, Model([ion_tuple_ir3, json_tuple_ir3]))
  let (conversation, step) = @worker.Conversation::activate(
    offer,
    expected=claims,
  )
  guard sends(step)[0].json()
    is Object({ "params": Object({ "modelTransport": transport, .. }), .. }) &&
    transport is Object({ "tuples": tuples, .. }) else {
    fail("no model transport offer")
  }
  assert_eq(tuples, [ion_tuple_ir3.to_json(), json_tuple_ir3.to_json()])
  let (conversation, step) = conversation.on(
    answer(1, model_result([json_tuple_ir3], protocol="0.2.0-draft.1")),
  )
  guard step is Activated(negotiated, ..) else {
    fail("not activated: \{@debug.to_string(step)}")
  }
  assert_eq(negotiated.tuple, Some(json_tuple_ir3))
  let request = @worker.CompileRequest::new({
    "languageId": "python",
    "options": { "typesOnly": false, "irVersion": "3.0.0" },
  })
  let (_, step) = conversation.compile(request)
  guard sends(step)[0].json()
    is Object({ "params": Object({ "output": output, .. }), .. }) else {
    fail("no output tuple")
  }
  assert_eq(output, json_tuple_ir3.to_json())
}

///|
test "session: no agreed tuple at the requested IR version is tuple_unavailable after negotiation" {
  // The claims show IR 3, but the live worker agrees on nothing of the offer.
  assert_eq(
    refused_agreement(Model([ion_tuple_ir3, json_tuple_ir3]), []),
    (["morphir.shutdown", "morphir.exit"], Some(TupleUnavailable)),
  )
  // A worker that answers IR 4 to an IR 3 offer did not keep to the offer.
  assert_eq(
    refused_agreement(Model([json_tuple_ir3]), [json_compile_tuple.to_json()]),
    (["morphir.shutdown", "morphir.exit"], Some(AgreementMismatch)),
  )
}

///|
test "session: without a requirement a guest with both versions agrees on IR 4.0.0 first" {
  let both = [json_compile_tuple, json_tuple_ir3]
  let claims = claims_of(both)
  let offer = @worker.Offer::select(claims, CompileModel)
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let (_, step) = conversation.on(
    answer(1, model_result(both, protocol="0.2.0-draft.1")),
  )
  guard step is Activated(negotiated, ..) else {
    fail("not activated: \{@debug.to_string(step)}")
  }
  assert_eq(negotiated.tuple, Some(json_compile_tuple))
}

///|
test "session: options that name another IR version than the agreed tuple are refused" {
  let claims = claims_of([json_tuple_ir3])
  let offer : @worker.Offer = Model([json_tuple_ir3])
  let (conversation, _) = @worker.Conversation::activate(offer, expected=claims)
  let (conversation, _) = conversation.on(
    answer(1, model_result([json_tuple_ir3], protocol="0.2.0-draft.1")),
  )
  let request = @worker.CompileRequest::new({
    "languageId": "python",
    "options": { "typesOnly": false, "irVersion": "4.0.0" },
  })
  let (_, step) = conversation.compile(request)
  assert_eq(refused_code(step), Some(TupleUnavailable))
  assert_eq(sends(step), [])
}

///|
test "offer default tuple: the first offered tuple, and none on MEP 0.1" {
  assert_eq(
    @worker.Offer::Model([json_tuple_ir3, ion_tuple]).default_tuple(),
    Some(json_tuple_ir3),
  )
  assert_eq(@worker.Offer::Legacy.default_tuple(), None)
}
