///|
test "command middleware scopes timing and preserves the handler result" {
  let logs = @logging.MemoryLogger::new()
  let ticks = Ref(1.0)
  let context : CommandContext = {
    mode: JSON,
    logger: logs,
    clock: fn() { ticks.val },
    check_cancelled: fn() { () },
    failed: fn(_, _) { -1 },
  }
  let sender : @mediator.Sender[CommandContext, Int32, Int32] = command_sender(
    "project list",
    (scope, value) => {
      scope.logger.info("Selected {Count} projects", [
        Json::number(value.to_double()),
      ])
      ticks.val = 1.025
      value
    },
  )
  assert_eq(sender.send(context, 7), 7)
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
test "command middleware checks cancellation before effects and maps failure once" {
  let calls = Ref(0)
  let failures = Ref(0)
  let mapped = Ref(false)
  let logs = @logging.MemoryLogger::new()
  let context : CommandContext = {
    mode: JSON,
    logger: logs,
    clock: fn() { 1.0 },
    check_cancelled: fn() raise { raise CommandCancelled },
    failed: fn(presentation, error) {
      mapped.val = presentation is Compilation && error is CommandCancelled
      failures.val += 1
      130
    },
  }
  let sender : @mediator.Sender[CommandContext, Unit, Int32] = command_sender(
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
