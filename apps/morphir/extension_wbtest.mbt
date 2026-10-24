///|
fn extension_test_pin() -> Json {
  let modules : Map[String, Json] = Map([])
  for name in extension_host_modules {
    modules[name] = Json::string("b".repeat(64))
  }
  {
    "contractVersion": "0.1.0-draft.1",
    "binding": "core-wasm-process",
    "executionProfile": {
      "id": "morphir/mep-bytes-v1/v1-draft",
      "sha256": "6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6",
    },
    "runtime": {
      "name": "node",
      "version": "v24.22.0",
      "executable": "/tools/node",
      "sha256": "a".repeat(64),
    },
    "host": { "root": "/tools/host", "modules": Json::object(modules) },
    "artifact": {
      "directory": "/tools/guest",
      "wasmSha256": "c".repeat(64),
      "manifestSha256": "d".repeat(64),
    },
    "origin": "explicit fixture",
  }
}

///|
fn extension_refused(value : Json) -> String {
  try {
    ignore(extension_pin(value))
    ""
  } catch {
    @config.Invalid(code) => code
    _ => "other"
  }
}

///|
fn extension_changed(path : Array[String], replacement : Json) -> Json {
  fn change(value : Json, depth : Int32) -> Json {
    guard value is Object(fields) else { return value }
    let copy = fields.copy()
    if depth == path.length() - 1 {
      copy[path[depth]] = replacement
    } else {
      copy[path[depth]] = change(
        fields.get(path[depth]).unwrap_or(Json::null()),
        depth + 1,
      )
    }
    Json::object(copy)
  }

  change(extension_test_pin(), 0)
}

///|
test "extension pins admit only the qualified binding, runtime and profile" {
  let pin = extension_pin(extension_test_pin())
  assert_true(pin.binding is CoreWasmProcess)
  assert_true(pin.runtime is Node24_22_0)
  assert_eq(pin.to_json(), extension_test_pin())
  let patched = extension_changed(
    ["runtime", "version"],
    Json::string("v24.22.1"),
  )
  let patched_pin = extension_pin(patched)
  assert_true(patched_pin.runtime is Node24_22_1)
  assert_eq(patched_pin.to_json(), patched)
  assert_eq(
    extension_refused(
      extension_changed(["binding"], Json::string("component-model")),
    ),
    "extension.unsupported_binding",
  )
  assert_eq(
    extension_refused(
      extension_changed(["runtime", "version"], Json::string("v24.22.2")),
    ),
    "extension.unsupported_runtime",
  )
  assert_eq(
    extension_refused(
      extension_changed(
        ["executionProfile", "sha256"],
        Json::string("e".repeat(64)),
      ),
    ),
    "extension.unsupported_execution_profile",
  )
  assert_eq(
    extension_refused(
      extension_changed(["runtime", "executable"], Json::string("node")),
    ),
    "extension.invalid_pin",
  )
  assert_eq(
    extension_refused(
      extension_changed(["artifact", "wasmSha256"], Json::string("ABC")),
    ),
    "extension.invalid_pin",
  )
  assert_eq(
    extension_refused(extension_changed(["unknown"], Json::boolean(true))),
    "extension.invalid_pin",
  )
  guard extension_test_pin() is Object(fields) &&
    fields.get("host") is Some(Object(host)) &&
    host.get("modules") is Some(Object(modules)) else {
    abort("fixture pin")
  }
  let partial = modules.copy()
  partial.remove("dist/bridge.mjs")
  partial["other.mjs"] = Json::string("b".repeat(64))
  assert_eq(
    extension_refused(
      extension_changed(["host", "modules"], Json::object(partial)),
    ),
    "extension.incomplete_host_modules",
  )
}

///|
test "extension sessions offer exactly the selected tuple and end with exit" {
  let describe = extension_messages(Describe, None, {})
  assert_eq(describe.length(), 2)
  assert_eq(describe[1], { "jsonrpc": "2.0", "method": "morphir.exit" })
  let compile = extension_messages(Compile, Some(JsonIr), { "x": 1 })
  assert_eq(
    compile.map(m => {
      guard m is Object(fields) && fields.get("method") is Some(String(name)) else {
        return ""
      }
      name
    }),
    [
      "morphir.extension.describe", "morphir.initialize", "morphir.frontend.compileModel",
      "morphir.shutdown", "morphir.exit",
    ],
  )
  guard compile[1] is Object(fields) &&
    fields.get("params") is Some(Object(params)) &&
    params.get("modelTransport") is Some(Object(transport)) else {
    abort("initialize")
  }
  assert_eq(
    transport.get("tuples"),
    Some(Json::array([JsonIr.tuple("morphir.frontend.compileModel")])),
  )
  assert_eq(transport.get("limits"), Some(extension_limits))
}

