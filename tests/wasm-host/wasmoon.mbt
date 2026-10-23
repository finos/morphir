///|
fn resource_probe(bytes : Bytes) -> Json raise {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let prefix = "morphir:lifetime-probe/sessions@0.1.0#"
  let instance = runtime.instantiate("resources-probe", bytes)
  let construct = instance.bind(prefix + "[constructor]session")
  let read = instance.bind(prefix + "[method]session.read")
  let borrow = instance.bind(prefix + "read-borrowed")
  let take = instance.bind(prefix + "take")
  let live = instance.bind(prefix + "live")
  let dropped = instance.bind(prefix + "dropped")
  let label : @component.ComponentValue = String("Session 😀 𝄞 雪\u0000")
  let resource = construct.call([label]) catch {
    InvocationFailed(message) if message.contains(
        "component returned a value incompatible with Own(",
      ) &&
      message.contains(" at result") =>
      // A gap observed at the public facade boundary. Do not use runtime_impl
      // or patch the engine just to turn this into a positive capability claim.
      return Json::object(
        Map::from_array([
          ("status", Json::string("unsupported")),
          ("phase", Json::string("constructor-result")),
          ("failure", Json::string(message)),
        ]),
      )
    error => raise error
  }
  assert_true(resource is [Resource(_)])
  let first_read = read.call(resource) catch {
    error => fail("Resource method failed: " + error.to_string())
  }
  assert_eq(first_read, [label])
  for _ in 0..<100 {
    assert_eq(borrow.call(resource), [label])
  }
  assert_eq(live.call([]), [U32(1U)])
  assert_eq(dropped.call([]), [U32(0U)])
  assert_eq(take.call(resource), [label])
  assert_eq(live.call([]), [U32(0U)])
  assert_eq(dropped.call([]), [U32(1U)])
  let stale_refused = try {
    borrow.call(resource) |> ignore
    false
  } catch {
    InvocationFailed(message) => message.contains("resource")
    _ => false
  }
  assert_true(stale_refused)
  let fresh = runtime.instantiate("resources-other", bytes)
  let foreign = fresh
    .bind(prefix + "[constructor]session")
    .call([String("foreign")])
  let cross_instance_refused = try {
    borrow.call(foreign) |> ignore
    false
  } catch {
    InvocationFailed(message) => message.contains("resource")
    TypeMismatch(..) => true
    _ => false
  }
  assert_true(cross_instance_refused)
  assert_eq(fresh.bind(prefix + "[method]session.read").call(foreign), [
    String("foreign"),
  ])
  assert_eq(fresh.bind(prefix + "take").call(foreign), [String("foreign")])
  assert_eq(fresh.bind(prefix + "live").call([]), [U32(0U)])
  assert_eq(fresh.bind(prefix + "dropped").call([]), [U32(1U)])
  Json::object(
    Map::from_array([
      ("status", Json::string("qualified")),
      ("borrowedCalls", Json::number(100)),
      ("ownedTransfer", Json::boolean(true)),
      ("destructorExactlyOnce", Json::boolean(true)),
      ("consumedHandleRefused", Json::boolean(true)),
      ("crossInstanceRefusal", Json::boolean(true)),
    ]),
  )
}

///|
fn callback_probe(bytes : Bytes) -> Json raise {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let message = try {
    runtime.instantiate("callbacks-no-import", bytes) |> ignore
    fail(
      "A component requiring a host callback instantiated without that capability",
    )
  } catch {
    @component.ComponentRuntimeError::InstantiationFailed(message) => message
    error => raise error
  }
  assert_true(message.contains("morphir:lifetime-probe/host"))
  Json::object(
    Map::from_array([
      ("status", Json::string("unsupported")),
      (
        "reason",
        Json::string(
          "The pinned public facade exposes no general callback installer",
        ),
      ),
      ("missingImportRefused", Json::boolean(true)),
      ("failure", Json::string(message)),
    ]),
  )
}

