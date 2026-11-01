///|
/// The source that both MoonBit guests compile.
let moonbit_source : String =
  #|///|
  #|pub fn add(a : Int, b : Int) -> Int {
  #|  a + b
  #|}

///|
fn compile_params(tuple : @worker.ModelTuple) -> Map[String, Json] {
  let options : Json = { "typesOnly": false, "irVersion": "4.0.0" }
  let context : Json = { "package": "acme/math", "options": options }
  {
    "languageId": "moonbit",
    "sources": {
      "documents": [
        {
          "uri": "math.mbt",
          "languageId": "moonbit",
          "version": 0,
          "text": moonbit_source,
        },
      ],
    },
    "package": { "name": "acme/math" },
    "options": options,
    "contextDigest": @worker.Sha256::of(@utf8.encode(context.stringify())).to_string(),
    "output": tuple.to_json(),
  }
}

///|
fn generate_params(
  envelope : Json,
  tuple : @worker.ModelTuple,
) -> Map[String, Json] {
  let identity : Json = match envelope {
    Object(fields) =>
      {
        "target": "moonbit",
        "modelId": fields.get("modelId").unwrap_or(Json::null()),
        "revision": fields.get("revision").unwrap_or(Json::null()),
      }
    _ => Json::null()
  }
  {
    "model": envelope,
    "input": tuple.to_json(),
    "target": "moonbit",
    "contextDigest": @worker.Sha256::of(@utf8.encode(identity.stringify())).to_string(),
  }
}

///|
/// Describes, compiles and generates with one guest, each in its own
/// session. Returns the compile result and the generate result.
async fn describe_compile_generate(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
) -> (@worker.Claims, Json, Json) {
  let claims = host.probe(spec).claims
  let compile_offer = @worker.Offer::select(
    claims,
    CompileModel,
    profile=MorphirModel,
    codec=IonBinary,
    ir_version=@worker.IrVersionName::parse("4.0.0"),
  )
  guard compile_offer is Model([compile_tuple]) else {
    fail("not a model offer")
  }
  let compiled = host.with_session(spec, expected=claims, offer=compile_offer, session => {
    session.compile(@worker.CompileRequest::new(compile_params(compile_tuple)))
  })
  guard compiled.class is Completed(compiled) else {
    fail("the compile did not complete: \{@debug.to_string(compiled)}")
  }
  guard compiled.result is { "model": envelope, .. } else {
    fail("the compile result has no model: \{compiled.result.stringify()}")
  }
  let generate_offer = @worker.Offer::select(
    claims,
    GenerateModel,
    profile=MorphirModel,
    codec=IonBinary,
    ir_version=@worker.IrVersionName::parse("4.0.0"),
  )
  guard generate_offer is Model([generate_tuple]) else {
    fail("not a model offer")
  }
  let generated = host.with_session(
    spec,
    expected=claims,
    offer=generate_offer,
    session => {
      session.generate(
        @worker.GenerateRequest::new(generate_params(envelope, generate_tuple)),
      )
    },
  )
  guard generated.class is Completed(generated) else {
    fail("the generate did not complete: \{@debug.to_string(generated)}")
  }
  (claims, compiled.result, generated.result)
}

///|
async test "Node worker threads: the portable guest returns the same envelopes as the native guest" {
  guard entry() is Some(path) &&
    prerequisite("MORPHIR_PORTABLE_GUEST") is Some(portable) &&
    prerequisite("MORPHIR_NATIVE_GUEST") is Some(native) &&
    @node_process.host_machine() is Some(machine) else {
    return
  }
  let wasm_bytes = read_file(portable)
  let native_bytes = read_file(native)
  let (wasm_claims, wasm_compiled, wasm_generated) = describe_compile_generate(
    host(path),
    wasm_spec(wasm_bytes, abi=MorphirBytesV1),
  )
  let (native_claims, native_compiled, native_generated) = describe_compile_generate(
    @worker.Host::new(@node_process.NodeProcessLauncher::new(), Node(machine)),
    @worker.WorkerSpec::new(
      @worker.ArtifactRef::new(
        File(@worker.ArtifactPath::parse(native, Posix)),
        @worker.Sha256::of(native_bytes),
      ),
      Process(platform=machine.platforms()[0], args=[]),
    ),
  )
  assert_eq(wasm_claims, native_claims)
  assert_eq(wasm_compiled, native_compiled)
  assert_eq(wasm_generated, native_generated)
}
