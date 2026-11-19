///|
let orders_source_paths : Array[String] = [
  "manifest.json", "pkg/acme/orders/audit/module.json", "pkg/acme/orders/domain/module.json",
  "pkg/acme/orders/domain/order.type.json", "pkg/acme/orders/domain/order.value.json",
  "pkg/acme/orders/domain/total-in-_usd.value.json", "deps/morphir/_sdk/@/basics/module.json",
  "deps/morphir/_sdk/@/basics/int.type.json", "deps/morphir/_sdk/@/basics/add.value.json",
]

///|
fn orders_field(value : Json, keys : Array[String]) -> Json raise {
  keys.fold(init=value, (current, key) => @wire.field(current, key))
}

///|
async fn copy_orders_tree(
  source : String,
  destination : String,
  control~ : Bool,
) -> Unit {
  for path in orders_source_paths {
    let target = destination + "/" + path
    let parent = target.rev_find("/").unwrap()
    @fs.mkdir(target[:parent], recursive=true, allow_exist=true)
    let document = @fs.read_file(source + "/" + path)
    if control && path == "pkg/acme/orders/domain/order.value.json" {
      let original = document.text()
      let changed = original.replace(
        old="\"IntegerLiteral\": 73",
        new="\"IntegerLiteral\": 74",
      )
      assert_true(changed != original)
      @fs.write_file(target, changed)
    } else {
      @fs.write_file(target, document)
    }
  }
}

///|
async test "native CLI generates orders through bounded MEP inventory" {
  generate_orders_through_native_cli(recorded=false)
}

///|
async test "native CLI generates orders under the producer read lease" {
  generate_orders_through_native_cli(recorded=true)
}

///|
async fn generate_orders_through_native_cli(recorded~ : Bool) -> Unit {
  let host = @env.get_env_var("MORPHIR_MEP_BOUNDED_HOST")
  let guest = @env.get_env_var("MORPHIR_MEP_BOUNDED_GUEST")
  let repository = @env.get_env_var("MORPHIR_MEP_BOUNDED_REPOSITORY")
  guard (host, guest, repository) is (Some(host), Some(guest), Some(repository)) else {
    guard (host, guest, repository) is (None, None, None) else {
      fail("Supply the bounded MEP host, guest, and repository together")
    }
    return
  }
  guard @env.get_env_var("MORPHIR_MEP_PLATFORM") is Some(platform) else {
    fail("Supply the native process platform in MORPHIR_MEP_PLATFORM")
  }
  let host = @fs.realpath(host)
  let guest = @fs.realpath(guest)
  let fixture = @fs.realpath(repository) +
    "/apps/morphir-extension/acceptance/fixtures/acme-orders-v4"
  let expanded = @wire.parse_bounded(
    @fs.read_file(fixture + "/single-file.json").text(),
  )
  let values = orders_field(expanded, [
    "distribution", "Library", "def", "modules", "domain", "Public", "values",
  ])
  assert_eq(
    orders_field(values, [
      "total-in-USD", "Public", "ExpressionBody", "body", "Reference",
    ]),
    Json::string("acme/orders:domain#order"),
  )
  let baseline = @wire.integer_text(
      orders_field(values, [
        "order", "Public", "ExpressionBody", "body", "Literal", "IntegerLiteral",
      ]),
    ) +
    "\n"
  assert_eq(baseline, "73\n")

  let root = @fs.tmpdir(prefix="morphir-bounded-orders-")
  defer @fs.rmdir(root, recursive=true)
  let pin = root + "/pin.json"
  let guest_digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@fs.read_file(guest).binary()),
  )
  let pin_json : Json = {
    "contractVersion": "0.2.0",
    "artifact": { "path": guest, "sha256": guest_digest },
    "runtime": { "kind": "process", "platform": platform, "args": [] },
    "origin": "local bounded orders test guest",
  }
  @fs.write_file(pin, pin_json.stringify())
  let environment = { "MORPHIR_HOME": root + "/home" }
  let described = @wire.parse_bounded(
    checked(
      host,
      [
        "extension", "describe", "--extension-pin", pin, "--timeout", "10000", "--json",
      ],
      cwd=root,
      environment~,
    ),
  )
  assert_eq(orders_field(described, ["state"]), Json::string("succeeded"))
  assert_eq(
    orders_field(described, ["result", "worker", "kind"]),
    Json::string("process"),
  )
  assert_eq(
    orders_field(described, ["result", "lifecycle", "workerStopped"]),
    Json::boolean(true),
  )
  let protocols = @wire.array(
    orders_field(described, ["result", "claims", "protocolVersions"]),
  )
  assert_true(protocols.contains(Json::string("0.2.0-draft.2")))

  let failures : Array[String] = []
  for
    (label, expected, control) in [
      ("frozen", baseline, false),
      ("control", "74\n", true),
    ] {
    let input_root = root + "/" + label
    let output = input_root + "-output"
    let tree = if recorded {
      input_root + "/compile.dest/model"
    } else {
      input_root
    }
    copy_orders_tree(fixture + "/plain-json", tree, control~)
    let selection = if recorded {
      let result = input_root + "/compile.json"
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
      @fs.write_file(input_root + "/compile.lock", "")
      @fs.write_file(result, record.stringify())
      ["--task-result", result]
    } else {
      [tree]
    }
    let (code, stdout, stderr) = @async.with_timeout(15000, async fn() {
      @process.collect_output(
        host,
        [
          "extension", "generate", ..selection, "--target", "moonbit", "--output",
          output, "--extension-pin", pin, "--timeout", "10000", "--json",
        ],
        cwd=root,
        extra_env=environment,
      )
    })
    if code != 0 {
      assert_false(@fs.exists(output))
      failures.push(
        "\{label} tree, expected order.txt = \{expected.trim()} (exit \{code})\n\{stdout.text()}\n\{stderr.text()}",
      )
      continue
    }
    let report = @wire.parse_bounded(stdout.text())
    assert_eq(orders_field(report, ["state"]), Json::string("succeeded"))
    assert_eq(
      orders_field(report, ["result", "protocolVersion"]),
      Json::string("0.2.0-draft.2"),
    )
    assert_eq(@fs.readdir(output, include_hidden=true), ["order.txt"])
    assert_eq(@fs.read_file(output + "/order.txt").text(), expected)
    assert_false(@fs.exists(output + ".morphir-partial"))
    println(
      "orders describe=draft.2 recorded=\{recorded} fixture=\{label} order.txt=\{expected.trim()}",
    )
  }
  guard failures.is_empty() else {
    fail(
      "Native process describe succeeded with MEP draft.2. Bounded generation failed:\n" +
      failures.join("\n"),
    )
  }
}
