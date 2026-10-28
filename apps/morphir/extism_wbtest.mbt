///|
fn extism_test_pin() -> Json {
  let modules : Map[String, Json] = Map([])
  for name in extism_helper_modules {
    modules[name] = Json::string("b".repeat(64))
  }
  {
    "contractVersion": "0.1.0",
    "binding": "extism-wasm",
    "executionProfile": extism_execution_profile,
    "host": {
      "executable": "/tools/adapter",
      "sha256": "a".repeat(64),
      "sourceRevision": native_services_revision,
    },
    "runtime": {
      "executable": "/tools/node",
      "version": "v24.22.1",
      "sha256": "a".repeat(64),
    },
    "helper": { "root": "/tools/helper", "modules": Json::object(modules) },
    "artifact": {
      "directory": "/tools/python",
      "descriptorSha256": "c".repeat(64),
      "wasmSha256": "d".repeat(64),
      "extensionId": "morphir-python",
      "version": "0.4.1",
    },
    "origin": "real-bundle qualification fixture",
  }
}

///|
test "Extism profile requires exact closure and separate binding" {
  assert_eq(extism_pin(extism_test_pin()), extism_test_pin())
  let bad = match extism_test_pin() {
    Object(fields) => fields.copy()
    _ => abort("object")
  }
  bad["binding"] = Json::string("core-wasm-process")
  let refused = try {
    ignore(extism_pin(Json::object(bad)))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  bad["binding"] = Json::string("extism-wasm")
  bad["unknown"] = Json::boolean(true)
  let refused = try {
    ignore(extism_pin(Json::object(bad)))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "Extism IR selection is explicit and aliases only exact supported releases" {
  assert_eq(extism_ir_version("3"), extism_ir_version("3.0.0"))
  assert_eq(extism_ir_version("4"), extism_ir_version("4.0.0"))
  for version in ["", "1", "2", "3.1.0", "4.0.0-draft.1", "latest"] {
    let refused = try {
      ignore(extism_ir_version(version))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "Extism owns IR and JSON options on explicit command arrays" {
  for operation in ["compile", "generate"] {
    let cli = parse_cli([
      "extension", operation, "input", "--ir-version", "3.0.0", "--model-format",
      "json", "--json", "--output", "out",
    ])
    assert_eq(value(cli, "ir-version"), "3.0.0")
    assert_eq(value(cli, "model-format"), "json")
    assert_true(flag(cli, "json"))
  }
  let cli = parse_cli(["extension", "describe", "--help", "--json"])
  assert_true(cli.help)
  assert_true(flag(cli, "json"))
}

///|
test "Extism refusal has finite failure schema and retains cancellation" {
  let failure = extism_report(
    "extension compile",
    Json::null(),
    "extension.ir_version_mismatch: selected 3",
    1,
    [],
  )
  assert_eq(
    failure.stringify(),
    "{\"profile\":\"morphir/command-result\",\"contractVersion\":\"0.1.0\",\"command\":\"extension.compile\",\"state\":\"failed\",\"exitCode\":1,\"diagnostics\":[],\"error\":{\"code\":\"extension.ir_version_mismatch\",\"message\":\"extension.ir_version_mismatch: selected 3\"}}",
  )
  let cancel = extism_report(
    "extension generate",
    Json::null(),
    "execution.cancelled",
    130,
    [],
  )
  guard cancel is Object(fields) else { abort("object") }
  assert_eq(fields.get("exitCode"), Some(Json(130)))
  assert_eq(fields.get("result"), None)
}

///|
test "Extism plain-IR boundary refuses rich envelopes and version mismatch" {
  let models : Array[Json] = [
    { "envelopeVersion": "0.1.0-draft.1", "payload": {} },
    { "formatVersion": 3, "distribution": [] },
    { "formatVersion": "3.1.0", "distribution": [] },
  ]
  for model in models {
    let refused = try {
      ignore(extism_model(model, PythonV4))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
#cfg(any(target="native", target="js"))
test "Extism deadline refuses publication before creating storage" {
  let refused = try {
    ignore(
      extension_publish("/unused-extism-test-destination", [], check=() => {
        extism_tick(-1.0)
      }),
    )
    false
  } catch {
    @config.Invalid(message) => message == "extension.timeout"
    _ => false
  }
  assert_true(refused)
}

///|
#cfg(any(target="native", target="js"))
test "Extism late cancellation refuses the publication rename and exits 130" {
  let root = @platform.temporary()
  let marker = root + "/cancel"
  let output = root + "/published"
  defer {
    @platform.remove_file(marker) catch {
      _ => ()
    }
    @platform.remove_dir(root) catch {
      _ => ()
    }
  }
  let mut checks = 0
  let error = try {
    ignore(
      extension_publish(output, [("module.py", b"result = 1")], check=() => {
        checks += 1
        // The file arrives after staging and its file write, before final rename.
        if checks == 3 {
          @platform.write(marker, "")
        }
        extism_tick(@platform.monotonic_seconds() + 30.0, cancel_file=marker)
      }),
    )
    "unexpected success"
  } catch {
    cause => @host.error_message(cause)
  }
  assert_eq(checks, 3)
  assert_eq(error, "execution.cancelled")
  assert_eq(extism_failure_status(error), 130)
  assert_eq(@platform.kind(output), 0)
  assert_eq(@platform.kind(output + ".morphir-partial"), 0)
}
