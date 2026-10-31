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
async test "byte callback adapter: the portable guest returns the same envelopes as the native guest" {
  guard cli() is Some(path) &&
    prerequisite("MORPHIR_PORTABLE_GUEST") is Some(portable) &&
    prerequisite("MORPHIR_NATIVE_GUEST") is Some(native) else {
    return
  }
  let machine = @process.host_machine().unwrap()
  let wasm_bytes = @fs.read_file(portable).binary()
  let native_bytes = @fs.read_file(native).binary()
  with_host(path, wasm_host => {
    let process_host = @worker.Host::new(
      @process.ProcessLauncher::new(),
      Native(machine),
    )
    let (wasm_claims, wasm_compiled, wasm_generated) = describe_compile_generate(
      wasm_host,
      wasm_spec(wasm_bytes, abi=MorphirBytesV1),
    )
    let (native_claims, native_compiled, native_generated) = describe_compile_generate(
      process_host,
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
    assert_true(wasm_generated.stringify().contains("add"))
  })
}

///|
async test "Python from the native CLI: compile runs in a worker process that is gone afterwards" {
  guard cli() is Some(path) &&
    prerequisite("MORPHIR_PYTHON_EXTENSIONS") is Some(root) else {
    return
  }
  with_host(path, wasm_host => {
    for version in ["0.4.1", "0.4.2"] {
      let bytes = @fs.read_file(
        "\{root}/\{version}/morphir-python-binding-\{version}.wasm",
      ).binary()
      let spec = wasm_spec(bytes, abi=ExtismKernelV1)
      let claims = wasm_host.probe(spec).claims
      let session = wasm_host.activate(spec, expected=claims, offer=Legacy)
      let outcome = session.compile(
        @worker.CompileRequest::new({
          "languageId": "python",
          "sources": {
            "documents": [
              {
                "uri": "file:///work/acme/models.py",
                "languageId": "python",
                "version": 1,
                "text": "from dataclasses import dataclass\n\n@dataclass(frozen=True)\nclass Approved:\n    amount: float\n",
              },
            ],
          },
          "package": { "name": "acme" },
          "dependencies": [],
          "options": { "irVersion": "4", "typesOnly": false },
        }),
      )
      guard outcome.class is Completed(compiled) else {
        fail("Python \{version} did not compile: \{@debug.to_string(outcome)}")
      }
      assert_true(compiled.result.stringify().contains("\"amount\""))
      let report = session.close()
      guard report.stop is Some(stop) else { fail("no worker stop") }
      // The worker exited after `exit`; the launcher confirmed its group gone.
      assert_eq(stop.status, Exited(code=0))
      assert_eq(report.extism, Some(@worker.ExtismProfile::restricted()))
    }
  })
}

///|
/// A workspace for the Python 0.4.2 extension commands of the native CLI: a
/// contract 0.2.0 pin with an `extism-kernel-v1` runtime, and
/// `src/models.py`.
async fn python_workspace(root : String, directory : String) -> Unit {
  let module_ = "\{root}/0.4.2/morphir-python-binding-0.4.2.wasm"
  let bytes = @fs.read_file(module_).binary()
  let pin : Json = {
    "contractVersion": "0.2.0",
    "artifact": {
      "path": module_,
      "sha256": @worker.Sha256::of(bytes).to_string(),
    },
    "runtime": { "kind": "wasm", "abi": "extism-kernel-v1" },
    "origin": "finos/morphir-python extension/python/v0.4.2",
  }
  @fs.write_file("\{directory}/pin.json", pin.stringify())
  @fs.mkdir("\{directory}/src")
  @fs.write_file(
    "\{directory}/src/models.py",
    "from dataclasses import dataclass\n\n@dataclass(frozen=True)\nclass Approved:\n    amount: float\n",
  )
}

///|
/// Runs one `extension` command of the CLI at `path` with `--json` in
/// `directory`. Returns the exit status and the command result on stdout.
async fn extension_command(
  path : String,
  directory : String,
  args : Array[String],
) -> (Int32, Json) {
  let (code, out, err) = @spawn.collect_output(
    path,
    ["extension", ..args, "--extension-pin", "pin.json", "--json"],
    cwd=directory,
  )
  let result = @json.parse(out.text()) catch {
    _ => fail("not a command result: \{out.text()} \{err.text()}")
  }
  (code, result)
}

///|
/// The format version of a Morphir IR JSON file.
async fn format_version(file : String) -> Json? {
  guard @json.parse(@fs.read_file(file).text())
    is { "formatVersion": version, .. } else {
    return None
  }
  Some(version)
}

///|
async test "Python from the native CLI: compile follows --ir-version and generate follows the model" {
  guard cli() is Some(path) &&
    prerequisite("MORPHIR_PYTHON_EXTENSIONS") is Some(root) else {
    return
  }
  let directory = @fs.tmpdir(prefix="morphir-wasm-python-cli-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  python_workspace(root, directory)
  // Python 0.4.2 claims IR versions 3 and 4. Compile sends the selected one
  // as options.irVersion and checks the result's IR.
  for version in [3, 4] {
    let (code, result) = extension_command(path, directory, [
      "compile",
      "src/models.py",
      "--package",
      "acme",
      "--ir-version",
      version.to_string(),
      "--output",
      "ir\{version}",
    ])
    guard code == 0 && result is { "state": "succeeded", .. } else {
      fail("compile --ir-version \{version} failed: \{result.stringify()}")
    }
    assert_eq(
      format_version("\{directory}/ir\{version}/morphir-ir.json"),
      Some(Json::number(version.to_double())),
    )
  }
  // Generate reads the IR version from the model. --ir-version is a check
  // that agrees with it, and without it the model's version is used.
  for generate in [("ir3", ["--ir-version", "3"]), ("ir4", []), ("ir3", [])] {
    let (model, check) = generate
    let output = "python-\{model}-\{check.length()}"
    let (code, result) = extension_command(
      path,
      directory,
      [
        "generate",
        "\{model}/morphir-ir.json",
        "--target",
        "python",
        "--output",
        output,
        ..check,
      ],
    )
    guard code == 0 && result is { "state": "succeeded", .. } else {
      fail("generate from \{model} failed: \{result.stringify()}")
    }
    assert_true(
      @fs.read_file("\{directory}/\{output}/src/models.py")
      .text()
      .contains("Approved"),
    )
  }
  // A model whose formatVersion differs from --ir-version is refused before
  // a session, and nothing is written.
  let (code, result) = extension_command(path, directory, [
    "generate", "ir3/morphir-ir.json", "--target", "python", "--ir-version", "4",
    "--output", "mismatch",
  ])
  assert_eq(code, 2)
  guard result
    is {
      "state": "failed",
      "exitCode": 2,
      "error": { "code": "extension.ir_version_mismatch", .. },
      ..
    } else {
    fail("the mismatch was not refused: \{result.stringify()}")
  }
  assert_false(@fs.exists("\{directory}/mismatch"))
}
