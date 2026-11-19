///|
async test "recorded orders generate through the pinned Extism WASM worker" {
  guard @env.get_env_var("MORPHIR_MEP_BOUNDED_WASM") is Some(module_file) else {
    return
  }
  let wasm = @fs.realpath(module_file)
  let bytes = @fs.read_file(wasm).binary()
  assert_eq(bytes.length(), 19335)
  let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
  assert_eq(
    digest, "d12319c81f125c41d4e073e10d11c61bde9e64ebe14671dcf7ffffc8cb2320e0",
  )
  let host = @fs.realpath(@env.get_env_var("MORPHIR_MEP_BOUNDED_HOST").unwrap())
  let repository = @fs.realpath(
    @env.get_env_var("MORPHIR_MEP_BOUNDED_REPOSITORY").unwrap(),
  )
  let fixture = repository +
    "/apps/morphir-extension/acceptance/fixtures/acme-orders-v4/plain-json"
  let root = @fs.tmpdir(prefix="morphir-bounded-wasm-")
  defer @fs.rmdir(root, recursive=true)
  let pin = root + "/pin.json"
  let pinned : Json = {
    "contractVersion": "0.2.0",
    "artifact": { "path": wasm, "sha256": digest },
    "runtime": { "kind": "wasm", "abi": "extism-kernel-v1" },
    "origin": "fixed shared 6.2 orders module",
  }
  @fs.write_file(pin, pinned.stringify())
  let failures : Array[String] = []
  for
    (name, expected) in [
      ("frozen", b"73\n"),
      ("literal", b"74\n"),
      ("redirect", b"128\n"),
    ] {
    let task = root + "/" + name
    let model = task + "/compile.dest/model"
    let domain = model + "/pkg/acme/orders/domain/"
    copy_orders_tree(fixture, model, control=name == "literal")
    if name == "redirect" {
      let module_path = domain + "module.json"
      let module_record = @wire.object(@fs.read_file(module_path).json())
      assert_eq(module_record["values"], Json::array(["order", "total-in-USD"]))
      module_record["values"] = Json::array(["order", "reserve", "total-in-USD"])
      @fs.write_file(module_path, Json::object(module_record).stringify())
      let reference_path = domain + "total-in-_usd.value.json"
      let original = @fs.read_file(reference_path).text()
      let redirected = original.replace(
        old="acme/orders:domain#order",
        new="acme/orders:domain#reserve",
      )
      assert_true(original != redirected)
      @fs.write_file(reference_path, redirected)
      assert_true(
        @fs.read_file(domain + "order.value.json")
        .text()
        .contains("\"IntegerLiteral\": 73"),
      )
      let reserve : Json = {
        "formatVersion": 4,
        "name": "reserve",
        "def": {
          "Public": {
            "ExpressionBody": {
              "inputTypes": {},
              "outputType": "morphir/SDK:basics#int",
              "body": { "Literal": { "IntegerLiteral": 128 } },
            },
          },
        },
      }
      @fs.write_file(domain + "reserve.value.json", reserve.stringify())
    }
    let record : Json = {
      "schema": 1,
      "task": "compile",
      "module": "",
      "value": ["model"],
      "ir": {
        "path": "model",
        "layout": "document-tree",
        "format": "json",
        "version": "v4",
      },
      "completedAt": "2026-11-18T00:00:00Z",
    }
    @fs.write_file(task + "/compile.lock", "")
    @fs.write_file(task + "/compile.json", record.stringify())
    let output = task + "-output"
    let (status, stdout, stderr) = @async.with_timeout(16000, () => {
      @process.collect_output(
        host,
        [
          "extension",
          "generate",
          "--task-result",
          task + "/compile.json",
          "--extension-pin",
          pin,
          "--output",
          output,
          "--target",
          "text",
          "--timeout",
          "12000",
          "--json",
        ],
        cwd=root,
        extra_env={ "MORPHIR_HOME": root + "/home" },
      )
    })
    if status != 0 {
      assert_false(@fs.exists(output))
      failures.push(
        "\{name}: exit=\{status} \{stdout.text()}\n\{stderr.text()}",
      )
      continue
    }
    let report = @wire.parse_bounded(stdout.text())
    assert_eq(orders_field(report, ["state"]), Json::string("succeeded"))
    assert_eq(
      orders_field(report, ["result", "worker", "kind"]),
      Json::string("wasm"),
    )
    assert_eq(
      orders_field(report, ["result", "protocolVersion"]),
      Json::string("0.2.0-draft.2"),
    )
    assert_eq(
      orders_field(report, ["result", "lifecycle", "workerStopped"]),
      Json::boolean(true),
    )
    assert_eq(
      orders_field(report, ["result", "lifecycle", "worker", "code"]),
      Json::number(0),
    )
    assert_eq(
      orders_field(report, ["result", "lifecycle", "probe"]),
      Json::string("initialized"),
    )
    for key in ["memoryCeiling", "instructionBudget", "callDeadline"] {
      assert_eq(
        orders_field(report, ["result", "bounds", key, "enforced"]),
        Json::boolean(true),
      )
    }
    let events : Array[Json] = []
    for line in stderr.text().trim().split("\n") {
      events.push(@wire.parse_bounded(line.to_owned()))
    }
    assert_eq(events.length(), 2)
    assert_eq(@wire.field(events[0], "event"), Json::string("started"))
    assert_eq(@wire.field(events[0], "moduleSha256"), Json::string(digest))
    assert_eq(@wire.field(events[0], "abi"), Json::string("extism-kernel-v1"))
    assert_eq(@wire.field(events[1], "event"), Json::string("exited"))
    assert_eq(@wire.field(events[1], "exitCode"), Json::number(0))
    let limits = orders_field(report, [
      "result", "negotiated", "modelAccess", "limits",
    ])
    for
      (key, value) in [
        ("maxFrameBytes", 8192),
        ("maxEncodedBytesPerExchange", 1024),
        ("maxDecodedBytesPerExchange", 512),
        ("maxDocumentsPerBatch", 1),
        ("maxDepth", 64),
        ("maxNodes", 256),
        ("maxDiagnosticsPerExchange", 1),
        ("maxOutstandingRequests", 1),
        ("maxGuestStateBytes", 1048576),
        ("maxHostCacheBytes", 1048576),
        ("maxArtifactChunkBytes", 4),
        ("maxArtifactBytes", 4),
        ("maxTotalArtifactBytes", 4),
        ("maxSessionDiskBytes", 4096),
        ("maxSessionWorkUnits", 65536),
        ("maxRounds", 5),
        ("maxCallMilliseconds", 1000),
        ("maxSessionMilliseconds", 10000),
      ] {
      assert_eq(@wire.field(limits, key), Json::number(value.to_double()))
    }
    assert_eq(@fs.readdir(output, include_hidden=true), ["order.txt"])
    assert_eq(@fs.read_file(output + "/order.txt").binary(), expected)
    println(
      "\{name}: exact \{@utf8.decode(expected[:]).trim()}, worker stopped; \{stderr.text()}",
    )
  }
  guard failures.is_empty() else { fail(failures.join("\n")) }
}
