///|
fn source_profile(
  id : String,
  run : (@engine.Source, String, () -> Bool) -> @data.IRUnit raise,
) -> @engine.SourceProfile {
  {
    id: @ids.ProfileId::parse(id) catch {
      _ => abort("test profile id: " + id)
    },
    compile: @engine.PerFile(run),
    unit_limits: @data.Limits::default(),
    evidence: @engine.Declared,
    dependencies: { "parser": "1.0" },
    capabilities: {
      summary: "Test source",
      supported: ["Boolean literals"],
      excluded: ["Calls"],
      max_documents: Some(1),
      incremental: false,
      limits: { "bytes": 1024 },
    },
  }
}

///|
fn source_provider(
  id : String,
  profiles : Array[@engine.SourceProfile],
  language~ : String = "rich",
) -> @engine.SourceProvider {
  let parsed = fn(text : String) -> @ids.LanguageId {
    @ids.LanguageId::parse(text) catch {
      _ => abort("test language: " + text)
    }
  }
  {
    id: @ids.ProviderId::parse(id) catch {
      _ => abort("test provider: " + id)
    },
    languages: [
      {
        id: parsed(language),
        extensions: [
          @ids.FileExtension::parse(".model") catch {
            _ => abort("ext")
          },
        ],
        default_profile: profiles[0].id,
        profiles,
      },
    ],
  }
}

///|
fn source_request(
  provider~ : String = "",
  profile~ : String = "",
) -> @engine.Request raise {
  {
    ..@engine.Request::new(),
    overlay: @configuration.parse(
      "[frontend]\n" +
      (if provider == "" { "" } else { "provider='" + provider + "'\n" }) +
      (if profile == "" { "" } else { "profile='" + profile + "'\n" }),
    ),
  }
}

///|
fn provider_plan(
  engine : @engine.Engine,
  request : @engine.Request,
) -> @engine.Plan raise {
  let files = rich_files()
  let base = @engine.Host::memory(files)
  engine.plan(
    {
      ..base,
      read: fn(path) raise {
        if path.has_suffix(".model") {
          fail("Read model during planning")
        }
        (base.read)(path)
      },
    },
    @workspace.discover({ files, directories: ["", "src"], }),
    request,
  )
}

///|
test "source provider selection is lazy and copies mutable claims and callbacks" {
  let engine = @engine.Engine::new()
  let mut seed_calls = 0
  let mut library_calls = 0
  let seed = source_profile("seed", fn(_, id, _) raise {
    seed_calls += 1
    @data.IRUnit::new(id, @fixtures.library())
  })
  let library = source_profile("library", fn(_, id, _) raise {
    library_calls += 1
    @data.IRUnit::new(id, @fixtures.library())
  })
  let provider = source_provider("test/compiler", [seed, library])
  engine.register_source_provider(provider)
  seed.dependencies["parser"] = "mutated"
  library.capabilities.supported[0] = "mutated"
  library.capabilities.limits["bytes"] = 1
  provider.languages.clear()
  let default = provider_plan(engine, @engine.Request::new()).source_frontends()[0]
  assert_eq(default.profile, Some("seed"))
  assert_true(default.default_profile)
  let plan = provider_plan(engine, source_request(profile="library"))
  let descriptor = plan.source_frontends()[0]
  assert_eq(descriptor.language, "rich")
  assert_eq(descriptor.provider, "test/compiler")
  assert_eq(descriptor.available_profiles, ["seed", "library"])
  assert_false(descriptor.default_profile)
  assert_eq(descriptor.dependencies["parser"], "1.0")
  assert_eq(descriptor.capabilities.unwrap().supported, ["Boolean literals"])
  assert_eq(descriptor.capabilities.unwrap().limits["bytes"], 1024)
  descriptor.capabilities.unwrap().supported.clear()
  descriptor.available_profiles.clear()
  descriptor.dependencies.clear()
  assert_eq(
    plan.source_frontends()[0].capabilities.unwrap().supported.length(),
    1,
  )
  engine.register_source_provider(source_provider("another/compiler", [seed]))
  let report = engine.execute_content(plan, fn(_, _) { @data.Text("source") })
  assert_true(report.successful())
  assert_eq(seed_calls, 0)
  assert_eq(library_calls, 1)
}

