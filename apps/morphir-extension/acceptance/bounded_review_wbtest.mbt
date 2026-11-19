///|
async test "native bounded generation enforces reviewed runtime boundaries" {
  guard @env.get_env_var("MORPHIR_MEP_BOUNDED_REVIEW") == Some("1") else {
    return
  }
  let host = @fs.realpath(@env.get_env_var("MORPHIR_MEP_BOUNDED_HOST").unwrap())
  let guest = @fs.realpath(
    @env.get_env_var("MORPHIR_MEP_BOUNDED_GUEST").unwrap(),
  )
  let repository = @fs.realpath(
    @env.get_env_var("MORPHIR_MEP_BOUNDED_REPOSITORY").unwrap(),
  )
  let platform = @env.get_env_var("MORPHIR_MEP_PLATFORM").unwrap()
  let host_digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@fs.read_file(host).binary()),
  )
  let guest_digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@fs.read_file(guest).binary()),
  )
  assert_eq(
    host_digest,
    @env.get_env_var("MORPHIR_MEP_BOUNDED_HOST_SHA256").unwrap(),
  )
  assert_eq(
    guest_digest,
    @env.get_env_var("MORPHIR_MEP_BOUNDED_GUEST_SHA256").unwrap(),
  )
  let fixture = repository +
    "/apps/morphir-extension/acceptance/fixtures/acme-orders-v4/plain-json"
  let failures : Array[String] = []
  for
    mode in [
      "deadline", "exit-deadline", "diagnostics", "inventory", "module", "cleanup",
      "encoded", "decoded", "before-decode", "forged-over", "forged-in", "exact-continue",
      "exact-complete",
    ] {
    let root = @fs.tmpdir(prefix="morphir-bounded-review-")
    defer @fs.rmdir(root, recursive=true)
    let tree = root + "/tree"
    let output = root + "/output"
    copy_orders_tree(fixture, tree, control=false)
    let module_path = tree + "/pkg/acme/orders/domain/module.json"
    if mode == "inventory" || mode == "module" {
      let document = @wire.object(@fs.read_file(module_path).json())
      document["values"] = if mode == "inventory" {
        Json::array(Array::makei(40, index => Json::string("v\{index}")))
      } else {
        {
          "inline": {
            "Public": {
              "ExpressionBody": {
                "inputTypes": {},
                "outputType": "morphir/SDK:basics#int",
                "body": { "Literal": { "IntegerLiteral": 73 } },
              },
            },
          },
        }
      }
      @fs.write_file(module_path, Json::object(document).stringify())
    }
    let args = match mode {
      "cleanup" => [mode, root]
      "encoded"
      | "decoded"
      | "before-decode"
      | "forged-over"
      | "forged-in"
      | "exact-continue"
      | "exact-complete" => ["batch", mode]
      _ => [mode]
    }
    let pin = root + "/pin.json"
    let pin_json : Json = {
      "contractVersion": "0.2.0",
      "artifact": { "path": guest, "sha256": guest_digest },
      "runtime": { "kind": "process", "platform": platform, "args": args },
      "origin": "local bounded review test guest",
    }
    @fs.write_file(pin, pin_json.stringify())
    let environment = { "MORPHIR_HOME": root + "/home" }
    let probe = @wire.parse_bounded(
      checked(
        host,
        [
          "extension", "describe", "--extension-pin", pin, "--timeout", "4000", "--json",
        ],
        cwd=root,
        environment~,
      ),
    )
    assert_eq(orders_field(probe, ["state"]), Json::string("succeeded"))
    assert_eq(
      orders_field(probe, ["result", "worker", "kind"]),
      Json::string("process"),
    )
    assert_eq(
      orders_field(probe, ["result", "lifecycle", "workerStopped"]),
      Json::boolean(true),
    )
    assert_true(
      @wire.array(orders_field(probe, ["result", "claims", "protocolVersions"])).contains(
        Json::string("0.2.0-draft.2"),
      ),
    )

    let began = @async.now()
    let (code, stdout, stderr) = @async.with_timeout(7000, async fn() {
      @process.collect_output(
        host,
        [
          "extension", "generate", tree, "--target", "moonbit", "--output", output,
          "--extension-pin", pin, "--timeout", "4000", "--json",
        ],
        cwd=root,
        extra_env=environment,
      )
    })
    let elapsed = @async.now() - began
    let report = @wire.parse_bounded(stdout.text())
    let diagnostics = @wire.array(orders_field(report, ["diagnostics"]))
    let diagnostic_bytes = @utf8.encode(Json::array(diagnostics).stringify()).length()
    let siblings = @fs.readdir(root, include_hidden=true)
    let scratch = siblings.filter(name => {
      name.has_prefix(".morphir-bounded-") ||
      name.has_prefix(".morphir-source-")
    })
    let published = @fs.exists(output)
    let error = if code == 0 {
      ""
    } else {
      @wire.string(orders_field(report, ["error", "code"]))
    }
    let message = if code == 0 {
      ""
    } else {
      @wire.string(orders_field(report, ["error", "message"]))
    }
    let exact = mode == "exact-continue" || mode == "exact-complete"
    let passed = match mode {
      "forged-in" =>
        code == 1 &&
        error == "extension.result_invalid" &&
        message.contains("declared decoded length")
      "encoded" | "decoded" | "before-decode" | "forged-over" =>
        code == 1 &&
        error == "extension.result_invalid" &&
        message.contains("artifact batch") &&
        message.contains(
          if mode == "decoded" || mode == "forged-over" {
            "decoded"
          } else {
            "encoded"
          },
        )
      "exact-continue" | "exact-complete" =>
        code == 0 &&
        published &&
        @fs.read_file(output + "/first.txt").text() == "abc" &&
        @fs.read_file(output + "/second.txt").text() == "xyz"
      "exit-deadline" =>
        code == 124 &&
        error == "extension.deadline" &&
        elapsed < 1400L &&
        stderr
        .text()
        .contains("fixture received exit after shutdown acknowledgement")
      "deadline" =>
        code == 124 && error == "extension.deadline" && elapsed < 1800L
      "diagnostics" =>
        code == 1 &&
        error == "extension.result_invalid" &&
        message.contains("diagnostic") &&
        diagnostic_bytes > 9000 &&
        diagnostic_bytes <= 32768
      "inventory" =>
        code == 2 &&
        error == "extension.input_invalid" &&
        message.contains("work")
      "module" =>
        code == 2 &&
        error == "extension.input_invalid" &&
        message.contains("split member")
      "cleanup" =>
        code == 1 &&
        error == "extension.output_failed" &&
        message.contains("directory.entry_limit") &&
        scratch.is_empty()
      _ => false
    }
    let observed = "\{mode}: describe=draft.2/stopped exit=\{code} elapsedMs=\{elapsed} diagnosticsBytes=\{diagnostic_bytes} published=\{published} scratch=\{scratch.length()} error=\{error} message=\{message}"
    println(observed)
    if published != exact || !scratch.is_empty() || !passed {
      failures.push(observed)
    }
  }
  guard failures.is_empty() else { fail(failures.join("\n")) }
}