///|
async fn execute(paths : ArrayView[String]) -> Json {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let bytes = @fs.read_file(paths[0]).binary()
  let instance = runtime.instantiate("moonbit-rich-probe", bytes)
  let exchange = instance.bind("exchange")
  let calls = instance.bind("calls")
  let packet : @component.ComponentValue = Record([
    ("label", String("Morphir 😀 𝄞 e\u0301 雪\u0000")),
    ("payload", List([U8(224), U8(1), U8(0), U8(234), U8(33), U8(42)])),
    ("encoding", Enum("ion-binary")),
  ])
  assert_eq(calls.call([]), [U32(0U)])
  let first = exchange.call([packet])
  assert_eq(first, [ResultOk(Some(packet))])
  for _ in 0..<100 {
    assert_eq(exchange.call([packet]), first)
  }
  assert_eq(first, [ResultOk(Some(packet))])
  assert_eq(calls.call([]), [U32(101U)])
  let wrong_type = try {
    exchange.call([U32(1U)]) |> ignore
    false
  } catch {
    TypeMismatch(..) => true
    _ => false
  }
  assert_true(wrong_type)
  assert_eq(calls.call([]), [U32(101U)])
  instance.bind("close").call([]) |> ignore
  assert_eq(exchange.call([packet]), [ResultErr(Some(Variant("closed", None)))])
  let fresh = runtime.instantiate("moonbit-fresh-probe", bytes)
  assert_eq(fresh.bind("calls").call([]), [U32(0U)])
  let spin = fresh.bind("spin")
  let bounded = try {
    runtime.with_execution_limits(safepoints=Some(5000L), fn() raise {
      spin.call([]) |> ignore
    })
    false
  } catch {
    @component.ComponentRuntimeError::ExecutionBudgetExceeded => true
    _ => false
  }
  assert_true(bounded)
  let resources = resource_probe(@fs.read_file(paths[1]).binary())
  let callbacks = callback_probe(@fs.read_file(paths[2]).binary())
  runtime.close()
  runtime.close()
  let closed = try {
    calls.call([]) |> ignore
    false
  } catch {
    RuntimeClosed => true
    _ => false
  }
  assert_true(closed)
  let report = @json.parse(
    "{\"host\":\"wasmoon-native-interpreter\",\"unicode\":true,\"ionBytes\":true,\"acceptedCalls\":101,\"typeRefusal\":true,\"closedResult\":true,\"freshInstance\":true,\"executionBudget\":true,\"runtimeClosed\":true}",
  )
  guard report is Object(fields) else { fail("Invalid evidence object") }
  fields["resources"] = resources
  fields["callbacks"] = callbacks
  report
}

///|
#cfg(target="js")
fn cli_arguments() -> ArrayView[String] {
  @env.args()[2:]
}

///|
#cfg(not(target="js"))
fn cli_arguments() -> ArrayView[String] {
  @env.args()[1:]
}

///|
fn json_command() -> @argparse.Command {
  @argparse.Command(
    "wasmoon-host-probe",
    about="Probe existing component files; COMPONENT RESOURCES CALLBACKS --json preserves the bare evidence object",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[
      @argparse.FlagArg("json", required=true),
      @argparse.FlagArg("help"),
      @argparse.FlagArg("self-test"),
    ],
    options=[
      @argparse.OptionArg("component", requires=["resources", "callbacks"]),
      @argparse.OptionArg("resources", requires=["component"]),
      @argparse.OptionArg("callbacks", requires=["component"]),
    ],
    groups=[
      @argparse.ArgGroup("operation", required=true, multiple=false, args=[
        "help", "self-test", "component",
      ]),
    ],
  )
}

///|
fn json_arguments(argv : ArrayView[String]) -> Array[String] {
  match argv {
    [component, resources, callbacks, "--json"]
    | ["--json", "--", component, resources, callbacks] =>
      [
        "--json",
        "--component=" + component,
        "--resources=" + resources,
        "--callbacks=" + callbacks,
      ]
    ["--help", "--json"] => ["--json", "--help"]
    ["--self-test", "--json"] => ["--json", "--self-test"]
    _ => argv.to_owned()
  }
}

///|
fn completion(result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "wasm.host.wasmoon",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
async fn main {
  let argv = cli_arguments()
  let json_mode = match argv {
    [_, _, _, "--json", ..]
    | ["--json", "--", ..]
    | ["--json", "--help" | "--self-test"]
    | ["--help" | "--self-test", "--json", ..] => true
    _ => false
  }
  if !json_mode {
    println(execute(argv).stringify())
    return
  }
  try {
    let count = match argv {
      ["--json", "--", ..] => 5
      [_, _, _, "--json", ..] => 4
      _ => 2
    }
    ignore(
      @argparse.Command(
        "wasmoon-host-probe",
        disable_help_flag=true,
        disable_help_subcommand=true,
        positionals=[
          @argparse.PositionArg(
            "argument",
            num_args=@argparse.ValueRange(lower=count, upper=count),
          ),
        ],
      ).parse(argv=["--"] + argv.to_owned(), env=Map([])),
    )
    let matches = json_command().parse(argv=json_arguments(argv), env=Map([]))
    let result = if matches.flags.get("help").unwrap_or(false) {
      completion({ "render_help": json_command().render_help() })
    } else if matches.flags.get("self-test").unwrap_or(false) {
      for path in ["", "--", "--json", "--help", "資料/component 😀"] {
        let parsed = json_command().parse(
          argv=json_arguments([path, path, path, "--json"]),
          env=Map([]),
        )
        assert_eq(parsed.values["component"], [path])
        assert_eq(parsed.values["resources"], [path])
        assert_eq(parsed.values["callbacks"], [path])
      }
      completion({ "passed": true })
    } else {
      // Existing report consumers require the bare evidence object.
      execute([
        matches.values["component"][0],
        matches.values["resources"][0],
        matches.values["callbacks"][0],
      ])
    }
    @stdio.stdout.write(result.stringify() + "\n")
  } catch {
    error => {
      let message = error.to_string()
      let result : Json = {
        "profile": "morphir/command-result",
        "contractVersion": "0.1.0",
        "command": "wasm.host.wasmoon",
        "state": "failed",
        "exitCode": 1,
        "error": { "code": "command_failed", "message": message },
        "diagnostics": [],
      }
      @stdio.stderr.write(message + "\n")
      @stdio.stdout.write(result.stringify() + "\n")
      @sys.exit(1)
    }
  }
}