///|
test "ambiguous providers and unknown or mismatched selections fail before reads" {
  let engine = @engine.Engine::new()
  let profile = source_profile("only", fn(_, id, _) raise {
    @data.IRUnit::new(id, @fixtures.library())
  })
  engine.register_source_provider(source_provider("a/compiler", [profile]))
  engine.register_source_provider(source_provider("b/compiler", [profile]))
  engine.register_source_provider(
    source_provider("other/compiler", [profile], language="other"),
  )
  for
    (request, code) in [
      (@engine.Request::new(), "frontend.ambiguous_provider"),
      (source_request(profile="only"), "frontend.ambiguous_provider"),
      (source_request(provider="missing"), "frontend.unknown_provider"),
      (
        source_request(provider="other/compiler"),
        "frontend.provider_language_mismatch",
      ),
      (
        source_request(provider="a/compiler", profile="missing"),
        "frontend.unknown_profile",
      ),
    ] {
    let rejected = try {
      ignore(provider_plan(engine, request))
      false
    } catch {
      @configuration.Invalid(message) => {
        assert_true(message.has_prefix(code))
        true
      }
      error => raise error
    }
    assert_true(rejected)
  }
  assert_eq(
    provider_plan(engine, source_request(provider="b/compiler")).source_frontends()[0].provider,
    "b/compiler",
  )
}

///|
test "registration validates atomically and legacy providers remain selectable" {
  let engine = @engine.Engine::new()
  let profile = source_profile("only", fn(_, id, _) raise {
    @data.IRUnit::new(id, @fixtures.library())
  })
  let good = source_provider("compiler", [profile])
  for
    bad in [
      { ..good, languages: [], },
      source_provider("compiler", [profile, profile]),
      source_provider("compiler", [
        {
          ..profile,
          capabilities: { ..profile.capabilities, limits: { "bytes": -1 }, },
        },
      ]),
      source_provider("compiler", [
        {
          ..profile,
          capabilities: { ..profile.capabilities, max_documents: Some(0), },
        },
      ]),
      source_provider("compiler", [profile], language="ion-binary"),
      {
        ..good,
        languages: [
          {
            ..good.languages[0],
            default_profile: @ids.ProfileId::parse("missing"),
          },
        ],
      },
    ] {
    assert_true(
      try {
        engine.register_source_provider(bad)
        false
      } catch {
        @configuration.Invalid(_) => true
        error => raise error
      },
    )
  }
  engine.register_source_provider(good)
  engine.register_unit_frontend(
    "rich",
    [".model"],
    fn(_, id, _) raise { @data.IRUnit::new(id, @fixtures.library()) },
    profile=Some("legacy"),
  )
  let legacy = provider_plan(
      engine,
      source_request(provider="rich", profile="legacy"),
    ).source_frontends()[0]
  assert_eq(legacy.provider, "rich")
  assert_true(legacy.capabilities is None)
  assert_eq(legacy.evidence.name(), "declared")
  // The non-raising legacy overwrite API cannot silently shadow a provider ID.
  engine.register_frontend("compiler", [".model"], fn(_) raise {
    @fixtures.library()
  })
  let rejected = try {
    ignore(
      engine.plan(
        @engine.Host::memory(rich_files()),
        @workspace.discover({ files: rich_files(), directories: ["", "src"], }),
        {
          ..@engine.Request::new(),
          overlay: @configuration.parse(
            "[frontend]\nlanguage='compiler'\nprovider='compiler'",
          ),
        },
      ),
    )
    false
  } catch {
    @configuration.Invalid(_) => true
    error => raise error
  }
  assert_true(rejected)
}

///|
test "Scheme profile selection and explicit overlays preserve precedence" {
  let engine = @engine.Engine::new()
  let profile = source_profile("seed", fn(_, id, _) raise {
    @data.IRUnit::new(id, @fixtures.library())
  })
  engine.register_source_provider(
    source_provider("compiler", [
      profile,
      { ..profile, id: @ids.ProfileId::parse("library"), },
    ]),
  )
  let request = {
    ..@engine.Request::new(),
    script: "(pipeline (frontend-provider \"compiler\") (frontend-profile \"library\"))",
  }
  assert_eq(
    provider_plan(engine, request).source_frontends()[0].profile,
    Some("library"),
  )
  let overlay = source_request(profile="seed").overlay
  assert_eq(
    provider_plan(engine, { ..request, overlay, }).source_frontends()[0].profile,
    Some("seed"),
  )
  let files = rich_files()
  files["morphir.toml"] += "\nprofile='seed'" // pipeline key does not become a source selection
  let info = engine.list_projects(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories: ["", "src"], }),
    script=request.script,
  )
  assert_eq(info[0].frontend, Some("rich"))
}

