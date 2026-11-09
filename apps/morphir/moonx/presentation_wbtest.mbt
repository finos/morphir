///|
suberror LauncherFixtureFailure {
  SimulatedMissingNode
}

///|
test "launcher help and startup failures use command-result JSON" {
  assert_true(
    help_document()
    is {
      "profile": String("morphir/command-result"),
      "contractVersion": String("0.1.0"),
      "command": String("moonx"),
      "state": String("succeeded"),
      "exitCode": Number(0, ..),
      "result": { "help": String(_), .. },
      ..
    },
  )
  let stopped = @launcher.LaunchOutcome::new(
    NotStarted(Cancelled(Signal(Interrupt))),
    @launcher.ProcessStatus::from_bits(130U),
    [],
  )
  let document = startup_document(stopped).unwrap()
  assert_true(
    document
    is {
      "state": String("failed"),
      "exitCode": Number(130, ..),
      "error": { "code": String("moonx.cancelled"), .. },
      ..
    },
  )
}

///|
test "started children keep stdout ownership even when they fail" {
  for status in [0U, 1U, 23U, 130U, 143U, 0xc000013aU] {
    let status = @launcher.ProcessStatus::from_bits(status)
    let outcome = @launcher.LaunchOutcome::new(
      Started(Exited(status)),
      status,
      [],
    )
    assert_true(startup_document(outcome) is None)
  }
}

///|
test "missing Node gives an actionable startup failure" {
  let outcome = @launcher.LaunchOutcome::new(
    NotStarted(
      Failed(
        NodeMissing(
          executable=@launcher.Executable::node(),
          cause=SimulatedMissingNode,
        ),
      ),
    ),
    @launcher.ProcessStatus::failure(),
    [],
  )
  assert_true(
    startup_document(outcome).unwrap()
    is {
      "state": String("failed"),
      "exitCode": Number(1, ..),
      "error": {
        "code": String("moonx.node_missing"),
        "message": String(message),
        ..
      },
      ..
    } &&
    message.contains("Node") &&
    message.contains("native"),
  )
}

///|
test "Windows startup reporting retains every selected status bit" {
  let outcome = @launcher.LaunchOutcome::new(
    NotStarted(Cancelled(Signal(Interrupt))),
    @launcher.ProcessStatus::from_bits(0xc000013aU),
    [],
  )
  let document = startup_document(outcome).unwrap()
  assert_true(document is { "exitCode": Number(3221225786, ..), .. })
}
