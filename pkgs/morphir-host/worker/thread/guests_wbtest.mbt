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
/// A valid plain IR file of exactly `size` bytes, generated here: a small
/// library, and JSON white space that fills the rest.
fn plain_ir_of_size(size : Int32) -> Bytes {
  let ir = "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"generated\",\"dependencies\":{},\"def\":{\"modules\":{\"main\":{\"Public\":{\"types\":{},\"values\":{\"answer\":{\"Public\":{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":\"morphir/SDK:basics#int\",\"body\":{\"Literal\":{\"IntegerLiteral\":42}}}}}}}}}}}}}"
  @utf8.encode(ir + " ".repeat(size - ir.length()))
}

///|
/// Wraps a plain IR file of `size` bytes as the CLI does, and sends it to the
/// guest with `generateModel`. Returns the generate result.
async fn generate_plain_ir(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
  size : Int32,
) -> Json {
  let claims = host.probe(spec).claims
  let bytes = plain_ir_of_size(size)
  let wrapped = @worker.WrappedPlainIr::of(
    bytes,
    @json.parse(@utf8.decode(bytes[:])),
  )
  let generated = host.with_session(
    spec,
    expected=claims,
    offer=@worker.Offer::of_model(claims, wrapped.tuple),
    session => {
      session.generate(
        @worker.GenerateRequest::new(
          generate_params(wrapped.envelope, wrapped.tuple),
        ),
      )
    },
  )
  guard generated.class is Completed(generated) else {
    fail("the generate did not complete: \{@debug.to_string(generated)}")
  }
  generated.result
}

///|
async test "Node worker threads: a plain IR file of exactly 4 MiB generates on both guests" {
  guard entry() is Some(path) &&
    prerequisite("MORPHIR_PORTABLE_GUEST") is Some(portable) &&
    prerequisite("MORPHIR_NATIVE_GUEST") is Some(native) &&
    @node_process.host_machine() is Some(machine) else {
    return
  }
  let size = 4 * 1024 * 1024
  let wasm_generated = generate_plain_ir(
    host(path),
    wasm_spec(read_file(portable), abi=MorphirBytesV1),
    size,
  )
  let native_generated = generate_plain_ir(
    @worker.Host::new(@node_process.NodeProcessLauncher::new(), Node(machine)),
    @worker.WorkerSpec::new(
      @worker.ArtifactRef::new(
        File(@worker.ArtifactPath::parse(native, Posix)),
        @worker.Sha256::of(read_file(native)),
      ),
      Process(platform=machine.platforms()[0], args=[]),
    ),
    size,
  )
  assert_eq(wasm_generated, native_generated)
  assert_true(wasm_generated.stringify().contains("answer"))
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
