///|
test "process authority binds without acquiring and missing grants refuse publication" {
  let files = a_metadata_session_workspace(true)
  for root in ["one", "two"] {
    let path = root + "/morphir.toml"
    files[path] += "\n[metadata]\nprovider='shared-local-restore'\nservice='service'\npolicy='policy'\nlock='lock'\nregistry='registry'\nstate='state'\nassurance='portable'\n[metadata.naming]\nrelease='example.com/morphir/naming@1.0.0'"
  }
  let host = @host.Host::new(@host.Mount::memory(files))
  let engine = @engine.Engine::new()
  host.register_process_metadata_provider(engine, None, "/work", "/invocation")
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  let outputs = Map::from_array([("previous.txt", @data.Text("retain"))])
  let result = host.run_content(engine, plan, {
    ..@host.ContentPublisher::memory(outputs),
    begin: fn(_) raise { fail("ungranted metadata reached publication") },
  })
  assert_false(result.successful())
  assert_eq(result.report.diagnostics.length(), 2)
  assert_true(
    result.report.diagnostics.all(d => {
      d.message.contains("metadata.restore_host_grants_required")
    }),
  )
  assert_eq(outputs.length(), 1)
  assert_eq(outputs["previous.txt"], @data.Text("retain"))
}

///|
test "process deadlines validate without resource acquisition" {
  let host = @host.Host::new(@host.Mount::memory(Map([])))
  for timeout in [0, 6000, 600001] {
    let refused = try {
      host.register_process_metadata_provider(
        @engine.Engine::new(),
        None,
        "/work",
        "/invocation",
        timeout~,
      )
      false
    } catch {
      error => @host.error_message(error) == "metadata.restore_invalid_deadline"
    }
    assert_true(refused)
  }
}

///|
test "a disabled CLI provider preserves unavailable diagnostics without acquisition" {
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
  )
  let engine = @engine.Engine::new()
  host.register_process_metadata_provider(engine, None, "/work", "/invocation")
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  let result = host.run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(Map([])),
  )
  assert_false(result.successful())
  assert_eq(result.report.diagnostics.length(), 2)
  assert_true(
    result.report.diagnostics.all(d => {
      d.message.contains("metadata.provider_unavailable")
    }),
  )
  assert_true(
    result.report.diagnostics.all(d => {
      !d.message.contains("metadata.restore_host_grants_required")
    }),
  )
}
