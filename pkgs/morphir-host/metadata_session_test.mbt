///|
fn a_metadata_session_workspace(
  named : Bool,
  context~ : String? = None,
) -> Map[String, String] raise {
  let unit = @data.IRUnit::new(
    "main",
    @metadata_fixtures.input(),
    metadata=if named {
      [
        {
          node_id: "value:example:main#ready",
          data: match context {
            None =>
              @metadata_fixtures.adapter(
                "[" + @metadata_fixtures.row("ready") + "]",
              )
            Some(reference) =>
              @metadata_fixtures.adapter(
                "[" + @metadata_fixtures.row("ready") + "]",
                context=reference,
              )
          },
        },
      ]
    } else {
      []
    },
  )
  guard @data.Registry::new().encode("ion-text", unit) is @data.Text(source) else {
    fail("text checkpoint")
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
  files
}

///|
test "host metadata sessions are lazy, scoped and disposed before publication" {
  let events : Array[String] = []
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
  )
  let engine = @engine.Engine::new()
  host.register_project_metadata_provider(engine, scope => {
    events.push("acquire " + scope.project_root)
    {
      capabilities: @metadata_fixtures.capabilities(),
      dispose: fn() { events.push("dispose " + scope.project_root) },
    }
  })
  let snapshot = host.snapshot()
  ignore(
    engine.plan(snapshot.engine_host(), @workspace.discover(snapshot.tree), {
      ..@engine.Request::new(),
      all: true,
    }),
  )
  assert_eq(events.length(), 0)
  let outputs : Map[String, @data.Content] = Map([])
  let memory = @host.ContentPublisher::memory(outputs)
  let publisher : @host.ContentPublisher = {
    ..memory,
    begin: fn(paths) raise {
      assert_eq(events.last(), Some("dispose one"))
      events.push("begin")
      (memory.begin)(paths)
    },
  }
  for _ in 0..<2 {
    let fresh = host.snapshot()
    let next_plan = engine.plan(
      fresh.engine_host(),
      @workspace.discover(fresh.tree),
      { ..@engine.Request::new(), all: true, },
    )
    assert_true(host.run_content(engine, next_plan, publisher).successful())
  }
  assert_eq(events, [
    "acquire one", "acquire two", "dispose two", "dispose one", "begin", "acquire one",
    "acquire two", "dispose two", "dispose one", "begin",
  ])
}

///|
test "host metadata sessions stay unused without naming facts" {
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(false)),
  )
  let engine = @engine.Engine::new()
  host.register_project_metadata_provider(engine, fn(_) raise {
    fail("unused provider acquired")
  })
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  assert_true(
    host
    .run_content(engine, plan, @host.ContentPublisher::memory(Map([])))
    .successful(),
  )
}

///|
test "cleanup failure attempts all sessions and blocks output replacement" {
  let events : Array[String] = []
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
  )
  let engine = @engine.Engine::new()
  let mut fail_cleanup = true
  host.register_project_metadata_provider(engine, scope => {
    events.push("acquire " + scope.project_root)
    {
      capabilities: @metadata_fixtures.capabilities(),
      dispose: fn() raise {
        events.push("dispose " + scope.project_root)
        if fail_cleanup {
          raise @linked_metadata.Invalid(
            "metadata.test_cleanup",
            scope.project_root,
            "retained test session",
          )
        }
      },
    }
  })
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  let outputs = Map::from_array([("previous.txt", @data.Text("retain"))])
  let memory = @host.ContentPublisher::memory(outputs)
  let publisher : @host.ContentPublisher = {
    ..memory,
    begin: fn(_) raise { fail("publication began before cleanup succeeded") },
  }
  let result = host.run_content(engine, plan, publisher)
  assert_false(result.successful())
  assert_true(
    result.publication_error
    .unwrap()
    .contains("metadata.restore_cleanup_failed"),
  )
  assert_eq(events, ["acquire one", "acquire two", "dispose two", "dispose one"])
  assert_eq(outputs.length(), 1)
  assert_eq(outputs["previous.txt"], @data.Text("retain"))
  try {
    ignore(host.run_content(engine, plan, publisher))
    fail("failed owner reused")
  } catch {
    error =>
      assert_true(
        @host.error_message(error).contains("metadata.restore_cleanup_failed"),
      )
  }
  // Two consecutive failed retries must keep the same LIFO order.
  for _ in 0..<2 {
    let before = events.length()
    try {
      host.dispose_metadata_sessions()
      fail("cleanup unexpectedly succeeded")
    } catch {
      error =>
        assert_true(
          @host.error_message(error).contains("metadata.restore_cleanup_failed"),
        )
    }
    assert_eq(events[before:].to_owned(), ["dispose two", "dispose one"])
  }
  fail_cleanup = false
  let before = events.length()
  host.dispose_metadata_sessions()
  assert_eq(events[before:].to_owned(), ["dispose two", "dispose one"])
  let fresh = host.snapshot()
  let next_plan = engine.plan(
    fresh.engine_host(),
    @workspace.discover(fresh.tree),
    { ..@engine.Request::new(), all: true, },
  )
  assert_true(host.run_content(engine, next_plan, memory).successful())
}

