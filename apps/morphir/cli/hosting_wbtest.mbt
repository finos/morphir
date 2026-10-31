///|
priv suberror HostingFixtureFailure

///|
fn hosted_fixture() -> Invocation raise {
  {
    cli: parse_cli(["project", "list", "--json"]),
    mode: JSON,
    environment: Map([]),
    directory: "/",
    root: "/",
    configuration: @config.empty(),
    settings: { level: Off, files: Disabled, },
    cancel_file: "",
    command_started: Ref(false),
    workers: WorkerHosting::none(),
  }
}

///|
#cfg(any(target="native", target="js"))
async test "hosted failure drains diagnostics before the registered telemetry and restores the owner" {
  let events : Array[String] = []
  let invocation = hosted_fixture()
  let outer = @platform.InterruptionScope::install(() => false)
  defer outer.close()
  let previous = active_run.val
  let host = invocation.host(@logging.null_logger(), () => {
    events.push("diagnostics")
  })
  let result = @hosting.run(host, _ => {
    let flush = telemetry_flush(() => events.push("telemetry"))
    flush()
    assert_true(events.is_empty())
    assert_false(@platform.interruption_requested())
    raise HostingFixtureFailure
  })
  assert_eq(result.exit_code().to_int(), 1)
  assert_eq(events, ["diagnostics", "telemetry"])
  assert_true(active_run.val is None && previous is None)
  assert_false(@platform.interruption_requested())
}

///|
#cfg(any(target="native", target="js"))
async test "one host stop state reaches synchronous adapters and retains exit 130" {
  let events : Array[String] = []
  let host = hosted_fixture().host(@logging.null_logger(), () => {
    events.push("diagnostics")
  })
  let result = @hosting.run(host, ctx => {
    ignore(telemetry_flush(() => events.push("telemetry")))
    ctx.lifetime.stop_application(exit_code=@hosting.ExitCode::from_int(130))
    assert_true(@platform.interruption_requested())
  })
  assert_eq(result.exit_code().to_int(), 130)
  assert_eq(events, ["diagnostics", "telemetry"])
}
