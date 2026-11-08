///|
/// A scripted guest for the in-memory workers. `reply` answers compile and
/// generate calls: `Ok(result)`, `Err(error)` or `None` for no answer.
priv struct FakeGuest {
  describe : Json
  /// The claims that `initialize` answers from, when they differ from those of
  /// `describe`.
  live : Json?
  reply : (String, Json) -> Result[Json, Json]?
  shutdown : Result[Json, Json]
  stderr : String
}

///|
/// Starts one in-memory worker for each launch, with the scripted guest,
/// and records every method that a worker received, the operation calls and
/// the model transport offers of `initialize`.
priv struct ScriptedLauncher {
  group : @async.TaskGroup[Unit]
  guest : FakeGuest
  methods : Array[String]
  calls : Array[Json]
  /// The bounds that the channel states, as a WASM host's channel does.
  bounds : @worker.EnforcedBounds?
  offers : Array[Json]
  /// The encoded bytes of each operation call, as the worker received them.
  requests : Array[Bytes]
}

///|
fn fake_initialize(describe : Json, params : Json) -> Json {
  guard describe is Object(fields) && params is Object(offered) else {
    return describe
  }
  let answer = fields.copy()
  answer.remove("protocolVersions")
  let line = match offered.get("protocolVersions") {
    Some(Array([String(line), ..])) => line
    _ => "0.1"
  }
  answer["protocolVersion"] = Json::string(line)
  if answer.get("capabilities") is Some(Object(capabilities)) {
    let capabilities = capabilities.copy()
    match (offered.get("modelTransport"), capabilities.get("modelTransport")) {
      (Some(Object(offer)), Some(Object(transport))) => {
        // Like a real guest: the offered tuples that it supports, in the
        // host's order.
        let supported = match transport.get("tuples") {
          Some(Array(tuples)) => tuples
          _ => []
        }
        let offered = match offer.get("tuples") {
          Some(Array(tuples)) => tuples
          _ => []
        }
        let transport = transport.copy()
        transport["tuples"] = Json::array(
          offered.filter(tuple => supported.contains(tuple)),
        )
        capabilities["modelTransport"] = Json::object(transport)
      }
      _ => capabilities.remove("modelTransport")
    }
    answer["capabilities"] = Json::object(capabilities)
  }
  Json::object(answer)
}

///|
async fn fake_serve(
  worker : @worker.MemoryWorker,
  guest : FakeGuest,
  methods : Array[String],
  calls : Array[Json],
  offers : Array[Json],
  requests : Array[Bytes],
) -> Unit {
  worker.write_stderr(@utf8.encode(guest.stderr))
  while true {
    let message = worker.receive() catch { _ => return }
    guard message.json() is Object({ "method": String(name), .. } as fields) else {
      continue
    }
    methods.push(name)
    let params = fields.get("params").unwrap_or(Json::null())
    if name == "morphir.exit" {
      worker.exit(code=0)
      return
    }
    guard fields.get("id") is Some(id) else { continue }
    let answer = match name {
      "morphir.extension.describe" => Some(Ok(guest.describe))
      "morphir.initialize" => {
        if params is Object({ "modelTransport": offer, .. }) {
          offers.push(offer)
        }
        Some(Ok(fake_initialize(guest.live.unwrap_or(guest.describe), params)))
      }
      "morphir.shutdown" => Some(guest.shutdown)
      _ => {
        calls.push(params)
        requests.push(message.to_bytes())
        (guest.reply)(name, params)
      }
    }
    match answer {
      Some(Ok(result)) =>
        worker.send(
          @worker.Message::new({ "jsonrpc": "2.0", "id": id, "result": result }),
        ) catch {
          _ => return
        }
      Some(Err(error)) =>
        worker.send(
          @worker.Message::new({ "jsonrpc": "2.0", "id": id, "error": error }),
        ) catch {
          _ => return
        }
      None => ()
    }
  }
}

///|
impl @worker.Launcher for ScriptedLauncher with fn launch(self, _spec, _limits) {
  let (channel, worker) = @worker.MemoryChannel::pair(bounds?=self.bounds)
  self.group.spawn_bg(() => {
    fake_serve(
      worker,
      self.guest,
      self.methods,
      self.calls,
      self.offers,
      self.requests,
    )
  })
  channel
}

///|
/// The run of one command against the scripted guest.
priv struct FakeRun {
  report : ExtensionReport
  json : Json
  methods : Array[String]
  calls : Array[Json]
  offers : Array[Json]
  requests : Array[Bytes]
}

///|
async fn fake_run(
  args : Array[String],
  guest : FakeGuest,
  stopped~ : () -> Bool = () => false,
  hosted~ : Bool = true,
  bounds? : @worker.EnforcedBounds,
) -> FakeRun {
  let finished : Ref[FakeRun?] = Ref(None)
  @async.with_task_group(group => {
    let launcher = ScriptedLauncher::{
      group,
      guest,
      methods: [],
      calls: [],
      bounds,
      offers: [],
      requests: [],
    }
    let hosting = if hosted {
      WorkerHosting::new(
        Native(@worker.Machine::of(X86_64UnknownLinuxGnu)),
        process=launcher,
      )
    } else {
      WorkerHosting::none()
    }
    let report = extension_run(parse_cli(args), { hosting, stopped, })
    finished.val = Some({
      report,
      json: report.to_json(),
      methods: launcher.methods,
      calls: launcher.calls,
      offers: launcher.offers,
      requests: launcher.requests,
    })
  })
  guard finished.val is Some(run) else { abort("the run did not finish") }
  run
}

///|
/// Runs the command entry, `extension_command`, with the scripted guest in
/// one output mode, and returns its exit status.
async fn fake_command(
  args : Array[String],
  guest : FakeGuest,
  mode : OutputMode,
) -> Int32 {
  let status : Ref[Int32?] = Ref(None)
  @async.with_task_group(group => {
    let launcher = ScriptedLauncher::{
      group,
      guest,
      methods: [],
      calls: [],
      bounds: None,
      offers: [],
      requests: [],
    }
    let context = {
      ..command_context(mode),
      workers: WorkerHosting::new(
        Native(@worker.Machine::of(X86_64UnknownLinuxGnu)),
        process=launcher,
      ),
    }
    status.val = Some(extension_command(parse_cli(args), context))
  })
  guard status.val is Some(code) else { abort("the command did not finish") }
  code
}

///|
fn fake_moonbit_describe() -> Json {
  extension_test_claims(
    frontend={
      "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
      "irVersions": ["4.0.0"],
      "compile": false,
    },
    backend={ "targets": ["moonbit"], "irVersions": ["4"], "generate": true },
    tuples=[
      extension_test_tuple("morphir.frontend.compileModel", "ion-binary"),
      extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
      extension_test_tuple("morphir.backend.generateModel", "ion-binary"),
    ],
  )
}

///|
fn fake_model_result() -> Json {
  let bytes = b"\xe0\x01\x00\xea"
  {
    "success": true,
    "diagnostics": [
      {
        "severity": "warning",
        "code": "fixture.note",
        "message": "a fixture warning",
        "location": {
          "uri": "main.mbt",
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 1 },
          },
        },
      },
    ],
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "irVersion": "4.0.0",
      "profile": "morphir-model",
      "modelId": "fixture",
      "revision": "1",
      "payload": {
        "codec": "ion-binary",
        "decodedByteLength": 4,
        "sha256": extension_sha256(bytes),
        "content": @base64.encode(bytes[:]),
      },
    },
  }
}

///|
fn fake_guest(
  describe~ : Json = fake_moonbit_describe(),
  live? : Json,
  reply~ : (String, Json) -> Result[Json, Json]? = (_, _) => {
    Some(Ok(fake_model_result()))
  },
  shutdown~ : Result[Json, Json] = Ok({}),
  stderr~ : String = "",
) -> FakeGuest {
  { describe, live, reply, shutdown, stderr, }
}

///|
/// A scratch directory with a pin for the scripted guest.
priv struct FakeWorkspace {
  root : String
  pin : String
}

///|
fn fake_workspace(
  runtime~ : Json = {
    "kind": "process",
    "platform": "x86_64-unknown-linux-gnu",
    "args": [],
  },
  descriptor? : Json,
  contract~ : String = "0.2.0",
) -> FakeWorkspace raise {
  let root = @platform.temporary()
  let pin = extension_test_pin(runtime~)
  pin["contractVersion"] = Json::string(contract)
  if descriptor is Some(document) {
    let path = root + "/release.json"
    let bytes = @utf8.encode(document.stringify())
    @platform.write_bytes(path, bytes)
    pin["descriptor"] = { "path": path, "sha256": extension_sha256(bytes) }
  }
  @platform.write(root + "/pin.json", Json::object(pin).stringify())
  @platform.write(root + "/main.mbt", "pub fn ready() -> Bool { true }\n")
  { root, pin: root + "/pin.json", }
}

///|
fn fake_file(path : String) -> String {
  @platform.read(path) catch {
    _ => ""
  }
}

///|
fn fake_exists(path : String) -> Bool {
  try @platform.kind(path) != 0 catch {
    _ => false
  }
}

///|
fn fake_field(value : Json, path : Array[String]) -> Json {
  let mut current = value
  for name in path {
    current = match current {
      Object(fields) => fields.get(name).unwrap_or(Json::null())
      _ => Json::null()
    }
  }
  current
}

///|
fn fake_error(run : FakeRun) -> String {
  match fake_field(run.json, ["error", "code"]) {
    String(code) => code
    _ => ""
  }
}

