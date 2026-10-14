///|
test "one project's denied metadata provider prevents workspace publication" {
  let unit = @data.IRUnit::new("main", @metadata_fixtures.input(), metadata=[
    {
      node_id: "value:example:main#ready",
      data: @metadata_fixtures.adapter(
        "[" + @metadata_fixtures.row("ready") + "]",
      ),
    },
  ])
  let source = match @data.Registry::new().encode("ion-text", unit) {
    @data.Text(text) => text
    _ => fail("text checkpoint")
  }
  let files = Map::from_array([
    ("morphir.toml", "[workspace]\nmembers=['one','two']"),
  ])
  for root in ["one", "two"] {
    files[root + "/morphir.toml"] = "[project]\nname='" +
      root +
      "'\n[frontend]\nlanguage='ion-text'\n[pipeline]\nbackend='moonbit'\nvalidation='source-only'"
    files[root + "/src/main.ion"] = source
  }
  let mount = @host.Mount::memory(files)
  let host = @host.Host::new(mount)
  let snapshot = host.snapshot()
  let workspace = @workspace.discover(snapshot.tree)
  let engine = @engine.Engine::new()
  engine.register_project_metadata_provider(scope => {
    if scope.project_root == "one" {
      @metadata_fixtures.capabilities()
    } else {
      @linked_metadata.Capabilities::unavailable()
    }
  })
  let plan = engine.plan(snapshot.engine_host(), workspace, {
    ..@engine.Request::new(),
    all: true,
  })
  let outputs = Map::from_array([
    (".morphir/out/one/compile.dest/previous.txt", @data.Text("retain one")),
    (".morphir/out/two/compile.dest/previous.txt", @data.Text("retain two")),
  ])
  let result = host.run_content(
    engine,
    plan,
    @host.ContentPublisher::memory(outputs),
  )
  assert_false(result.successful())
  assert_eq(result.committed.length(), 0)
  assert_eq(outputs.length(), 2)
  assert_eq(
    outputs[".morphir/out/one/compile.dest/previous.txt"],
    @data.Text("retain one"),
  )
  assert_eq(
    outputs[".morphir/out/two/compile.dest/previous.txt"],
    @data.Text("retain two"),
  )
  assert_true(
    result.report.diagnostics.any(d => {
      d.path.has_prefix("two/") &&
      d.message.contains("metadata.provider_unavailable")
    }),
  )
}
