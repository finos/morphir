///|
async fn assert_middleware_timing() -> Unit {
  let logs = @logging.MemoryLogger::new()
  let ticks = Ref(1.0)
  let context : CommandContext = {
    mode: JSON,
    configuration: @config.from_json({ "fixture": true }, origin="test").framework(),
    logger: logs,
    clock: fn() { ticks.val },
    check_cancelled: fn() { () },
    stop_requested: fn() { false },
    failed: fn(_, _) { -1 },
    workers: WorkerHosting::none(),
  }
  let sender : @mediator_async.Sender[CommandContext, Int32, Int32] = command_sender(
    "project list",
    (scope, value) => {
      assert_true(@lander_config.bind(scope.configuration, "fixture"))
      scope.logger.info("Selected {Count} projects", [
        Json::number(value.to_double()),
      ])
      ticks.val = 1.025
      value
    },
  )
  assert_eq(
    sender.send(context, 7),
    7,
    msg=logs
      .events()
      .map(event => event.error.map(error => error.to_string()).unwrap_or(""))
      .join("; "),
  )
  let events = logs.events()
  assert_eq(events.length(), 4)
  assert_true(
    events.all(event => event.category == Some("morphir.cli.project.list")),
  )
  assert_eq(events[1].property("Count"), Some(Json::number(7.0)))
  assert_eq(events[2].property("ExitCode"), Some(Json::number(7.0)))
  assert_true(
    events[3].property("ElapsedMilliseconds") is Some(Number(value, ..)) &&
    value > 24.9 &&
    value < 25.1,
  )
}

///|
async fn assert_middleware_cancellation() -> Unit {
  let calls = Ref(0)
  let failures = Ref(0)
  let mapped = Ref(false)
  let logs = @logging.MemoryLogger::new()
  let context : CommandContext = {
    mode: JSON,
    configuration: @config.from_json({ "fixture": true }, origin="test").framework(),
    logger: logs,
    clock: fn() { 1.0 },
    check_cancelled: fn() raise { raise CommandCancelled },
    stop_requested: fn() { true },
    failed: fn(presentation, error) {
      mapped.val = presentation is Compilation && error is CommandCancelled
      failures.val += 1
      130
    },
    workers: WorkerHosting::none(),
  }
  let sender : @mediator_async.Sender[CommandContext, Unit, Int32] = command_sender(
    "compile",
    (_, _) => {
      calls.val += 1
      0
    },
  )
  assert_eq(sender.send(context, ()), 130)
  assert_eq(calls.val, 0)
  assert_eq(failures.val, 1)
  assert_true(mapped.val)
  assert_eq(logs.events().length(), 3)
  assert_eq(logs.events()[1].level, @logging.Error)
}

///|
test "command middleware retains notebook and legacy failure presentation" {
  assert_true(failure_presentation("notebook export") is Notebook(Export))
  assert_true(failure_presentation("notebook import") is Notebook(Import))
  assert_true(failure_presentation("run") is Legacy)
  assert_true(CommandRequest::decode(parse_cli(["run", "."])) is RunCommand(_))
  assert_true(
    CommandRequest::decode(parse_cli(["notebook", "import", "sheet.dib"]))
    is NotebookImportCommand(_),
  )
}

///|
#cfg(any(target="native", target="js"))
async test "process command middleware scopes timing and preserves the handler result" {
  assert_middleware_timing()
}

///|
#cfg(any(target="native", target="js"))
async test "process command middleware checks cancellation before effects and maps failure once" {
  assert_middleware_cancellation()
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn run_middleware_assertion(work : async () -> Unit) -> Unit raise {
  let variables : Map[String, String] = Map([])
  let host = @lander.cli(
      @lander_core.AppName::parse("middleware-test"),
      [],
      env_vars=variables,
      working_dir=@lander_core.AbsolutePath::root(),
    )
    |> @hosting.build(_ => ())
  let outcome = @hosting.run_embedded(host, _ => work())
  assert_eq(
    outcome.exit_code().to_int(),
    0,
    msg=outcome.failures().map(error => error.to_string()).join("; "),
  )
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
test "embedded command middleware scopes timing and preserves the handler result" {
  run_middleware_assertion(() => assert_middleware_timing())
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
test "embedded command middleware checks cancellation before effects and maps failure once" {
  run_middleware_assertion(() => assert_middleware_cancellation())
}