///|
async test "describe probes the worker and reports its claims" {
  let workspace = fake_workspace()
  let run = fake_run(
    ["extension", "describe", "--extension-pin", workspace.pin, "--json"],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 0)
  assert_eq(fake_field(run.json, ["state"]), "succeeded")
  assert_eq(fake_field(run.json, ["command"]), "extension.describe")
  assert_eq(fake_field(run.json, ["result", "worker", "kind"]), "process")
  assert_eq(
    fake_field(run.json, ["result", "extension", "id"]),
    "fixture-gleam",
  )
  assert_eq(fake_field(run.json, ["result", "claims", "languages"]), [
    { "id": "moonbit", "fileExtensions": [".mbt"] },
  ])
  assert_eq(fake_field(run.json, ["result", "claims", "frontendFlags"]), {
    "incremental": false,
    "multiDocument": false,
  })
  // A describe never initializes the worker.
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
}

///|
async test "compile on the model line publishes the model and reports the session" {
  let workspace = fake_workspace()
  let output = workspace.root + "/out"
  let run = fake_run(
    [
      "extension",
      "compile",
      workspace.root + "/main.mbt",
      "--package",
      "acme/ready",
      "--output",
      output,
      "--extension-pin",
      workspace.pin,
      "--json",
    ],
    fake_guest(stderr="guest progress on stderr\n"),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(run.methods, [
    "morphir.extension.describe", "morphir.exit", "morphir.initialize", "morphir.initialized",
    "morphir.frontend.compileModel", "morphir.shutdown", "morphir.exit",
  ])
  let request = run.calls[0]
  assert_eq(fake_field(request, ["languageId"]), "moonbit")
  assert_eq(fake_field(request, ["sources", "documents"]), [
    {
      "uri": "main.mbt",
      "languageId": "moonbit",
      "version": 0,
      "text": "pub fn ready() -> Bool { true }\n",
    },
  ])
  assert_eq(fake_field(request, ["output", "codec"]), "ion-binary")
  let result = fake_field(run.json, ["result"])
  assert_eq(fake_field(result, ["worker", "kind"]), "process")
  assert_eq(fake_field(result, ["protocolVersion"]), "0.2.0-draft.1")
  assert_eq(
    fake_field(result, ["negotiated", "tuple", "operation"]),
    "morphir.frontend.compileModel",
  )
  assert_eq(fake_field(result, ["negotiated", "limits", "maxDepth"]), 128)
  assert_eq(fake_field(result, ["negotiated", "limits", "maxNodes"]), 100000)
  assert_eq(fake_field(result, ["bounds", "deadlineMs"]), 60000)
  assert_eq(fake_field(result, ["lifecycle", "shutdown"]), "acknowledged")
  assert_eq(
    fake_field(result, ["stderr", "text"]),
    "guest progress on stderr\n",
  )
  guard fake_field(result, ["output", "files"]) is Array(files) else {
    fail("no published files")
  }
  assert_eq(files.map(file => fake_field(file, ["path"])), [
    "model-envelope.json", "model.ionb",
  ])
  assert_eq(fake_field(files[1], ["bytes"]), 4)
  assert_eq(
    fake_field(files[1], ["sha256"]),
    Json::string(extension_sha256(b"\xe0\x01\x00\xea")),
  )
  assert_true(fake_file(output + "/model-envelope.json").contains("ion-binary"))
  assert_false(fake_exists(output + ".morphir-partial"))
  // Guest diagnostics are in the report and go to stderr.
  assert_eq(fake_field(run.json, ["diagnostics"]), [
    {
      "severity": "warning",
      "message": "a fixture warning",
      "code": "fixture.note",
      "location": {
        "uri": "main.mbt",
        "range": {
          "start": { "line": 0, "character": 0 },
          "end": { "line": 0, "character": 1 },
        },
      },
    },
  ])
}

///|
/// A compile result with a `morphir-ir` model in Morphir JSON.
fn fake_json_model_result(
  ir_version~ : String = "4.0.0",
  format~ : Int32 = 4,
) -> Json {
  let bytes = @utf8.encode("{\"formatVersion\":\{format}}")
  {
    "success": true,
    "diagnostics": [],
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "irVersion": ir_version,
      "profile": "morphir-ir",
      "modelId": "fixture",
      "revision": "1",
      "payload": {
        "codec": "morphir-json",
        "decodedByteLength": bytes.length(),
        "sha256": extension_sha256(bytes),
        "content": @base64.encode(bytes[:]),
      },
    },
  }
}

///|
/// A model frontend that supports only the compile tuples with `codecs`.
fn fake_model_describe(codecs : Array[String]) -> Json {
  extension_test_claims(
    frontend={
      "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
      "irVersions": ["4.0.0"],
      "compile": false,
    },
    tuples=codecs.map(codec => {
      extension_test_tuple("morphir.frontend.compileModel", codec)
    }),
  )
}

///|
fn fake_compile_args(
  workspace : FakeWorkspace,
  output : String,
) -> Array[String] {
  [
    "extension",
    "compile",
    workspace.root + "/main.mbt",
    "--package",
    "acme/ready",
    "--output",
    workspace.root + "/" + output,
    "--extension-pin",
    workspace.pin,
    "--json",
  ]
}