///|
test "metadata admission failure still disposes its acquired session" {
  let events : Array[String] = []
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
  )
  let engine = @engine.Engine::new()
  host.register_project_metadata_provider(engine, scope => {
    capabilities: {
      ..@metadata_fixtures.capabilities(),
      restore_library: Some(fn(predicate) raise {
        raise @linked_metadata.Invalid(
          "metadata.test_denied", predicate, "test refusal",
        )
      }),
    },
    dispose: fn() raise {
      events.push(scope.project_root)
      raise @linked_metadata.Invalid(
        "metadata.test_cleanup",
        scope.project_root,
        "cleanup also failed",
      )
    },
  })
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  let result = host.run_content(engine, plan, {
    ..@host.ContentPublisher::memory(Map([])),
    begin: fn(_) raise { fail("failed generation published") },
  })
  assert_false(result.successful())
  assert_eq(events, ["two", "one"])
  assert_true(
    result.publication_error
    .unwrap()
    .contains("metadata.restore_cleanup_failed"),
  )
  assert_eq(result.report.diagnostics.length(), 2)
  assert_true(
    result.report.diagnostics.all(d => {
      d.message.contains("metadata.test_denied")
    }),
  )
}

///|
test "cancellation after restoration disposes before refusing publication" {
  let events : Array[String] = []
  let mut cancelled = false
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
    cancelled=fn() { cancelled },
  )
  let engine = @engine.Engine::new()
  host.register_project_metadata_provider(engine, scope => {
    events.push("acquire " + scope.project_root)
    {
      capabilities: {
        ..@metadata_fixtures.capabilities(),
        restore_library: Some(fn(_) raise {
          cancelled = true
          @metadata_fixtures.provider()
        }),
      },
      dispose: fn() { events.push("dispose " + scope.project_root) },
    }
  })
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  let result = host.run_content(engine, plan, {
    ..@host.ContentPublisher::memory(Map([])),
    begin: fn(_) raise { fail("cancelled operation published") },
  })
  assert_false(result.successful())
  assert_true(result.cancelled)
  assert_eq(result.committed.length(), 0)
  assert_eq(events, ["acquire one", "dispose one"])
}

///|
test "direct engine execution cannot acquire a host-owned metadata session" {
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
  )
  let engine = @engine.Engine::new()
  host.register_project_metadata_provider(engine, fn(_) raise {
    fail("capability used outside its host")
  })
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  let report = engine.execute_content(plan, fn(path, _) raise {
    @data.Text((host.input.read)(path))
  })
  assert_false(report.successful())
  assert_eq(report.diagnostics.length(), 2)
  assert_true(
    report.diagnostics.all(d => {
      d.message.contains("metadata.restore_session_required")
    }),
  )
}

///|
test "context acquisition and restoration share only their project's session" {
  let bytes = @utf8.encode(
    "{\"@context\":{\"targetNames\":{\"@id\":\"" +
    @linked_metadata.TARGET_NAMES_PREDICATE +
    "\",\"@type\":\"@json\"}}}",
  )
  let digest = @identity.sha256(bytes)
  let reference = "morphir://context/sha256/" + digest
  let events : Array[String] = []
  let host = @host.Host::new(
    @host.Mount::memory(
      a_metadata_session_workspace(true, context=Some("\"" + reference + "\"")),
    ),
  )
  let engine = @engine.Engine::new()
  host.register_project_metadata_provider(engine, scope => {
    events.push("acquire " + scope.project_root)
    {
      capabilities: {
        ..@metadata_fixtures.capabilities(),
        restore_library: Some(fn(_) raise {
          events.push("restore " + scope.project_root)
          @metadata_fixtures.provider()
        }),
        load_context: Some(fn(url, base) raise {
          assert_eq(url, reference)
          assert_eq(base, "")
          events.push("context " + scope.project_root)
          { url, bytes, sha256: digest, }
        }),
      },
      dispose: fn() { events.push("dispose " + scope.project_root) },
    }
  })
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
  assert_true(
    result.successful(),
    msg=result.report.diagnostics.map(d => d.message).join("; ") +
      result.publication_error.unwrap_or(""),
  )
  assert_eq(events, [
    "acquire one", "context one", "restore one", "acquire two", "context two", "restore two",
    "dispose two", "dispose one",
  ])
}

///|
test "session acquisition failures keep a metadata diagnostic and allow a fresh run" {
  let mut denied = true
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
  )
  let engine = @engine.Engine::new()
  host.register_project_metadata_provider(engine, fn(_) raise {
    if denied {
      raise @config.Invalid("Select an existing service executable")
    }
    { capabilities: @metadata_fixtures.capabilities(), dispose: fn() { () }, }
  })
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
      d.message.contains("metadata.restore_acquisition_failed") &&
      d.message.contains("Select an existing service executable")
    }),
  )
  denied = false
  let fresh = host.snapshot()
  let next_plan = engine.plan(
    fresh.engine_host(),
    @workspace.discover(fresh.tree),
    { ..@engine.Request::new(), all: true, },
  )
  assert_true(
    host
    .run_content(engine, next_plan, @host.ContentPublisher::memory(Map([])))
    .successful(),
  )
}
