///|
/// A scripted guest for the in-memory workers. `reply` answers compile and
/// generate calls: `Ok(result)`, `Err(error)` or `None` for no answer.
priv struct FakeGuest {
  describe : Json
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
        Some(Ok(fake_initialize(guest.describe, params)))
      }
      "morphir.shutdown" => Some(guest.shutdown)
      _ => {
        calls.push(params)
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
    fake_serve(worker, self.guest, self.methods, self.calls, self.offers)
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
  reply~ : (String, Json) -> Result[Json, Json]? = (_, _) => {
    Some(Ok(fake_model_result()))
  },
  shutdown~ : Result[Json, Json] = Ok({}),
  stderr~ : String = "",
) -> FakeGuest {
  { describe, reply, shutdown, stderr, }
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
fn fake_json_model_result() -> Json {
  let bytes = @utf8.encode("{\"formatVersion\":4}")
  {
    "success": true,
    "diagnostics": [],
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "irVersion": "4.0.0",
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
  // The host offers both of its tuples, in its order.
  assert_eq(run.offers.length(), 1)
  assert_eq(fake_field(run.offers[0], ["tuples"]), [
    extension_test_tuple("morphir.frontend.compileModel", "ion-binary"),
    extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
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
async test "required model tuple: --model-format json offers only JSON, which an Ion-only guest refuses" {
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
    extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
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
    "app.gleam", "nested/lib.gleam",
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