///|
async test "model tuple negotiation: the CLI offers Ion, then JSON, and a JSON-only guest compiles with JSON" {
  let workspace = fake_workspace()
  let run = fake_run(
    fake_compile_args(workspace, "json-model"),
    fake_guest(describe=fake_model_describe(["morphir-json"]), reply=(_, _) => {
      Some(Ok(fake_json_model_result()))
    }),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  // The host offers all of its tuples, in its order.
  assert_eq(run.offers.length(), 1)
  assert_eq(fake_field(run.offers[0], ["tuples"]), [
    fake_tuple_at("4.0.0", codec="ion-binary"),
    fake_tuple_at("4.0.0"),
    fake_tuple_at("3.0.0", codec="ion-binary"),
    fake_tuple_at("3.0.0"),
  ])
  // The session uses the agreed JSON tuple, and no error is reported.
  assert_eq(
    fake_field(run.calls[0], ["output"]),
    extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
  )
  let result = fake_field(run.json, ["result"])
  assert_eq(
    fake_field(result, ["negotiated", "tuple"]),
    extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
  )
  guard fake_field(result, ["output", "files"]) is Array(files) else {
    fail("no published files")
  }
  assert_eq(files.map(file => fake_field(file, ["path"])), [
    "model-envelope.json", "model.json",
  ])
  // A guest that supports both tuples agrees on both and uses Ion.
  let run = fake_run(fake_compile_args(workspace, "ion-model"), fake_guest())
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(
    fake_field(run.json, ["result", "negotiated", "tuple", "codec"]),
    "ion-binary",
  )
}

///|
async test "required model format: --model-format json offers only JSON tuples, which an Ion-only guest refuses" {
  let workspace = fake_workspace()
  let run = fake_run(
    fake_compile_args(workspace, "required") + ["--model-format", "json"],
    fake_guest(describe=fake_model_describe(["ion-binary", "morphir-json"]), reply=(
      _,
      _,
    ) => Some(Ok(fake_json_model_result()))),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(fake_field(run.offers[0], ["tuples"]), [
    fake_tuple_at("4.0.0"),
    fake_tuple_at("3.0.0"),
  ])
  let run = fake_run(
    fake_compile_args(workspace, "refused") + ["--model-format", "json"],
    fake_guest(describe=fake_model_describe(["ion-binary"])),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.tuple_unavailable")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  assert_false(fake_exists(workspace.root + "/refused"))
}

///|
fn fake_legacy_describe() -> Json {
  extension_test_claims(frontend={
    "languages": [{ "id": "gleam", "fileExtensions": [".gleam"] }],
    "irVersions": ["3"],
    "compile": true,
    "multiDocument": true,
  })
}

///|
/// The claims of a Python frontend like 0.4.1: one document per request.
fn fake_python_describe(multi_document~ : Bool = false) -> Json {
  let frontend : Map[String, Json] = {
    "languages": [{ "id": "python", "fileExtensions": [".py"] }],
    "irVersions": ["4"],
    "compile": true,
  }
  if multi_document {
    frontend["multiDocument"] = true
  }
  extension_test_claims(frontend=Json::object(frontend))
}

///|
async test "Python 0.4.1 with two modules: a frontend without multiDocument is refused" {
  let workspace = fake_workspace()
  let sources = workspace.root + "/loans"
  @platform.mkdir(sources)
  @platform.write(sources + "/loans.py", "def rate(): return 1\n")
  @platform.write(sources + "/terms.py", "def term(): return 2\n")
  let args = (output : String) => {
    [
      "extension",
      "compile",
      sources,
      "--source-base",
      workspace.root,
      "--package",
      "acme/loans",
      "--output",
      workspace.root + "/" + output,
      "--extension-pin",
      workspace.pin,
      "--json",
    ]
  }
  let reply = (_ : String, _ : Json) => {
    Some(
      Ok(
        fake_legacy_result(
          ir_version="4",
          ir=fake_legacy_ir_with("formatVersion", 4),
        ),
      ),
    )
  }
  let run = fake_run(
    args("refused"),
    fake_guest(describe=fake_python_describe(), reply~),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.capability_unavailable")
  assert_true(
    fake_field(run.json, ["error", "message"])
    .stringify()
    .contains("multiDocument"),
  )
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  assert_false(fake_exists(workspace.root + "/refused"))
  // One module compiles: the request has one document.
  let single = fake_run(
    [
      "extension",
      "compile",
      sources + "/loans.py",
      "--package",
      "acme/loans",
      "--output",
      workspace.root + "/single",
      "--extension-pin",
      workspace.pin,
    ],
    fake_guest(describe=fake_python_describe(), reply~),
  )
  assert_true(single.methods.contains("morphir.frontend.compile"))
  // A frontend that claims multiDocument receives both modules.
  let multi = fake_run(
    args("multi"),
    fake_guest(describe=fake_python_describe(multi_document=true), reply~),
  )
  assert_true(multi.methods.contains("morphir.frontend.compile"))
  guard fake_field(multi.calls[0], ["sources", "documents"]) is Array(documents) else {
    fail("no documents")
  }
  assert_eq(documents.length(), 2)
}

///|
async test "a frontend without model methods compiles on MEP 0.1 from the claimed sources" {
  let workspace = fake_workspace()
  let sources = workspace.root + "/src"
  @platform.mkdir(sources)
  @platform.mkdir(sources + "/nested")
  @platform.write(sources + "/app.gleam", "pub fn main() { 1 }\n")
  @platform.write(sources + "/nested/lib.gleam", "pub fn lib() { 2 }\n")
  @platform.write(sources + "/README.md", "not a source\n")
  let output = workspace.root + "/out"
  let run = fake_run(
    [
      "extension",
      "compile",
      sources,
      "--source-base",
      workspace.root,
      "--package",
      "acme/app",
      "--output",
      output,
      "--extension-pin",
      workspace.pin,
    ],
    fake_guest(describe=fake_legacy_describe(), reply=(rpc, _) => {
      if rpc == "morphir.frontend.compile" {
        Some(Ok(fake_legacy_result()))
      } else {
        None
      }
    }),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_true(run.methods.contains("morphir.frontend.compile"))
  let request = run.calls[0]
  assert_eq(fake_field(request, ["languageId"]), "gleam")
  guard fake_field(request, ["sources", "documents"]) is Array(documents) else {
    fail("no documents")
  }
  assert_eq(documents.map(document => fake_field(document, ["uri"])), [
    "src/app.gleam", "src/nested/lib.gleam",
  ])
  assert_eq(fake_field(request, ["options", "irVersion"]), "3")
  assert_eq(fake_file(output + "/morphir-ir.json"), fake_legacy_ir.stringify())
}

///|
/// A Morphir IR 3 distribution that the versioned JSON codec reads.
let fake_legacy_ir : Json = {
  "formatVersion": 3,
  "distribution": ["Library", [["acme"]], [], { "modules": [] }],
}

///|
fn fake_legacy_result(
  ir_version~ : Json = "3",
  ir~ : Json = fake_legacy_ir,
) -> Json {
  { "success": true, "irVersion": ir_version, "ir": ir, "diagnostics": [] }
}

///|
async fn fake_legacy_compile(
  workspace : FakeWorkspace,
  result : Json,
  output~ : String = workspace.root + "/out",
) -> FakeRun {
  @platform.write(workspace.root + "/app.gleam", "pub fn main() { 1 }\n")
  fake_run(
    [
      "extension",
      "compile",
      workspace.root + "/app.gleam",
      "--package",
      "acme/app",
      "--output",
      output,
      "--extension-pin",
      workspace.pin,
      "--json",
    ],
    fake_guest(describe=fake_legacy_describe(), reply=(_, _) => Some(Ok(result))),
  )
}

///|
async test "a MEP 0.1 compile result is checked against the selected IR version before publication" {
  for
    result in [
      // The result reports another IR version.
      fake_legacy_result(ir_version="4"),
      // The IR has another format version.
      fake_legacy_result(ir=fake_legacy_ir_with("formatVersion", 4)),
      // The IR does not decode with the IR 3 codec.
      fake_legacy_result(ir={ "formatVersion": 3 }),
    ] {
    let workspace = fake_workspace()
    let output = workspace.root + "/out"
    let run = fake_legacy_compile(workspace, result, output~)
    assert_eq(run.report.exit_code(), 1, msg=run.json.stringify())
    assert_eq(fake_error(run), "extension.result_invalid")
    assert_false(fake_exists(output))
    assert_false(fake_exists(output + ".morphir-partial"))
  }
  // A result without irVersion is checked by the IR's own format version.
  let workspace = fake_workspace()
  let result = fake_legacy_result()
  guard result is Object(fields) else { fail("result") }
  let fields = fields.copy()
  fields.remove("irVersion")
  let run = fake_legacy_compile(workspace, Json::object(fields))
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
}

///|
fn fake_legacy_ir_with(name : String, value : Json) -> Json {
  guard fake_legacy_ir is Object(fields) else { abort("fake_legacy_ir") }
  let fields = fields.copy()
  fields[name] = value
  Json::object(fields)
}

///|
fn fake_legacy_backend_describe(versions~ : Array[Json] = ["3"]) -> Json {
  extension_test_claims(
    frontend={
      "languages": [{ "id": "gleam", "fileExtensions": [".gleam"] }],
      "irVersions": ["3"],
      "compile": true,
    },
    backend={
      "targets": ["scala"],
      "irVersions": Json::array(versions),
      "generate": true,
    },
  )
}

///|
/// Runs a MEP 0.1 generate of `model` with the scripted backend.
async fn fake_legacy_generate(
  workspace : FakeWorkspace,
  model : String,
  output : String,
  versions~ : Array[Json] = ["3"],
  extra~ : Array[String] = [],
) -> FakeRun {
  fake_run(
    [
      "extension",
      "generate",
      model,
      "--output",
      workspace.root + "/" + output,
      "--extension-pin",
      workspace.pin,
      "--json",
      ..extra,
    ],
    fake_guest(describe=fake_legacy_backend_describe(versions~), reply=(_, _) => {
      Some(Ok(fake_artifacts()))
    }),
  )
}

///|
async test "a MEP 0.1 generate takes the IR version from the model and sends no irVersion" {
  let workspace = fake_workspace()
  let model = workspace.root + "/morphir-ir.json"
  @platform.write(model, fake_legacy_ir.stringify())
  // --ir-version is a check: the backend reads the version from the IR's
  // formatVersion, so the request carries the options as given, empty.
  let run = fake_legacy_generate(workspace, model, "checked", extra=[
    "--ir-version", "3",
  ])
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(fake_field(run.calls[0], ["options"]), Json::object(Map([])))
  assert_eq(fake_field(run.calls[0], ["target"]), "scala")
  // Without --ir-version, the model's formatVersion selects the claimed
  // version, also when the backend claims more than one.
  let run = fake_legacy_generate(workspace, model, "selected", versions=[
    "3", "4",
  ])
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(fake_field(run.calls[0], ["options"]), Json::object(Map([])))
}

///|
async test "a MEP 0.1 generate refuses a model of another or an unclaimed IR version" {
  let workspace = fake_workspace()
  let model = workspace.root + "/morphir-ir.json"
  @platform.write(model, fake_legacy_ir.stringify())
  // A model of IR 3 with --ir-version 4 is refused before the session.
  let run = fake_legacy_generate(
    workspace,
    model,
    "mismatch",
    versions=["3", "4"],
    extra=["--ir-version", "4"],
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.ir_version_mismatch")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  assert_false(fake_exists(workspace.root + "/mismatch"))
  // A model of IR 4 for a backend that claims only IR 3 is refused.
  let v4 = workspace.root + "/morphir-ir-4.json"
  @platform.write(v4, "{\"formatVersion\":4,\"distribution\":{}}")
  let run = fake_legacy_generate(workspace, v4, "unclaimed")
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.capability_unavailable")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  assert_false(fake_exists(workspace.root + "/unclaimed"))
}

///|
async test "a MEP 0.1 generate matches the model's IR version exactly, or by a major-only name" {
  let workspace = fake_workspace()
  let write = (name : String, version : Json) => {
    let path = workspace.root + "/" + name
    @platform.write(
      path,
      ({ "formatVersion": version, "distribution": {} } : Json).stringify(),
    )
    path
  }
  let v410 = write("ir-4.1.0.json", "4.1.0")
  let v420 = write("ir-4.2.0.json", "4.2.0")
  let v4 = write("ir-4.json", 4)
  let versions : Array[Json] = ["4.0.0", "4.1.0"]
  let generate = (model : String, output : String, extra : Array[String]) => {
    fake_legacy_generate(workspace, model, output, versions~, extra~)
  }
  // The model's exact version is claimed; a major-only --ir-version agrees.
  for case in [(v410, "exact", []), (v410, "major", ["--ir-version", "4"])] {
    let (model, output, extra) = case
    let run = generate(model, output, extra)
    assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  }
  // A major-only model version is served by the highest claimed version.
  let run = generate(v4, "highest", [])
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  // A full model version that is not claimed is refused.
  let run = generate(v420, "unclaimed", [])
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.capability_unavailable")
  assert_false(fake_exists(workspace.root + "/unclaimed"))
  // A full --ir-version must equal the model's version.
  for case in [(v410, "other-full"), (v4, "full-for-major")] {
    let (model, output) = case
    let run = generate(model, output, ["--ir-version", "4.0.0"])
    assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
    assert_eq(fake_error(run), "extension.ir_version_mismatch")
    assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  }
}

///|
async test "a model generate sends the envelope's tuple and refuses another --ir-version" {
  let workspace = fake_workspace()
  let input = fake_generate_input(workspace)
  let run = fake_run(
    [
      "extension",
      "generate",
      input,
      "--output",
      workspace.root + "/generated",
      "--extension-pin",
      workspace.pin,
      "--ir-version",
      "4.0.0",
      "--json",
    ],
    fake_guest(reply=(_, _) => Some(Ok(fake_artifacts()))),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(fake_field(run.calls[0], ["input"]), {
    "operation": "morphir.backend.generateModel",
    "profile": "morphir-model",
    "codec": "ion-binary",
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  })
  let run = fake_run(
    [
      "extension",
      "generate",
      input,
      "--output",
      workspace.root + "/refused",
      "--extension-pin",
      workspace.pin,
      "--ir-version",
      "3",
    ],
    fake_guest(reply=(_, _) => Some(Ok(fake_artifacts()))),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.ir_version_mismatch")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  // A major-only --ir-version agrees with the envelope's IR 4.0.0; another
  // full version of the same major does not.
  for case in [("4", 0), ("4.1.0", 2)] {
    let (version, code) = case
    let run = fake_run(
      [
        "extension",
        "generate",
        input,
        "--output",
        workspace.root + "/envelope-" + version,
        "--extension-pin",
        workspace.pin,
        "--ir-version",
        version,
      ],
      fake_guest(reply=(_, _) => Some(Ok(fake_artifacts()))),
    )
    assert_eq(run.report.exit_code(), code, msg=run.json.stringify())
  }
}

///|
async test "an unclaimed operation exits 2 and starts no operation" {
  let workspace = fake_workspace()
  @platform.write(workspace.root + "/model.json", "{\"formatVersion\":3}")
  let run = fake_run(
    [
      "extension",
      "generate",
      workspace.root + "/model.json",
      "--output",
      workspace.root + "/out",
      "--extension-pin",
      workspace.pin,
    ],
    fake_guest(describe=fake_legacy_describe()),
  )
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.capability_unavailable")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
}

///|
async test "descriptor claims that differ from the live describe exit 2" {
  let drifted = fake_moonbit_describe()
  guard drifted is Object(fields) else { fail("claims") }
  let fields = fields.copy()
  fields["extension"] = { "id": "fixture-gleam", "version": "1.0.1" }
  let workspace = fake_workspace(descriptor={
    "schemaVersion": "2.0.0-draft.2",
    "artifacts": [
      {
        "runtime": "process",
        "platform": "x86_64-unknown-linux-gnu",
        "filename": "morphir-extension",
        "sha256": extension_test_digest,
        "claims": Json::object(fields),
      },
    ],
  })
  let run = fake_run(
    ["extension", "describe", "--extension-pin", workspace.pin, "--json"],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.claims_mismatch")
  assert_false(run.methods.contains("morphir.initialize"))
  // The same descriptor with the live claims is accepted.
  let workspace = fake_workspace(descriptor={
    "schemaVersion": "2.0.0-draft.2",
    "artifacts": [
      { "sha256": extension_test_digest, "claims": fake_moonbit_describe() },
    ],
  })
  let run = fake_run(
    ["extension", "describe", "--extension-pin", workspace.pin],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
}

///|
async test "a bad descriptor is refused before any worker starts" {
  let entry : Json = {
    "sha256": extension_test_digest,
    "claims": fake_moonbit_describe(),
  }
  let cases : Array[(String, Json)] = [
    ("extension.descriptor_invalid", { "schemaVersion": "2.0.0-draft.2" }),
    (
      "extension.descriptor_invalid",
      { "artifacts": [{ "sha256": "b".repeat(64), "claims": entry }] },
    ),
    ("extension.descriptor_invalid", { "artifacts": [entry, entry] }),
    (
      "extension.descriptor_invalid",
      {
        "artifacts": [
          { "sha256": extension_test_digest, "claims": { "extension": 1 } },
        ],
      },
    ),
  ]
  for case in cases {
    let (code, descriptor) = case
    let workspace = fake_workspace(descriptor~)
    let run = fake_run(
      ["extension", "describe", "--extension-pin", workspace.pin, "--json"],
      fake_guest(),
    )
    assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
    assert_eq(fake_error(run), code, msg=run.json.stringify())
    assert_eq(run.methods, [])
  }
  // A descriptor whose bytes differ from the pinned digest.
  let workspace = fake_workspace(descriptor={ "artifacts": [entry] })
  @platform.write(workspace.root + "/release.json", "{\"artifacts\":[]}")
  let run = fake_run(
    ["extension", "describe", "--extension-pin", workspace.pin, "--json"],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.digest_mismatch")
  assert_eq(run.methods, [])
}

///|
fn fake_generate_input(workspace : FakeWorkspace) -> String raise {
  let path = workspace.root + "/model-envelope.json"
  guard fake_model_result() is Object({ "model": model, .. }) else {
    fail("no model")
  }
  @platform.write(path, model.stringify())
  path
}

///|
fn fake_artifacts() -> Json {
  {
    "success": true,
    "artifacts": [
      { "path": "src/main.mbt", "content": "fn main {}\n", "binary": false },
    ],
  }
}

///|
async test "an unsuccessful answer and a failed shutdown publish nothing" {
  let workspace = fake_workspace()
  let input = fake_generate_input(workspace)
  let output = workspace.root + "/generated"
  let args = [
    "extension",
    "generate",
    input,
    "--output",
    output,
    "--extension-pin",
    workspace.pin,
    "--json",
  ]
  let unsuccessful = fake_run(
    args,
    fake_guest(reply=(_, _) => Some(Ok({ "success": false, "diagnostics": [] }))),
  )
  assert_eq(unsuccessful.report.exit_code(), 1)
  assert_eq(fake_error(unsuccessful), "extension.operation_unsuccessful")
  assert_false(fake_exists(output))
  // The guest returns artifacts, then refuses shutdown.
  let refused = fake_run(
    args,
    fake_guest(
      reply=(_, _) => Some(Ok(fake_artifacts())),
      shutdown=Err({ "code": -32603, "message": "shutdown failed" }),
    ),
  )
  assert_eq(refused.report.exit_code(), 1, msg=refused.json.stringify())
  assert_eq(fake_field(refused.json, ["state"]), "failed")
  assert_false(fake_exists(output))
  assert_false(fake_exists(output + ".morphir-partial"))
  // The same session with an acknowledged shutdown publishes.
  let published = fake_run(
    args,
    fake_guest(reply=(_, _) => Some(Ok(fake_artifacts()))),
  )
  assert_eq(published.report.exit_code(), 0, msg=published.json.stringify())
  assert_eq(fake_field(published.calls[0], ["target"]), "moonbit")
  assert_eq(fake_file(output + "/src/main.mbt"), "fn main {}\n")
}

///|
async test "a cancel during generate exits 130 and publishes nothing" {
  let workspace = fake_workspace()
  let input = fake_generate_input(workspace)
  let output = workspace.root + "/generated"
  let cancelled = Ref(false)
  let run = fake_run(
    [
      "extension",
      "generate",
      input,
      "--output",
      output,
      "--extension-pin",
      workspace.pin,
      "--json",
    ],
    fake_guest(reply=(_, _) => {
      cancelled.val = true
      None
    }),
    stopped=() => cancelled.val,
  )
  assert_eq(run.report.exit_code(), 130)
  assert_eq(fake_error(run), "extension.cancelled")
  assert_false(fake_exists(output))
  assert_false(fake_exists(output + ".morphir-partial"))
}

///|
async test "an async cancellation of the command exits 130, not host_failed" {
  let workspace = fake_workspace()
  let finished : Ref[ExtensionReport?] = Ref(None)
  let methods : Array[String] = []
  @async.with_task_group(group => {
    let launcher = ScriptedLauncher::{
      group,
      guest: fake_guest(reply=(_, _) => None),
      methods,
      calls: [],
      bounds: None,
      offers: [],
      requests: [],
    }
    let hosting = WorkerHosting::new(
      Native(@worker.Machine::of(X86_64UnknownLinuxGnu)),
      process=launcher,
    )
    let task = group.spawn(() => {
      finished.val = Some(
        extension_run(
          parse_cli([
            "extension",
            "compile",
            workspace.root + "/main.mbt",
            "--package",
            "acme/ready",
            "--output",
            workspace.root + "/out",
            "--extension-pin",
            workspace.pin,
          ]),
          { hosting, stopped: () => false, },
        ),
      )
    })
    // Cancel the task while the guest holds the compile call.
    while !methods.contains("morphir.frontend.compileModel") {
      @async.sleep(5)
    }
    task.cancel()
  })
  guard finished.val is Some(report) else { fail("the run did not finish") }
  assert_eq(report.exit_code(), 130, msg=report.to_json().stringify())
  assert_eq(
    fake_field(report.to_json(), ["error", "code"]),
    "extension.cancelled",
  )
  assert_false(fake_exists(workspace.root + "/out"))
  assert_false(fake_exists(workspace.root + "/out.morphir-partial"))
}

///|
async test "a cancel file that appears after the session closes and before the rename exits 130" {
  let workspace = fake_workspace()
  let input = fake_generate_input(workspace)
  let output = workspace.root + "/generated"
  // The staging directory is the cancel file: it appears only after the
  // session closed and the worker tree stopped, before the rename.
  let args = [
    "extension",
    "generate",
    input,
    "--output",
    output,
    "--extension-pin",
    workspace.pin,
    "--cancel-file",
    output + ".morphir-partial",
    "--json",
  ]
  let guest = fake_guest(reply=(_, _) => Some(Ok(fake_artifacts())))
  assert_eq(fake_command(args, guest, JSON), 130)
  assert_false(fake_exists(output))
  assert_false(fake_exists(output + ".morphir-partial"))
  // The same check through extension_run reports extension.cancelled after a
  // complete session.
  let run = fake_run(args, guest, stopped=() => {
    fake_exists(output + ".morphir-partial")
  })
  assert_eq(run.report.exit_code(), 130)
  assert_eq(fake_error(run), "extension.cancelled")
  assert_eq(run.methods.filter(name => name == "morphir.shutdown"), [
    "morphir.shutdown",
  ])
  assert_false(fake_exists(output))
  assert_false(fake_exists(output + ".morphir-partial"))
}

///|
async test "the session deadline exits 124" {
  let workspace = fake_workspace()
  let run = fake_run(
    [
      "extension",
      "compile",
      workspace.root + "/main.mbt",
      "--package",
      "acme/ready",
      "--output",
      workspace.root + "/out",
      "--extension-pin",
      workspace.pin,
      "--timeout",
      "300",
    ],
    fake_guest(reply=(_, _) => None),
  )
  assert_eq(run.report.exit_code(), 124)
  assert_eq(fake_error(run), "extension.deadline")
  assert_false(fake_exists(workspace.root + "/out"))
}

///|
async test "refusals before any worker starts exit 2" {
  let retired = fake_workspace(contract="0.1.0-draft.1")
  let run = fake_run(
    ["extension", "describe", "--extension-pin", retired.pin, "--json"],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.pin_retired")
  assert_eq(run.methods, [])
  let wasm = fake_workspace(runtime={ "kind": "wasm" })
  let run = fake_run(
    ["extension", "describe", "--extension-pin", wasm.pin, "--json"],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.runtime_unavailable")
  assert_eq(run.methods, [])
  let run = fake_run(
    ["extension", "describe", "--extension-pin", wasm.pin],
    fake_guest(),
    hosted=false,
  )
  assert_eq(fake_error(run), "extension.runtime_unavailable")
  let run = fake_run(["extension", "describe"], fake_guest())
  assert_eq(fake_error(run), "extension.pin_required")
  let workspace = fake_workspace()
  @platform.mkdir(workspace.root + "/out")
  let run = fake_run(
    [
      "extension",
      "compile",
      workspace.root + "/main.mbt",
      "--package",
      "acme/ready",
      "--output",
      workspace.root + "/out",
      "--extension-pin",
      workspace.pin,
    ],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.output_exists")
  assert_eq(run.methods, [])
  // Only the staging directory of an earlier run exists: the message names it.
  let staged = fake_workspace()
  @platform.mkdir(staged.root + "/out.morphir-partial")
  let compile = (workspace : FakeWorkspace, output : String) => {
    [
      "extension",
      "compile",
      workspace.root + "/main.mbt",
      "--package",
      "acme/ready",
      "--output",
      output,
      "--extension-pin",
      workspace.pin,
    ]
  }
  let run = fake_run(compile(staged, staged.root + "/out"), fake_guest())
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.output_exists")
  assert_true(
    fake_field(run.json, ["error", "message"])
    .stringify()
    .contains("out.morphir-partial"),
    msg=run.json.stringify(),
  )
  assert_eq(run.methods, [])
  // The output's parent directory must exist before the probe.
  let run = fake_run(
    compile(staged, staged.root + "/missing/out"),
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 2)
  assert_eq(fake_error(run), "extension.input_invalid")
  assert_eq(run.methods, [])
  let run = fake_run(
    compile(staged, staged.root + "/main.mbt/out"),
    fake_guest(),
  )
  assert_eq(fake_error(run), "extension.input_invalid")
  assert_eq(run.methods, [])
}

///|
async test "the exit table is the same in human and JSON mode" {
  let workspace = fake_workspace()
  let retired = fake_workspace(contract="0.1.0")
  let input = fake_generate_input(workspace)
  let cancel = workspace.root + "/cancel"
  @platform.write(cancel, "")
  let generate = (output : String, extra : Array[String]) => {
    [
      "extension",
      "generate",
      input,
      "--output",
      workspace.root + "/" + output,
      "--extension-pin",
      workspace.pin,
      ..extra,
    ]
  }
  let cases : Array[(Int32, String, Array[String], FakeGuest)] = [
    (
      0,
      "success",
      ["extension", "describe", "--extension-pin", workspace.pin],
      fake_guest(),
    ),
    (
      1,
      "unsuccessful",
      generate("unsuccessful", []),
      fake_guest(reply=(_, _) => {
        Some(Ok({ "success": false, "diagnostics": [] }))
      }),
    ),
    (
      2,
      "refusal",
      ["extension", "describe", "--extension-pin", retired.pin],
      fake_guest(),
    ),
    (
      124,
      "deadline",
      generate("deadline", ["--timeout", "300"]),
      fake_guest(reply=(_, _) => None),
    ),
    (
      130,
      "cancellation",
      generate("cancelled", ["--cancel-file", cancel]),
      fake_guest(),
    ),
  ]
  for case in cases {
    let (expected, name, args, guest) = case
    assert_eq(fake_command(args, guest, Human), expected, msg="human \{name}")
    assert_eq(
      fake_command([..args, "--json"], guest, JSON),
      expected,
      msg="JSON \{name}",
    )
  }
}

///|
async test "compile reports the WASM bounds that the worker's host enforced in result.bounds" {
  let workspace = fake_workspace()
  let args = (output : String) => {
    [
      "extension",
      "compile",
      workspace.root + "/main.mbt",
      "--package",
      "acme/ready",
      "--output",
      workspace.root + "/" + output,
      "--extension-pin",
      workspace.pin,
      "--json",
    ]
  }
  let enforced = @worker.EnforcedBounds::new(
    memory_ceiling=Enforced,
    instruction_budget=NotEnforced(NoInstructionMetering),
    call_deadline=Enforced,
  )
  let run = fake_run(args("wasm"), fake_guest(), bounds=enforced)
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  let bounds = fake_field(run.json, ["result", "bounds"])
  assert_eq(fake_field(bounds, ["memoryCeiling"]), { "enforced": true })
  assert_eq(fake_field(bounds, ["callDeadline"]), { "enforced": true })
  assert_eq(
    fake_field(bounds, ["instructionBudget"]),
    enforced.instruction_budget.to_json(),
  )
  // The CLI's own bounds stay.
  assert_eq(fake_field(bounds, ["deadlineMs"]), 60000)
  assert_eq(fake_field(bounds, ["stderrTailBytes"]), 65536)
  // A process worker states no WASM bounds.
  let process = fake_run(args("process"), fake_guest())
  guard fake_field(process.json, ["result", "bounds"]) is Object(fields) else {
    fail("no bounds")
  }
  assert_false(fields.contains("memoryCeiling"))
}

///|
let fake_gleam_language : Json = { "id": "gleam", "fileExtensions": [".gleam"] }

///|
/// The claims of a Gleam frontend like morphir-gleam 0.4.0: several
/// documents in one request, on the JSON model tuple.
fn fake_gleam_describe(
  languages~ : Array[Json] = [fake_gleam_language],
) -> Json {
  extension_test_claims(
    frontend={
      "languages": Json::array(languages),
      "irVersions": ["4.0.0"],
      "compile": false,
      "multiDocument": true,
    },
    tuples=[
      extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
    ],
  )
}

///|
fn fake_gleam_guest(
  languages~ : Array[Json] = [fake_gleam_language],
) -> FakeGuest {
  fake_guest(describe=fake_gleam_describe(languages~), reply=(_, _) => {
    Some(Ok(fake_json_model_result()))
  })
}

///|
/// A Gleam project in `root`: modules in two directories under `src` that
/// import one another, and files of other languages.
fn fake_gleam_tree(root : String) -> Unit raise {
  @platform.mkdir(root + "/src")
  @platform.mkdir(root + "/src/app")
  @platform.mkdir(root + "/src/shared")
  @platform.write(
    root + "/src/app/money.gleam",
    "import shared/numbers\npub type Money = numbers.Number\n",
  )
  @platform.write(
    root + "/src/app/orders.gleam",
    "import app/money\npub type Order = money.Money\n",
  )
  @platform.write(root + "/src/shared/numbers.gleam", "pub type Number = Int\n")
  @platform.write(root + "/src/README.md", "not a source\n")
  @platform.write(root + "/src/main.elm", "module Main exposing (..)\n")
}

///|
/// The arguments of a compile of `input` in the workspace, with `options`
/// before the shared ones.
fn fake_tree_compile(
  workspace : FakeWorkspace,
  input : String,
  output : String,
  options : Array[String],
) -> Array[String] {
  [
    "extension",
    "compile",
    input,
    ..options,
    "--package",
    "acme/shop",
    "--output",
    workspace.root + "/" + output,
    "--extension-pin",
    workspace.pin,
    "--json",
  ]
}

///|
fn fake_uris(request : Json) -> Array[Json] {
  guard fake_field(request, ["sources", "documents"]) is Array(documents) else {
    return []
  }
  documents.map(document => fake_field(document, ["uri"]))
}

///|
async test "language from claims: a guest with several languages needs --language" {
  let workspace = fake_workspace()
  fake_gleam_tree(workspace.root)
  let elm : Json = { "id": "elm", "fileExtensions": [".elm"] }
  let base = ["--source-base", workspace.root]
  let source = workspace.root + "/src"
  // Several claimed languages and no --language: refused before any
  // operation session, and the message names both languages.
  let run = fake_run(
    fake_tree_compile(workspace, source, "none", base),
    fake_gleam_guest(languages=[elm, fake_gleam_language]),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.input_invalid")
  let message = fake_field(run.json, ["error", "message"]).stringify()
  assert_true(message.contains("elm") && message.contains("gleam"), msg=message)
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  assert_false(fake_exists(workspace.root + "/none"))
  // An unclaimed language is a capability refusal, also before any session.
  let run = fake_run(
    fake_tree_compile(
      workspace,
      source,
      "python",
      [..base, "--language", "python"],
    ),
    fake_gleam_guest(languages=[elm, fake_gleam_language]),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.capability_unavailable")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  // --language gleam sends gleam and reads only the .gleam files.
  let run = fake_run(
    fake_tree_compile(
      workspace,
      source,
      "gleam",
      [..base, "--language", "gleam"],
    ),
    fake_gleam_guest(languages=[elm, fake_gleam_language]),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  let request = run.calls[0]
  assert_eq(fake_field(request, ["languageId"]), "gleam")
  assert_eq(fake_uris(request), [
    "src/app/money.gleam", "src/app/orders.gleam", "src/shared/numbers.gleam",
  ])
  guard fake_field(request, ["sources", "documents"]) is Array(documents) else {
    fail("no documents")
  }
  for document in documents {
    assert_eq(fake_field(document, ["languageId"]), "gleam")
  }
}

///|
async test "relative document URIs: a tree is named from the input directory or the source base, with no sources.root" {
  let workspace = fake_workspace()
  fake_gleam_tree(workspace.root)
  // The guest claims one language, so no --language is needed.
  let run = fake_run(
    fake_tree_compile(workspace, workspace.root + "/src", "model", [
      "--source-base",
      workspace.root,
    ]),
    fake_gleam_guest(),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  let request = run.calls[0]
  assert_eq(fake_field(request, ["languageId"]), "gleam")
  assert_eq(fake_uris(request), [
    "src/app/money.gleam", "src/app/orders.gleam", "src/shared/numbers.gleam",
  ])
  guard fake_field(request, ["sources"]) is Object(sources) else {
    fail("no sources")
  }
  assert_eq(sources.keys().collect(), ["documents"])
  assert_false(request.stringify().contains(workspace.root))
  // A deeper input keeps the URIs from the source base.
  let run = fake_run(
    fake_tree_compile(workspace, workspace.root + "/src/app", "app", [
      "--source-base",
      workspace.root,
    ]),
    fake_gleam_guest(),
  )
  assert_eq(fake_uris(run.calls[0]), [
    "src/app/money.gleam", "src/app/orders.gleam",
  ])
  // Without --source-base the input directory is the base, wherever the
  // current directory is.
  let run = fake_run(
    fake_tree_compile(workspace, workspace.root + "/src", "own", []),
    fake_gleam_guest(),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(fake_uris(run.calls[0]), [
    "app/money.gleam", "app/orders.gleam", "shared/numbers.gleam",
  ])
  assert_false(run.calls[0].stringify().contains(workspace.root))
  // An input outside the source base is refused before any operation
  // session, and the message names the source base.
  let run = fake_run(
    fake_tree_compile(workspace, workspace.root + "/src", "outside", [
      "--source-base",
      workspace.root + "/other",
    ]),
    fake_gleam_guest(),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.input_invalid")
  assert_true(
    fake_field(run.json, ["error", "message"])
    .stringify()
    .contains(workspace.root + "/other"),
    msg=run.json.stringify(),
  )
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  assert_false(fake_exists(workspace.root + "/outside"))
}

///|
async test "same tree twice gives byte-identical compileModel requests; other trees keep the contextDigest" {
  let workspace = fake_workspace()
  fake_gleam_tree(workspace.root)
  let base = ["--source-base", workspace.root]
  let first = fake_run(
    fake_tree_compile(workspace, workspace.root + "/src", "first", base),
    fake_gleam_guest(),
  )
  let second = fake_run(
    fake_tree_compile(workspace, workspace.root + "/src", "second", base),
    fake_gleam_guest(),
  )
  assert_eq(first.report.exit_code(), 0, msg=first.json.stringify())
  assert_eq(first.requests.length(), 1)
  assert_eq(second.requests.length(), 1)
  assert_true(first.requests[0] == second.requests[0])
  // The same package and options with another tree: other documents, the
  // same contextDigest.
  let other = fake_workspace()
  @platform.mkdir(other.root + "/src")
  @platform.write(other.root + "/src/ledger.gleam", "pub type Ledger = Int\n")
  let third = fake_run(
    fake_tree_compile(workspace, other.root + "/src", "third", [
      "--source-base",
      other.root,
    ]),
    fake_gleam_guest(),
  )
  assert_eq(third.report.exit_code(), 0, msg=third.json.stringify())
  assert_eq(fake_uris(third.calls[0]), ["src/ledger.gleam"])
  assert_eq(
    fake_field(third.calls[0], ["contextDigest"]),
    fake_field(first.calls[0], ["contextDigest"]),
  )
  assert_true(fake_field(first.calls[0], ["contextDigest"]) is String(_))
}

///|
async test "a tree of 1,025 documents is refused before any operation session" {
  let workspace = fake_workspace()
  let many = workspace.root + "/many"
  @platform.mkdir(many)
  for index in 0..<1025 {
    @platform.write(many + "/m\{index}.gleam", "pub type T = Int\n")
  }
  let run = fake_run(
    fake_tree_compile(workspace, many, "model", [
      "--source-base",
      workspace.root,
    ]),
    fake_gleam_guest(),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.input_invalid")
  assert_true(
    fake_field(run.json, ["error", "message"])
    .stringify()
    .contains("limit of 1024 documents"),
    msg=run.json.stringify(),
  )
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
}

///|
/// A compile tuple of IR version `version`, like those of Python 0.5.
fn fake_tuple_at(version : String, codec~ : String = "morphir-json") -> Json {
  guard extension_test_tuple("morphir.frontend.compileModel", codec)
    is Object(fields) else {
    abort("a tuple is an object")
  }
  let fields = fields.copy()
  fields["irVersion"] = Json::string(version)
  Json::object(fields)
}

///|
/// A guest on both lines that compiles JSON models at IR 3.0.0 and 4.0.0, and
/// claims legacy compile too, like Python 0.5.
fn fake_python_model_describe(
  versions~ : Array[String] = ["3.0.0", "4.0.0"],
) -> Json {
  extension_test_claims(
    frontend={
      "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
      "irVersions": ["3", "4"],
      "compile": true,
      "multiDocument": true,
    },
    tuples=versions.map(version => fake_tuple_at(version)),
  )
}

///|
/// Answers a compile with a JSON model of the IR version that the request
/// names, as a conforming guest does.
fn fake_python_reply(_method : String, params : Json) -> Result[Json, Json]? {
  match fake_field(params, ["options", "irVersion"]) {
    String("3.0.0") =>
      Some(Ok(fake_json_model_result(ir_version="3.0.0", format=3)))
    _ => Some(Ok(fake_json_model_result()))
  }
}

///|
async test "--ir-version 3 negotiates an IR 3.0.0 tuple, and the request and the checks follow it" {
  let workspace = fake_workspace()
  let run = fake_run(
    fake_compile_args(workspace, "ir3") + ["--ir-version", "3"],
    fake_guest(describe=fake_python_model_describe(), reply=fake_python_reply),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  // The offer holds only the tuples of IR 3.0.0, Ion first.
  assert_eq(fake_field(run.offers[0], ["tuples"]), [
    fake_tuple_at("3.0.0", codec="ion-binary"),
    fake_tuple_at("3.0.0"),
  ])
  assert_eq(fake_field(run.calls[0], ["output"]), fake_tuple_at("3.0.0"))
  assert_eq(fake_field(run.calls[0], ["options", "irVersion"]), "3.0.0")
  // contextDigest covers the options, so it follows the agreed IR version.
  let context : Json = {
    "package": "acme/ready",
    "options": { "typesOnly": false, "irVersion": "3.0.0" },
  }
  assert_eq(
    fake_field(run.calls[0], ["contextDigest"]),
    Json::string(extension_sha256(@utf8.encode(context.stringify()))),
  )
  let result = fake_field(run.json, ["result"])
  assert_eq(fake_field(result, ["protocolVersion"]), "0.2.0-draft.1")
  assert_eq(fake_field(result, ["negotiated", "tuple"]), fake_tuple_at("3.0.0"))
  assert_eq(
    fake_file(workspace.root + "/ir3/model.json"),
    "{\"formatVersion\":3}",
  )
  // An exact version gives the same offer.
  let exact = fake_run(
    fake_compile_args(workspace, "ir3-exact") + ["--ir-version", "3.0.0"],
    fake_guest(describe=fake_python_model_describe(), reply=fake_python_reply),
  )
  assert_eq(exact.report.exit_code(), 0, msg=exact.json.stringify())
  assert_eq(exact.offers, run.offers)
  assert_true(exact.requests[0] == run.requests[0])
}

///|
async test "--ir-version 4, and no flag, compile with IR 4.0.0 on a guest of both versions" {
  let workspace = fake_workspace()
  let guest = fake_guest(
    describe=fake_python_model_describe(),
    reply=fake_python_reply,
  )
  let selected = fake_run(
    fake_compile_args(workspace, "ir4") + ["--ir-version", "4"],
    guest,
  )
  assert_eq(selected.report.exit_code(), 0, msg=selected.json.stringify())
  assert_eq(fake_field(selected.offers[0], ["tuples"]), [
    fake_tuple_at("4.0.0", codec="ion-binary"),
    fake_tuple_at("4.0.0"),
  ])
  assert_eq(fake_field(selected.calls[0], ["options", "irVersion"]), "4.0.0")
  let free = fake_run(fake_compile_args(workspace, "free"), guest)
  assert_eq(free.report.exit_code(), 0, msg=free.json.stringify())
  // No flag: the host offers IR 4.0.0 first, and the guest agrees on it.
  assert_eq(fake_field(free.offers[0], ["tuples"]), [
    fake_tuple_at("4.0.0", codec="ion-binary"),
    fake_tuple_at("4.0.0"),
    fake_tuple_at("3.0.0", codec="ion-binary"),
    fake_tuple_at("3.0.0"),
  ])
  assert_eq(fake_field(free.calls[0], ["output"]), fake_tuple_at("4.0.0"))
  assert_eq(fake_field(free.calls[0], ["options", "irVersion"]), "4.0.0")
}

///|
async test "a guest with only IR 3.0.0 tuples compiles at IR 3.0.0 with no flag" {
  let workspace = fake_workspace()
  let run = fake_run(
    fake_compile_args(workspace, "only-ir3"),
    fake_guest(
      describe=fake_python_model_describe(versions=["3.0.0"]),
      reply=fake_python_reply,
    ),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(fake_field(run.calls[0], ["options", "irVersion"]), "3.0.0")
  assert_eq(fake_field(run.calls[0], ["output"]), fake_tuple_at("3.0.0"))
}

///|
async test "a guest on both lines with no way to serve --ir-version is refused" {
  let workspace = fake_workspace()
  // The claims show it: refused before any operation session starts. This
  // guest has no legacy compile, so no line serves IR 3.
  let run = fake_run(
    fake_compile_args(workspace, "refused") + ["--ir-version", "3"],
    fake_guest(describe=fake_model_describe(["morphir-json"])),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.tuple_unavailable")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  assert_eq(run.offers, [])
  assert_false(fake_exists(workspace.root + "/refused"))
  // An IR version that no tuple and no claim on MEP 0.1 includes, also.
  for version in ["5", "4.1.0"] {
    let run = fake_run(
      fake_compile_args(workspace, "unknown-" + version) +
      ["--ir-version", version],
      fake_guest(describe=fake_python_model_describe()),
    )
    assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
    assert_eq(fake_error(run), "extension.tuple_unavailable")
    assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  }
  // Both flags together intersect: JSON at IR 3 has a tuple, Ion at IR 3 has
  // none, though the guest has Ion at IR 4.0.0.
  let crossed = fake_guest(
    describe=extension_test_claims(
      frontend={
        "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
        "compile": false,
      },
      tuples=[
        fake_tuple_at("4.0.0", codec="ion-binary"),
        fake_tuple_at("3.0.0"),
      ],
    ),
    reply=fake_python_reply,
  )
  let run = fake_run(
    fake_compile_args(workspace, "crossed") +
    ["--ir-version", "3", "--model-format", "ion"],
    crossed,
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.tuple_unavailable")
  let run = fake_run(
    fake_compile_args(workspace, "intersect") +
    ["--ir-version", "3", "--model-format", "json"],
    crossed,
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(fake_field(run.offers[0], ["tuples"]), [fake_tuple_at("3.0.0")])
}

///|
async test "claims with a tuple that the live worker does not agree on are refused after negotiation" {
  let workspace = fake_workspace()
  let run = fake_run(
    fake_compile_args(workspace, "drift") + ["--ir-version", "3"],
    fake_guest(
      describe=fake_python_model_describe(),
      live=fake_python_model_describe(versions=["4.0.0"]),
    ),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.tuple_unavailable")
  assert_eq(run.calls, [])
  assert_eq(run.methods, [
    "morphir.extension.describe", "morphir.exit", "morphir.initialize", "morphir.shutdown",
    "morphir.exit",
  ])
  assert_false(fake_exists(workspace.root + "/drift"))
}

///|
async test "a result that is not of the agreed IR version publishes nothing" {
  let workspace = fake_workspace()
  let cases = [
    // The envelope names IR 4.0.0 under an agreed IR 3.0.0 tuple.
    ("envelope", fake_json_model_result(ir_version="4.0.0", format=3)),
    // The payload is IR 4 under an envelope of the agreed IR 3.0.0 tuple.
    ("format", fake_json_model_result(ir_version="3.0.0", format=4)),
  ]
  for case in cases {
    let (name, result) = case
    let run = fake_run(
      fake_compile_args(workspace, name) + ["--ir-version", "3"],
      fake_guest(describe=fake_python_model_describe(), reply=(_, _) => {
        Some(Ok(result))
      }),
    )
    assert_eq(run.report.exit_code(), 1, msg=run.json.stringify())
    assert_eq(fake_error(run), "extension.result_invalid")
    assert_false(fake_exists(workspace.root + "/" + name))
  }
}

///|
async test "a model generate of an IR 3.0.0 envelope sends its tuple, and --ir-version checks it" {
  let workspace = fake_workspace()
  guard fake_json_model_result(ir_version="3.0.0", format=3)
    is Object({ "model": model, .. }) else {
    fail("no model")
  }
  let input = workspace.root + "/model-envelope.json"
  @platform.write(input, model.stringify())
  let tuple : Json = {
    "operation": "morphir.backend.generateModel",
    "profile": "morphir-ir",
    "codec": "morphir-json",
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "3.0.0",
  }
  let guest = fake_guest(
    describe=extension_test_claims(
      backend={ "targets": ["moonbit"], "irVersions": ["3"], "generate": true },
      tuples=[tuple],
    ),
    reply=(_, _) => Some(Ok(fake_artifacts())),
  )
  let args = (output : String) => {
    [
      "extension",
      "generate",
      input,
      "--output",
      workspace.root + "/" + output,
      "--extension-pin",
      workspace.pin,
      "--json",
    ]
  }
  for selection in [[], ["--ir-version", "3"], ["--ir-version", "3.0.0"]] {
    let run = fake_run(
      args("generated-\{selection.length()}-\{selection.last().unwrap_or("")}") +
      selection,
      guest,
    )
    assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
    assert_eq(fake_field(run.offers[0], ["tuples"]), [tuple])
    assert_eq(fake_field(run.calls[0], ["input"]), tuple)
  }
  let run = fake_run(args("mismatch") + ["--ir-version", "4"], guest)
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.ir_version_mismatch")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
}

///|
async test "--ir-version must name a version" {
  let workspace = fake_workspace()
  let run = fake_run(
    fake_compile_args(workspace, "bad") + ["--ir-version", "4 0"],
    fake_guest(),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.input_invalid")
  assert_eq(run.methods, [])
}

///|
async test "a guest that claims only MEP 0.1 keeps the legacy compile at each --ir-version" {
  let workspace = fake_workspace()
  let describe = extension_test_claims(frontend={
    "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
    "irVersions": ["3", "4"],
    "compile": true,
    "multiDocument": true,
  })
  let run = fake_run(
    fake_compile_args(workspace, "legacy") + ["--ir-version", "5"],
    fake_guest(describe~),
  )
  // On MEP 0.1 the refusal stays the claimed-version one.
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.capability_unavailable")
  assert_eq(run.offers, [])
}

///|
/// A guest on both lines that generates from JSON models at `versions`, and
/// claims legacy generate too, like Python 0.5.
fn fake_generate_describe(versions : Array[String]) -> Json {
  extension_test_claims(
    backend={
      "targets": ["moonbit"],
      "irVersions": ["3", "4"],
      "generate": true,
    },
    tuples=versions.map(version => fake_generate_tuple(version)),
  )
}

///|
fn fake_generate_tuple(version : String) -> Json {
  {
    "operation": "morphir.backend.generateModel",
    "profile": "morphir-ir",
    "codec": "morphir-json",
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": version,
  }
}

///|
/// The arguments of a generate of the plain IR file `document`.
fn fake_plain_generate(
  workspace : FakeWorkspace,
  document : String,
  output : String,
) -> Array[String] raise {
  let path = workspace.root + "/" + output + ".morphir-ir.json"
  @platform.write(path, document)
  [
    "extension",
    "generate",
    path,
    "--output",
    workspace.root + "/" + output,
    "--extension-pin",
    workspace.pin,
    "--json",
  ]
}

///|
async test "plain IR on a guest of both lines goes with generateModel at the tuple of its format version" {
  let workspace = fake_workspace()
  let guest = fake_guest(describe=fake_generate_describe(["3.0.0", "4.0.0"]), reply=(
    _,
    _,
  ) => Some(Ok(fake_artifacts())))
  for
    case in [
      ("3.0.0", "{\"formatVersion\":3}", "plain-3"),
      ("4.0.0", "{\"formatVersion\":4}", "plain-4"),
      ("3.0.0", "{ \"formatVersion\": \"3.0.0\" }", "plain-text-3"),
    ] {
    let (version, document, output) = case
    let run = fake_run(fake_plain_generate(workspace, document, output), guest)
    assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
    assert_eq(run.methods, [
      "morphir.extension.describe", "morphir.exit", "morphir.initialize", "morphir.initialized",
      "morphir.backend.generateModel", "morphir.shutdown", "morphir.exit",
    ])
    assert_eq(fake_field(run.offers[0], ["tuples"]), [
      fake_generate_tuple(version),
    ])
    let call = run.calls[0]
    assert_eq(fake_field(call, ["input"]), fake_generate_tuple(version))
    let bytes = @utf8.encode(document)
    let expected = @worker.WrappedPlainIr::of(bytes, @json.parse(document))
    assert_eq(fake_field(call, ["model"]), expected.envelope)
    assert_eq(
      fake_field(run.json, ["result", "protocolVersion"]),
      "0.2.0-draft.1",
    )
  }
  // The same file gives the same request.
  let first = fake_run(
    fake_plain_generate(workspace, "{\"formatVersion\":4}", "same-a"),
    guest,
  )
  let second = fake_run(
    fake_plain_generate(workspace, "{\"formatVersion\":4}", "same-b"),
    guest,
  )
  assert_true(first.requests[0] == second.requests[0])
}

///|
async test "plain IR on a guest of both lines with no way to serve it is refused" {
  let workspace = fake_workspace()
  // The guest claims legacy generate at IR 3 and 4, and a generate tuple of IR
  // 4.0.0 only.
  let guest = fake_guest(describe=fake_generate_describe(["4.0.0"]), reply=(
    _,
    _,
  ) => Some(Ok(fake_artifacts())))
  let refused = async fn(document : String, output : String, code : String) {
    let run = fake_run(fake_plain_generate(workspace, document, output), guest)
    assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
    assert_eq(fake_error(run), code)
    assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
    assert_false(fake_exists(workspace.root + "/" + output))
  }
  // A format version that no tuple and no claim on MEP 0.1 includes.
  refused("{\"formatVersion\":5}", "no-host", "extension.tuple_unavailable")
  refused("{\"modules\":[]}", "no-format", "extension.input_invalid")
  // --ir-version stays a check of the file's version.
  let run = fake_run(
    fake_plain_generate(workspace, "{\"formatVersion\":4}", "mismatch") +
    ["--ir-version", "3"],
    guest,
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.ir_version_mismatch")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  // A guest on both lines with no generate tuple, and no claim of this version.
  let run = fake_run(
    fake_plain_generate(workspace, "{\"formatVersion\":3}", "no-generate"),
    fake_guest(
      describe=extension_test_claims(
        backend={
          "targets": ["moonbit"],
          "irVersions": ["4"],
          "generate": true,
        },
        tuples=[fake_tuple_at("4.0.0")],
      ),
    ),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.tuple_unavailable")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
}

///|
/// The one host warning of a fallback in a run's JSON report.
fn fake_fallback_warning(run : FakeRun) -> Json {
  guard fake_field(run.json, ["diagnostics"]) is Array(items) else {
    abort("no diagnostics")
  }
  let found = items.filter(item => {
    fake_field(item, ["code"]) == Json::string("extension.legacy_mep_fallback")
  })
  guard found is [only] else {
    abort("not one fallback warning: \{run.json.stringify()}")
  }
  only
}

///|
fn fake_has_fallback_warning(run : FakeRun) -> Bool {
  guard fake_field(run.json, ["diagnostics"]) is Array(items) else {
    return false
  }
  items
  .iter()
  .any(item => {
    fake_field(item, ["code"]) == Json::string("extension.legacy_mep_fallback")
  })
}

///|
/// Answers a legacy compile with the IR 3 distribution.
fn fake_legacy_reply(_method : String, _params : Json) -> Result[Json, Json]? {
  Some(Ok(fake_legacy_result()))
}

///|
async test "compile: no tuple for --ir-version, and a claim on MEP 0.1, succeeds on it with a warning" {
  let workspace = fake_workspace()
  let guest = fake_guest(
    describe=fake_python_model_describe(versions=["4.0.0"]),
    reply=fake_legacy_reply,
  )
  for case in ["3", "3.0.0"] {
    let run = fake_run(
      fake_compile_args(workspace, "fallback-" + case) + ["--ir-version", case],
      guest,
    )
    assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
    // The wire is MEP 0.1: no model transport, and the legacy method.
    assert_eq(run.offers, [])
    assert_eq(run.methods, [
      "morphir.extension.describe", "morphir.exit", "morphir.initialize", "morphir.initialized",
      "morphir.frontend.compile", "morphir.shutdown", "morphir.exit",
    ])
    // The claimed name goes on the wire, as MEP 0.1 has it.
    assert_eq(fake_field(run.calls[0], ["options", "irVersion"]), "3")
    assert_eq(fake_field(run.calls[0], ["output"]), Json::null())
    assert_eq(fake_field(run.json, ["result", "protocolVersion"]), "0.1")
    let warning = fake_fallback_warning(run)
    assert_eq(fake_field(warning, ["severity"]), "warning")
    assert_eq(
      fake_field(warning, ["message"]),
      "fixture-gleam 1.0.0 claims no model tuple for morphir.frontend.compileModel at IR 3.0.0, so this operation runs on legacy MEP 0.1 with morphir.frontend.compile. Update the extension to a release that claims the IR 3.0.0 model tuple, or move to IR 4.0.0.",
    )
    assert_eq(fake_field(warning, ["data", "requestedIrVersion"]), "3.0.0")
    // The default output has the same warning on stderr, by this line.
    let line = extension_diagnostic_line(
      @worker.Diagnostic::decode(warning) catch {
        error => abort(error.to_string())
      },
    )
    assert_true(
      line.has_prefix("warning extension.legacy_mep_fallback: fixture-gleam"),
      msg=line,
    )
    let file = fake_file(
      workspace.root + "/fallback-" + case + "/morphir-ir.json",
    )
    assert_true(file.contains("\"formatVersion\":3"), msg=file)
  }
  // JSON is what MEP 0.1 returns, so a JSON requirement stays satisfied.
  let run = fake_run(
    fake_compile_args(workspace, "fallback-json") +
    ["--ir-version", "3", "--model-format", "json"],
    guest,
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  ignore(fake_fallback_warning(run))
  // No IR version, and several claimed: the MEP 0.1 rule asks for one.
  let json_only_ion = extension_test_claims(
    frontend={
      "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
      "irVersions": ["3", "4"],
      "compile": true,
    },
    tuples=[fake_tuple_at("4.0.0", codec="ion-binary")],
  )
  let run = fake_run(
    fake_compile_args(workspace, "fallback-pick") + ["--model-format", "json"],
    fake_guest(describe=json_only_ion, reply=fake_legacy_reply),
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.input_invalid")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
}

///|
async test "compile: a request that MEP 0.1 cannot carry stays tuple_unavailable, with no operation session" {
  let workspace = fake_workspace()
  let guest = fake_guest(
    describe=fake_python_model_describe(versions=["4.0.0"]),
    reply=fake_legacy_reply,
  )
  for
    case in [
      ["--ir-version", "3", "--model-format", "ion"],
      ["--ir-version", "5"],
      ["--ir-version", "3.1.0"],
      ["--ir-version", "3", "--frontend-profile", "strict"],
    ] {
    let run = fake_run(
      fake_compile_args(workspace, "refused-" + case.join("-")) + case,
      guest,
    )
    assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
    assert_eq(fake_error(run), "extension.tuple_unavailable")
    assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
    assert_false(fake_has_fallback_warning(run))
  }
}

///|
async test "compile: a claimed tuple stays on the model line with no warning" {
  let workspace = fake_workspace()
  let run = fake_run(
    fake_compile_args(workspace, "python-3") + ["--ir-version", "3"],
    fake_guest(describe=fake_python_model_describe(), reply=fake_python_reply),
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(
    fake_field(run.json, ["result", "protocolVersion"]),
    "0.2.0-draft.1",
  )
  assert_false(fake_has_fallback_warning(run))
}

///|
async test "plain IR: no tuple, and a claim on MEP 0.1, goes as it is with a warning" {
  let workspace = fake_workspace()
  // Like avro 0.4.0: both lines, IR 3 and 4 on MEP 0.1, a tuple of IR 4.0.0.
  let guest = fake_guest(describe=fake_generate_describe(["4.0.0"]), reply=(
    _,
    _,
  ) => Some(Ok(fake_artifacts())))
  let document = "{ \"formatVersion\": 3, \"distribution\": [] }"
  for
    case in [
      ("plain-legacy", []),
      ("plain-legacy-major", ["--ir-version", "3"]),
      ("plain-legacy-full", ["--ir-version", "3.0.0"]),
    ] {
    let (output, flags) = case
    let run = fake_run(
      fake_plain_generate(workspace, document, output) + flags,
      guest,
    )
    assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
    assert_eq(run.offers, [])
    assert_eq(run.methods, [
      "morphir.extension.describe", "morphir.exit", "morphir.initialize", "morphir.initialized",
      "morphir.backend.generate", "morphir.shutdown", "morphir.exit",
    ])
    let call = run.calls[0]
    assert_eq(fake_field(call, ["ir"]), @json.parse(document))
    assert_eq(fake_field(call, ["input"]), Json::null())
    assert_eq(fake_field(call, ["options"]), {})
    assert_eq(fake_field(run.json, ["result", "protocolVersion"]), "0.1")
    assert_eq(
      fake_field(fake_fallback_warning(run), ["data", "input"]),
      "plain-ir",
    )
  }
  // --ir-version stays a check of the file's version on this line.
  let run = fake_run(
    fake_plain_generate(workspace, document, "plain-mismatch") +
    ["--ir-version", "4"],
    guest,
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.ir_version_mismatch")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  // The same guest at IR 4 stays on the model line.
  let run = fake_run(
    fake_plain_generate(workspace, "{\"formatVersion\":4}", "plain-model"),
    guest,
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(
    fake_field(run.json, ["result", "protocolVersion"]),
    "0.2.0-draft.1",
  )
  assert_false(fake_has_fallback_warning(run))
}

///|
/// A generate of the model envelope `envelope`.
fn fake_envelope_generate(
  workspace : FakeWorkspace,
  envelope : Json,
  output : String,
) -> Array[String] raise {
  let path = workspace.root + "/" + output + ".model.json"
  @platform.write(path, envelope.stringify())
  [
    "extension",
    "generate",
    path,
    "--output",
    workspace.root + "/" + output,
    "--extension-pin",
    workspace.pin,
    "--json",
  ]
}

///|
fn fake_json_envelope(
  document : String,
  profile~ : String = "morphir-ir",
  codec~ : String = "morphir-json",
  digest? : String,
) -> Json {
  let bytes = @utf8.encode(document)
  {
    "envelopeVersion": "0.1.0-draft.1",
    "modelId": "urn:example:model",
    "revision": "1",
    "irVersion": "3.0.0",
    "profile": profile,
    "payload": {
      "codec": codec,
      "layout": "single-document",
      "decodedByteLength": bytes.length(),
      "sha256": digest.unwrap_or(extension_sha256(bytes)),
      "content": @base64.encode(bytes[:]),
    },
    "evidence": [],
    "critical": [],
  }
}

///|
async test "model envelope: a JSON envelope with no tuple goes as its document with a warning, and Ion is refused" {
  let workspace = fake_workspace()
  let guest = fake_guest(describe=fake_generate_describe(["4.0.0"]), reply=(
    _,
    _,
  ) => Some(Ok(fake_artifacts())))
  let document = "{ \"formatVersion\": 3, \"distribution\": [] }"
  let run = fake_run(
    fake_envelope_generate(
      workspace,
      fake_json_envelope(document),
      "envelope-legacy",
    ),
    guest,
  )
  assert_eq(run.report.exit_code(), 0, msg=run.json.stringify())
  assert_eq(run.offers, [])
  assert_eq(fake_field(run.calls[0], ["ir"]), @json.parse(document))
  assert_eq(fake_field(run.json, ["result", "protocolVersion"]), "0.1")
  let warning = fake_fallback_warning(run)
  assert_eq(fake_field(warning, ["data", "input"]), "model-envelope")
  // The host does not convert: Ion has no plain form.
  let run = fake_run(
    fake_envelope_generate(
      workspace,
      fake_json_envelope(document, profile="morphir-model", codec="ion-binary"),
      "envelope-ion",
    ),
    guest,
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.tuple_unavailable")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
  // A payload that does not match what the envelope declares.
  let run = fake_run(
    fake_envelope_generate(
      workspace,
      fake_json_envelope(document, digest="0".repeat(64)),
      "envelope-corrupt",
    ),
    guest,
  )
  assert_eq(run.report.exit_code(), 2, msg=run.json.stringify())
  assert_eq(fake_error(run), "extension.input_invalid")
  assert_eq(run.methods, ["morphir.extension.describe", "morphir.exit"])
}
