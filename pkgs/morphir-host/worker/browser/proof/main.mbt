///|
/// What the page or the Node driver gives the proof, as
/// `globalThis.morphirWorkerProof`: `platform` ("browser" or "node"),
/// `entry` (the entry module URL or path), the `portable` and `python`
/// module bytes, `callMs` (the runaway guest's call deadline),
/// `measureMemory` (resolves to bytes, or -1) and `done` (receives the result
/// as JSON text).
#external
priv type ProofInput

///|
extern "js" fn proof_input() -> ProofInput =
  #| () => globalThis.morphirWorkerProof

///|
extern "js" fn ProofInput::text(self : ProofInput, name : String) -> String =
  #| (input, name) => typeof input[name] === 'string' ? input[name] : ''

///|
extern "js" fn ProofInput::module_bytes(
  self : ProofInput,
  name : String,
) -> Bytes =
  #| (input, name) => input[name] instanceof Uint8Array ? input[name] : new Uint8Array(0)

///|
extern "js" fn ProofInput::number(self : ProofInput, name : String) -> Int32 =
  #| (input, name) => Number.isInteger(input[name]) ? input[name] : 0

///|
/// Tells the driver that a step starts or ends, so that it can watch the
/// page and its workers at that time.
extern "js" fn ProofInput::mark(self : ProofInput, name : String) -> Unit =
  #| (input, name) => { input.mark?.(name); }

///|
extern "js" fn ProofInput::done(self : ProofInput, text : String) -> Unit =
  #| (input, text) => input.done(text)

///|
extern "js" fn ProofInput::measure_memory(
  self : ProofInput,
  _signal : @js_async.AbortSignal,
) -> @js_async.Promise[Double] =
  #| (input) => Promise.resolve(input.measureMemory ? input.measureMemory() : -1).catch(() => -1)

///|
/// The platform that runs the proof.
priv enum ProofPlatform {
  Browser
  Node
}

///|
fn ProofPlatform::name(self : ProofPlatform) -> String {
  match self {
    Browser => "browser"
    Node => "node"
  }
}

///|
/// The host of one platform. `call_ms` replaces the per-call deadline.
fn host(
  platform : ProofPlatform,
  entry : String,
  call_ms? : Int32,
) -> @worker.Host raise {
  match platform {
    Browser =>
      @worker.Host::new(
        @browser.BrowserLauncher::new(@browser.EntryUrl::parse(entry), call_ms?),
        Browser,
      )
    Node => {
      guard @node_process.host_machine() is Some(machine) else {
        fail("Node runs on a machine that the host does not know")
      }
      @worker.Host::new(
        @thread.ThreadLauncher::new(entry~, call_ms?),
        Node(machine),
      )
    }
  }
}

///|
fn wasm_spec(bytes : Bytes, abi : @worker.WasmAbi) -> @worker.WorkerSpec {
  @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(bytes), @worker.Sha256::of(bytes)),
    Wasm(abi=Some(abi)),
  )
}

///|
/// The source that the MoonBit guest compiles.
let moonbit_source : String =
  #|///|
  #|pub fn add(a : Int, b : Int) -> Int {
  #|  a + b
  #|}

///|
/// The source that the Python extension compiles.
let python_source : String =
  #|from dataclasses import dataclass
  #|
  #|@dataclass(frozen=True)
  #|class Approved:
  #|    amount: float

///|
fn digest(value : Json) -> String {
  @worker.Sha256::of(@utf8.encode(value.stringify())).to_string()
}

///|
/// A model compile of the MoonBit guest, as the CLI sends it.
fn moonbit_compile(tuple : @worker.ModelTuple) -> Map[String, Json] {
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
    "contextDigest": digest(context),
    "output": tuple.to_json(),
  }
}

///|
/// A model generate of the MoonBit guest, as the CLI sends it.
fn moonbit_generate(
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
    "contextDigest": digest(identity),
  }
}

///|
/// A MEP 0.1 compile of the Python extension, as the CLI sends it.
fn python_compile() -> Map[String, Json] {
  {
    "languageId": "python",
    "sources": {
      "documents": [
        {
          "uri": "file:///work/acme/models.py",
          "languageId": "python",
          "version": 1,
          "text": python_source,
        },
      ],
    },
    "package": { "name": "acme" },
    "dependencies": [],
    "options": { "irVersion": "4", "typesOnly": false },
  }
}

///|
/// The JSON of a worker stop, without its stderr tail.
fn stop_json(report : @worker.SessionReport) -> Json {
  match report.stop {
    Some(stop) =>
      {
        "status": @debug.to_string(stop.status),
        "method": @debug.to_string(stop.stop_method),
      }
    None => Json::null()
  }
}