///|
test "extension source identities never expose absolute host paths" {
  assert_eq(extension_document_uri("src/main.mbt"), "src/main.mbt")
  assert_eq(extension_document_uri("/home/user/work/main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("../outside/main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("C:\\work\\lib.mbt"), "lib.mbt")
  assert_true(
    try {
      ignore(extension_document_uri("notes.txt"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "extension envelopes select only the qualified model tuples" {
  let envelope : Json = {
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
    "profile": "morphir-model",
    "payload": { "codec": "ion-binary" },
  }
  assert_eq(extension_envelope_tuple(envelope), IonModel)
  guard envelope is Object(fields) else { abort("envelope") }
  let json = fields.copy()
  json["profile"] = Json::string("morphir-ir")
  json["payload"] = { "codec": "morphir-json" }
  assert_eq(extension_envelope_tuple(Json::object(json)), JsonIr)
  let mixed = fields.copy()
  mixed["payload"] = { "codec": "morphir-json" }
  let draft = fields.copy()
  draft["irVersion"] = Json::string("3.0.0")
  for candidate in [Json::object(mixed), Json::object(draft), Json::null()] {
    assert_true(
      try {
        ignore(extension_envelope_tuple(candidate))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
fn extension_test_plan(operation : ExtensionOperation) -> ExtensionPlan {
  let tuple = if operation is Describe { None } else { Some(IonModel) }
  {
    operation,
    messages: extension_messages(operation, tuple, {}),
    tuple,
    output: "",
  }
}

///|
fn extension_test_frames(responses : Array[Json]) -> Bytes {
  let buffer = Buffer()
  for response in responses {
    buffer.write_bytes(@mep.encode_frame(response.stringify())) catch {
      _ => abort("frame")
    }
  }
  buffer.to_bytes()
}

///|
fn extension_test_process(state : String, code : Int32?) -> ExtensionProcess {
  { state, exit_code: code, stderr: "", error: "", work_directory_empty: true, }
}

///|
fn extension_test_responses(result : Json) -> Array[Json] {
  [
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": { "extension": { "id": "guest", "version": "1" } },
    },
    {
      "jsonrpc": "2.0",
      "id": 2,
      "result": {
        "protocolVersion": "0.2.0-draft.1",
        "capabilities": {
          "modelTransport": {
            "tuples": [IonModel.tuple("morphir.frontend.compileModel")],
            "limits": extension_limits,
          },
        },
      },
    },
    { "jsonrpc": "2.0", "id": 3, "result": result },
    { "jsonrpc": "2.0", "id": 4, "result": {} },
  ]
}

///|
test "extension outcomes require a complete, ordered and acknowledged session" {
  let plan = extension_test_plan(Compile)
  let exited = extension_test_process("exited", Some(0))
  let success = extension_outcome(
    plan,
    exited,
    extension_test_frames(extension_test_responses({ "success": true })),
  )
  assert_eq(success.state, "completed")
  assert_eq(success.exit_code, 0)
  assert_eq(success.shutdown, "acknowledged")
  let unsuccessful = extension_outcome(
    plan,
    exited,
    extension_test_frames(extension_test_responses({ "success": false })),
  )
  assert_eq(unsuccessful.exit_code, 1)
  assert_eq(unsuccessful.error, "extension.operation_unsuccessful")
  // A guest that dies after answering initialize is not a completed session.
  let partial = extension_test_responses({ "success": true })[:2].to_owned()
  let crashed = extension_outcome(
    plan,
    extension_test_process("exited", Some(1)),
    extension_test_frames(partial),
  )
  assert_eq(crashed.state, "failed")
  assert_true(crashed.error.has_prefix("extension.incomplete_session"))
  // Out-of-order identifiers and truncated frames are invalid responses.
  let swapped = extension_test_responses({ "success": true })
  let first = swapped[0]
  swapped[0] = swapped[1]
  swapped[1] = first
  assert_eq(
    extension_outcome(plan, exited, extension_test_frames(swapped)).error,
    "extension.invalid_response",
  )
  let truncated = extension_test_frames(
    extension_test_responses({ "success": true }),
  )
  assert_eq(
    extension_outcome(
      plan,
      exited,
      truncated[:truncated.length() - 1].to_bytes(),
    ).error,
    "extension.invalid_frame",
  )
  let extra = extension_test_responses({ "success": true })
  extra.push({ "jsonrpc": "2.0", "id": 5, "result": {} })
  assert_eq(
    extension_outcome(plan, exited, extension_test_frames(extra)).error,
    "extension.unsolicited_response",
  )
}

///|
test "extension negotiation refusals and host stops map to distinct states" {
  let plan = extension_test_plan(Compile)
  let exited = extension_test_process("exited", Some(0))
  let refused = extension_test_responses({ "success": true })
  refused[1] = {
    "jsonrpc": "2.0",
    "id": 2,
    "error": { "code": -32602, "message": "Invalid model transport offer" },
  }
  let outcome = extension_outcome(plan, exited, extension_test_frames(refused))
  assert_eq(outcome.state, "refused")
  assert_eq(outcome.exit_code, 2)
  assert_true(outcome.error.contains("Invalid model transport offer"))
  let empty = extension_test_responses({ "success": true })
  empty[1] = {
    "jsonrpc": "2.0",
    "id": 2,
    "result": {
      "protocolVersion": "0.2.0-draft.1",
      "capabilities": { "modelTransport": { "tuples": [], "limits": {} } },
    },
  }
  assert_eq(
    extension_outcome(plan, exited, extension_test_frames(empty)).error,
    "extension.tuple_unavailable",
  )
  let error = extension_test_responses({ "success": true })
  error[2] = {
    "jsonrpc": "2.0",
    "id": 3,
    "error": { "code": -32602, "message": "Unknown compilation parameter" },
  }
  let operation = extension_outcome(plan, exited, extension_test_frames(error))
  assert_eq(operation.exit_code, 1)
  assert_true(operation.error.has_prefix("extension.operation_error"))
  let stopped = fn(state, error) {
    extension_outcome(
      plan,
      { ..extension_test_process(state, None), error, },
      b"",
    )
  }
  assert_eq(stopped("cancelled", "execution.cancelled").exit_code, 130)
  assert_eq(stopped("failed", "execution.deadline").exit_code, 124)
  assert_eq(stopped("refused", "execution.deadline").exit_code, 124)
  assert_eq(stopped("failed", "extension.guest_signalled").exit_code, 1)
  assert_eq(stopped("refused", "extension.identity_mismatch").exit_code, 2)
  let describe = extension_outcome(
    extension_test_plan(Describe),
    exited,
    extension_test_frames(extension_test_responses({})[:1].to_owned()),
  )
  assert_eq(describe.exit_code, 0)
  assert_eq(describe.shutdown, "not-applicable")
}

///|
test "extension results publish only intact models and confined artifacts" {
  let bytes = b"\xe0\x01\x00\xea"
  let result : Json = {
    "success": true,
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "irVersion": "4.0.0",
      "profile": "morphir-model",
      "payload": {
        "codec": "ion-binary",
        "decodedByteLength": 4,
        "sha256": extension_sha256(bytes),
        "content": @base64.encode(bytes[:]),
      },
    },
  }
  assert_eq(extension_model_bytes(result, IonModel).1, bytes)
  assert_true(
    try {
      ignore(extension_model_bytes(result, JsonIr))
      false
    } catch {
      _ => true
    },
  )
  let tampered = result
    .stringify()
    .replace(old="\"decodedByteLength\":4", new="\"decodedByteLength\":5")
  assert_eq(
    try {
      ignore(extension_model_bytes(@json.parse(tampered), IonModel))
      ""
    } catch {
      @config.Invalid(code) => code
      _ => "other"
    },
    "extension.model_integrity",
  )
  let artifact = fn(path : String) -> Json {
    {
      "success": true,
      "artifacts": [{ "path": path, "content": "x", "binary": false }],
    }
  }
  assert_eq(
    extension_artifacts(artifact("mep/source.json"))[0].0,
    "mep/source.json",
  )
  for path in ["../escape", "/abs", "a//b", "a\\b", "c:x", "./a"] {
    assert_true(
      try {
        ignore(extension_artifacts(artifact(path)))
        false
      } catch {
        _ => true
      },
      msg=path,
    )
  }
  let collision : Json = {
    "artifacts": [
      { "path": "a", "content": "x", "binary": false },
      { "path": "a/b", "content": "y", "binary": false },
    ],
  }
  assert_true(
    try {
      ignore(extension_artifacts(collision))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "extension command syntax keeps its own options" {
  let cli = parse_cli([
    "extension", "compile", "src/main.mbt", "--extension-pin", "pin.json", "--package",
    "my/pkg", "--output", "out",
  ])
  assert_eq(cli.command, "extension compile")
  assert_eq(value(cli, "path"), "src/main.mbt")
  assert_true(
    try {
      ignore(parse_cli(["extension", "describe", "--package", "x"]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(parse_cli(["extension"]))
      false
    } catch {
      _ => true
    },
  )
}