///|
test "one provider can offer languages and mixed projects retain their profiles" {
  let engine = @engine.Engine::new()
  let seed = source_profile("seed", fn(_, id, _) raise {
    @data.IRUnit::new(id, @fixtures.library())
  })
  let provider = source_provider("compiler", [
    seed,
    { ..seed, id: @ids.ProfileId::parse("library"), },
  ])
  engine.register_source_provider({
    ..provider,
    languages: provider.languages +
    [{ ..provider.languages[0], id: @ids.LanguageId::parse("other"), }],
  })
  let files = Map::from_array([
    ("morphir.toml", "[workspace]\nmembers=['a','b']"),
    (
      "a/morphir.toml", "[project]\nname='A'\n[frontend]\nlanguage='rich'\nprofile='library'\n[pipeline]\nbackend='checkpoint'",
    ),
    (
      "b/morphir.toml", "[project]\nname='B'\n[frontend]\nlanguage='other'\n[pipeline]\nbackend='checkpoint'",
    ),
    ("a/src/Main.model", "opaque"),
    ("b/src/Main.model", "opaque"),
  ])
  let workspace = @workspace.discover({
    files,
    directories: ["", "a", "b", "a/src", "b/src"],
  })
  let base = @engine.Host::memory(files)
  let host = {
    ..base,
    read: fn(path) raise {
      if path.has_suffix(".model") {
        fail("Read model")
      }
      (base.read)(path)
    },
  }
  let plan = engine.plan(host, workspace, {
    ..@engine.Request::new(),
    all: true,
  })
  assert_eq(plan.source_frontends().map(f => (f.language, f.profile)), [
    ("rich", Some("library")),
    ("other", Some("seed")),
  ])
  assert_eq(
    engine.execute_content(plan, fn(_, _) { @data.Text("opaque") }).processed,
    2,
  )
}

///|
test "codec inputs reject source profile constraints and configuration rejects empty selections" {
  let engine = @engine.Engine::new()
  for
    (overlay, code) in [
      (
        "[frontend]\nlanguage='ion-binary'\nprofile='seed'", "frontend.source_constraint_on_data_format",
      ),
      ("[frontend]\nprovider=''", "frontend.invalid_provider"),
      ("[frontend]\nprofile=''", "frontend.invalid_profile"),
    ] {
    let request = {
      ..@engine.Request::new(),
      overlay: @configuration.parse(overlay),
    }
    assert_true(
      try {
        ignore(provider_plan(engine, request))
        false
      } catch {
        @configuration.Invalid(message) => {
          assert_true(message.has_prefix(code))
          true
        }
        error => raise error
      },
    )
  }
}

///|
test "a document limit is optional and has no upper bound" {
  let profile = source_profile("only", fn(_, id, _) raise {
    @data.IRUnit::new(id, @fixtures.library())
  })
  for max_documents in [None, Some(65), Some(100000)] {
    @engine.Engine::new().register_source_provider(
      source_provider("compiler", [
        { ..profile, capabilities: { ..profile.capabilities, max_documents, }, },
      ]),
    )
  }
}

///|
test "a project compiler receives typed package and module names" {
  let engine = @engine.Engine::new()
  let mut seen : (String, Array[String]) = ("", [])
  let profile : @engine.SourceProfile = {
    ..source_profile("whole", fn(_, id, _) raise {
      @data.IRUnit::new(id, @fixtures.library())
    }),
    compile: @engine.PerProject(fn(project, id, _) raise {
      seen = (
        project.package_name.to_string(),
        project.exposed_modules.map(m => m.to_string()),
      )
      @data.IRUnit::new(id, @fixtures.library())
    }),
  }
  engine.register_source_provider(source_provider("test/whole", [profile]))
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='My.Pkg'\nexposed_modules=['Api', 'Sub.Util']\n[frontend]\nlanguage='rich'\n[pipeline]\nbackend='checkpoint'",
    ),
    ("src/a.model", "a"),
  ])
  let host = @engine.Host::memory(files)
  let plan = engine.plan(
    host,
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
  )
  let report = engine.execute_content(plan, fn(path, _) raise {
    @data.Text((host.read)(path))
  })
  assert_true(report.successful())
  assert_eq(seen, ("My.Pkg", ["Api", "Sub.Util"]))
}