///|
/// Describes, compiles and generates with one guest, each in its own
/// session, and times each session. `measure` runs in the compile session
/// after the compile, while the guest is loaded.
async fn describe_compile_generate(
  host : @worker.Host,
  spec : @worker.WorkerSpec,
  model~ : Bool,
  measure~ : async () -> Double,
) -> Json {
  let started = @async.now()
  let claims = host.probe(spec).claims
  let probe_ms = @async.now() - started
  let compile_offer = if model {
    @worker.Offer::select(
      claims,
      CompileModel,
      profile=MorphirModel,
      codec=IonBinary,
      ir_version=@worker.IrVersionName::parse("4.0.0"),
    )
  } else {
    @worker.Offer::select(claims, Compile)
  }
  let compile_request = match compile_offer {
    Model([tuple]) => moonbit_compile(tuple)
    Model(_) => fail("not one model tuple")
    Legacy => python_compile()
  }
  let started = @async.now()
  let mut memory = -1.0
  let compiled = host.with_session(spec, expected=claims, offer=compile_offer, session => {
    let outcome = session.compile(@worker.CompileRequest::new(compile_request))
    memory = measure()
    outcome
  })
  let compile_ms = @async.now() - started
  guard compiled.class is Completed(compiled) else {
    fail("the compile did not complete: \{@debug.to_string(compiled)}")
  }
  let (generate_offer, generate_request) = match compiled.result {
    { "model": envelope, .. } if model => {
      let offer = @worker.Offer::select(
        claims,
        GenerateModel,
        profile=MorphirModel,
        codec=IonBinary,
        ir_version=@worker.IrVersionName::parse("4.0.0"),
      )
      guard offer is Model([tuple]) else { fail("not one model tuple") }
      (offer, moonbit_generate(envelope, tuple))
    }
    { "ir": ir, .. } if !model =>
      (
        @worker.Offer::select(claims, Generate),
        { "ir": ir, "target": "python", "options": {} },
      )
    result => fail("the compile result has no model: \{result.stringify()}")
  }
  let started = @async.now()
  let mut generate_stop = Json::null()
  let generated = host.with_session(
    spec,
    expected=claims,
    offer=generate_offer,
    session => {
      let outcome = session.generate(
        @worker.GenerateRequest::new(generate_request),
      )
      generate_stop = stop_json(session.close())
      outcome
    },
  )
  let generate_ms = @async.now() - started
  guard generated.class is Completed(generated) else {
    fail("the generate did not complete: \{@debug.to_string(generated)}")
  }
  {
    "results": {
      "extension": "\{claims.extension_id} \{claims.version}",
      "claims": @debug.to_string(claims),
      "compile": compiled.result,
      "generate": generated.result,
      "generateStop": generate_stop,
    },
    "measured": {
      "moduleBytes": bytes_length(spec).to_double(),
      "probeMs": probe_ms.to_double(),
      "compileSessionMs": compile_ms.to_double(),
      "generateSessionMs": generate_ms.to_double(),
      "memoryBytes": memory,
    },
  }
}

///|
fn bytes_length(spec : @worker.WorkerSpec) -> Int32 {
  match spec.artifact.source {
    Memory(bytes) => bytes.length()
    File(_) => 0
  }
}

///|
/// A runaway guest: the call deadline must terminate its worker.
async fn runaway(host : @worker.Host, input : ProofInput) -> Json {
  let bytes = @fixtures.runaway_guest()
  input.mark("runaway-start")
  let started = @async.now()
  let ending = try host.probe(wasm_spec(bytes, MorphirBytesV1)) catch {
    @worker.Ended(ending, report~) => Some((ending, report))
    error => fail("not a host error: \{error}")
  } noraise {
    _ => None
  }
  let elapsed = @async.now() - started
  input.mark("runaway-end")
  guard ending is Some((ending, report)) else {
    fail("the runaway guest described itself")
  }
  {
    "ending": @debug.to_string(ending),
    "stop": stop_json(report),
    "elapsedMs": elapsed.to_double(),
  }
}

///|
/// Pins of a native executable and of a Node executable. Both name a
/// process runtime, which a browser host refuses before it starts a worker.
let process_pins : Array[Json] = [
  {
    "artifact": { "path": "/opt/morphir/morphir-elm", "sha256": "0".repeat(64) },
    "runtime": {
      "kind": "process",
      "platform": "x86_64-unknown-linux-gnu",
      "args": [],
    },
  },
  {
    "artifact": { "path": "/opt/morphir/node", "sha256": "1".repeat(64) },
    "runtime": {
      "kind": "process",
      "platform": "aarch64-apple-darwin",
      "args": ["extension.mjs"],
    },
  },
]

///|
/// The refusals of the process pins.
async fn refusals(host : @worker.Host, input : ProofInput) -> Json {
  input.mark("refusal-start")
  let results : Array[Json] = []
  for pin in process_pins {
    let spec = @worker.WorkerSpec::from_json(pin, Posix)
    let refused = try host.probe(spec) catch {
      @worker.Ended(Refused(code~, message~), report~) => {
        let refused : Json = {
          "code": code.to_string(),
          "message": message,
          "supported": host.supports(spec.runtime),
          "workerStopped": report.stop is Some(_),
        }
        refused
      }
      error => fail("not a refusal: \{error}")
    } noraise {
      _ => fail("a browser host ran a process pin")
    }
    results.push(refused)
  }
  input.mark("refusal-end")
  Json::array(results)
}

///|
async fn run(input : ProofInput) -> Json {
  let platform = match input.text("platform") {
    "browser" => Browser
    "node" => Node
    other => fail("unknown platform: \{other}")
  }
  let entry = input.text("entry")
  let measure = async fn() -> Double {
    @js_async.run_promise(signal => input.measure_memory(signal))
  }
  let moonbit = describe_compile_generate(
    host(platform, entry),
    wasm_spec(input.module_bytes("portable"), MorphirBytesV1),
    model=true,
    measure~,
  )
  let python = describe_compile_generate(
    host(platform, entry),
    wasm_spec(input.module_bytes("python"), ExtismKernelV1),
    model=false,
    measure~,
  )
  let result : Map[String, Json] = {
    "platform": platform.name(),
    "moonbit": moonbit,
    "python": python,
  }
  if platform is Browser {
    let call_ms = match input.number("callMs") {
      0 => 300
      value => value
    }
    result["runaway"] = runaway(host(platform, entry, call_ms~), input)
    result["refusals"] = refusals(host(platform, entry), input)
  }
  Json::object(result)
}

///|
async fn main {
  let input = proof_input()
  let result : Json = run(input) catch {
    error => { "error": @debug.to_string(error) }
  }
  input.done(result.stringify())
}
