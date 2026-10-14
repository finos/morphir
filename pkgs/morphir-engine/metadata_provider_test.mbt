///|
fn scoped_metadata_files(allowed : String) -> Map[String, String] {
  let files = Map::from_array([
    ("morphir.toml", "[workspace]\nmembers=['one','two']"),
  ])
  for root in ["one", "two"] {
    files[root + "/morphir.toml"] = "[project]\nname='" +
      root +
      "'\n[frontend]\nlanguage='ion-text'\n[pipeline]\nbackend='moonbit'\nvalidation='source-only'\n[metadata]\nprovider='shared-local-restore'\nservice='tools/provider'\npolicy='" +
      (if root == allowed { "accepted.json" } else { "denied.json" }) +
      "'\nlock='morphir.lock'\nregistry='registry'\nstate='state'\nassurance='portable'\n[metadata.naming]\nrelease='example.com/morphir/naming@1.0.0'"
    files[root + "/src/main.ion"] = "placeholder"
  }
  files
}

///|
fn scoped_metadata_workspace(
  files : Map[String, String],
) -> @workspace.Workspace raise {
  @workspace.discover({
    files,
    directories: ["", "one", "one/src", "two", "two/src"],
  })
}

///|
fn naming_checkpoint() -> @data.Content raise {
  @data.Registry::new().encode(
    "ion-text",
    @data.IRUnit::new("main", @metadata_fixtures.input(), metadata=[
      {
        node_id: "value:example:main#ready",
        data: @metadata_fixtures.adapter(
          "[" + @metadata_fixtures.row("ready") + "]",
        ),
      },
    ]),
  )
}

///|
test "project metadata binding is frozen per job and restoration stays lazy" {
  let content = naming_checkpoint()
  for allowed in ["one", "two"] {
    let scopes : Array[@engine.ProjectMetadataScope] = []
    let restored : Array[String] = []
    let engine = @engine.Engine::new()
    engine.register_project_metadata_provider(scope => {
      scopes.push(scope)
      guard scope.request is @configuration.SharedLocalRestore(request) else {
        fail("missing request")
      }
      let policy = request.policy.path
      {
        restore_library: Some(fn(predicate) raise {
          restored.push(scope.project_root)
          if policy != "accepted.json" {
            raise @linked_metadata.Invalid(
              "metadata.restore_denied",
              predicate,
              "Denied for " + scope.project_root,
            )
          }
          @metadata_fixtures.provider()
        }),
        load_context: None,
        target_names_interpreter: true,
      }
    })
    let files = scoped_metadata_files(allowed)
    let workspace = scoped_metadata_workspace(files)
    let plan = engine.plan(@engine.Host::memory(files), workspace, {
      ..@engine.Request::new(),
      all: true,
    })
    assert_eq(scopes.length(), 2)
    assert_eq(restored.length(), 0)
    assert_eq(scopes[0].workspace_root, "")
    assert_true(scopes.all(s => s.project_name == s.project_root))
    for scope in scopes {
      guard scope.request is @configuration.SharedLocalRestore(request) else {
        fail("request")
      }
      assert_eq(request.policy.origin, scope.project_root + "/morphir.toml")
    }
    // A caller's later configuration changes do not replace a bound authority.
    for project in workspace.projects {
      if project.document.value is @toml.TomlTable(fields) {
        fields["metadata"] = @toml.TomlTable(Map([]))
      }
    }
    let result = engine.execute_content(plan, fn(_, _) { content })
    assert_false(result.successful())
    assert_eq(restored.length(), 2)
    assert_eq(result.diagnostics.length(), 1)
    let denied = if allowed == "one" { "two" } else { "one" }
    assert_true(result.diagnostics[0].path.has_prefix(denied + "/"))
    assert_true(
      result.diagnostics[0].message.contains("metadata.restore_denied"),
      msg=result.diagnostics[0].message,
    )
    assert_true(
      result.artifacts.any(a => {
        a.path.contains("/" + allowed + "/") &&
        a.content is @data.Text(t) &&
        t.contains("pub fn wanted()")
      }),
    )
    assert_false(result.artifacts.any(a => a.path.contains("/" + denied + "/")))
  }
}

///|
test "metadata binder never restores for plans or units without naming facts" {
  let scopes : Array[@engine.ProjectMetadataScope] = []
  let restored : Array[String] = []
  let engine = @engine.Engine::new()
  engine.register_project_metadata_provider(scope => {
    scopes.push(scope)
    {
      restore_library: Some(fn(predicate) raise {
        restored.push(predicate)
        @metadata_fixtures.provider()
      }),
      load_context: None,
      target_names_interpreter: true,
    }
  })
  let files = scoped_metadata_files("one")
  let workspace = scoped_metadata_workspace(files)
  let host = @engine.Host::memory(files)
  ignore(engine.list_projects(host, workspace))
  assert_eq(scopes.length(), 0)
  assert_eq(restored.length(), 0)
  let plain = @data.Registry::new().encode(
    "ion-text",
    @data.IRUnit::new("main", @metadata_fixtures.input()),
  )
  for _ in 0..<2 {
    let plan = engine.plan(host, workspace, {
      ..@engine.Request::new(),
      all: true,
    })
    assert_eq(restored.length(), 0)
    let report = engine.execute_content(plan, fn(_, _) { plain })
    assert_true(report.successful())
  }
  assert_eq(scopes.length(), 4)
  assert_eq(restored.length(), 0)
}

///|
test "static metadata callers keep their authority and reject an additional binder" {
  for
    capabilities in [
      @metadata_fixtures.capabilities(),
      {
        ..@linked_metadata.Capabilities::unavailable(),
        target_names_interpreter: true,
      },
    ] {
    let engine = @engine.Engine::new(metadata_capabilities=capabilities)
    try {
      engine.register_project_metadata_provider(fn(_) {
        @linked_metadata.Capabilities::unavailable()
      })
      fail("ambiguous static authority accepted")
    } catch {
      @configuration.Invalid(message) =>
        assert_true(message.contains("metadata.ambiguous_authority"))
      other => raise other
    }
  }
  let engine = @engine.Engine::new()
  engine.register_project_metadata_provider(fn(_) {
    @linked_metadata.Capabilities::unavailable()
  })
  try {
    engine.register_project_metadata_provider(fn(_) {
      @metadata_fixtures.capabilities()
    })
    fail("second binder accepted")
  } catch {
    @configuration.Invalid(message) =>
      assert_true(message.contains("metadata.ambiguous_authority"))
    other => raise other
  }
}