///|
test "languages lists built-in frontends and providers, sorted, without callbacks" {
  let engine = @engine.Engine::new()
  let run = fn(_ : @engine.Source, id : String, _ : () -> Bool) raise {
    @data.IRUnit::new(id, @fixtures.library())
  }
  engine
  ..register_source_provider(
    source_provider("b/compiler", [source_profile("seed", run)]),
  )
  .register_source_provider(
    source_provider("a/compiler", [source_profile("seed", run)]),
  )
  let offers = engine.languages()
  assert_eq(offers.map(o => (o.language.to_string(), o.provider.to_string())), [
    ("rich", "a/compiler"),
    ("rich", "b/compiler"),
    ("scheme", "scheme"),
  ])
  let rich = offers[0]
  assert_eq(rich.extensions.map(e => e.to_string()), [".model"])
  assert_eq(rich.default_profile.map(p => p.to_string()), Some("seed"))
  assert_eq(rich.profiles.map(p => (p.id.to_string(), p.compile)), [
    ("seed", @engine.EachFile),
  ])
  assert_eq(rich.profiles[0].unit_limits, Some(@data.Limits::default()))
  assert_true(rich.profiles[0].capabilities is Some(_))
  let scheme = offers[2]
  assert_eq(scheme.extensions.map(e => e.to_string()), [".scm", ".ss"])
  assert_eq(scheme.default_profile, None)
  assert_eq(scheme.profiles.length(), 0)
}

///|
test "languages describes a unit frontend's profile and leaves out ir-json" {
  let engine = @engine.Engine::new()
  engine.register_unit_frontend(
    "rich",
    [".model"],
    fn(_, id, _) raise { @data.IRUnit::new(id, @fixtures.library()) },
    profile=Some("legacy"),
  )
  let offers = engine.languages()
  assert_false(offers.any(o => o.language.to_string() == "ir-json"))
  let rich = offers.filter(o => o.language.to_string() == "rich")[0]
  assert_eq(rich.provider.to_string(), "rich")
  assert_eq(rich.default_profile.map(p => p.to_string()), Some("legacy"))
  assert_eq(rich.profiles[0].compile, @engine.EachFile)
  assert_true(rich.profiles[0].capabilities is None)
}

///|
test "languages leaves out a frontend whose name or extension is not a valid id" {
  let engine = @engine.Engine::new()
  let never = fn(_ : @engine.Source) raise { fail("not compiled") }
  engine
  ..register_frontend("Bad Name", [".x"], never)
  .register_frontend("okay", ["noperiod"], never)
  let names = engine.languages().map(o => o.language.to_string())
  assert_false(names.contains("Bad Name"))
  assert_false(names.contains("okay"))
  assert_true(names.contains("scheme"))
}

///|
test "languages sorts by language id text, then provider id text, alphabetically" {
  let engine = @engine.Engine::new()
  let run = fn(_ : @engine.Source, id : String, _ : () -> Bool) raise {
    @data.IRUnit::new(id, @fixtures.library())
  }
  for name in ["zz", "abc"] {
    engine.register_unit_frontend(name, ["." + name], run)
  }
  engine
  ..register_source_provider(
    source_provider("bb/c", [source_profile("seed", run)]),
  )
  .register_source_provider(
    source_provider("a/compiler", [source_profile("seed", run)]),
  )
  assert_eq(
    engine
    .languages()
    .map(o => (o.language.to_string(), o.provider.to_string())),
    [
      ("abc", "abc"),
      ("rich", "a/compiler"),
      ("rich", "bb/c"),
      ("scheme", "scheme"),
      ("zz", "zz"),
    ],
  )
}
