///|
fn generation_files(
  backend : String,
  language~ : String = "ir-json",
) -> Map[String, String] raise {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Pricing'\n[frontend]\nlanguage='" +
      language +
      "'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'",
    ),
    ("src/main.json", @ir_json.write(@fixtures.library())),
  ])
}

///|
fn generation_plan(
  engine : @engine.Engine,
  files : Map[String, String],
) -> @engine.Plan raise {
  engine.plan(
    @engine.Host::memory(files),
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
  )
}

///|
test "MoonBit generation isolates each complete library and accepts JSON Ion inputs" {
  let registry = @data.Registry::new()
  let engine = @engine.Engine::new()
  for language in ["ir-json", "ion-text", "ion-binary"] {
    let files = generation_files("moonbit", language~)
    files.remove("src/main.json")
    let suffix = if language == "ir-json" {
      ".json"
    } else if language == "ion-text" {
      ".ion"
    } else {
      ".ionb"
    }
    files["src/main" + suffix] = "placeholder"
    let unit = @data.IRUnit::new("main", @fixtures.pricing())
    let content = registry.encode(
      if language == "ir-json" {
        "morphir-json"
      } else {
        language
      },
      unit,
    )
    let plan = generation_plan(engine, files)
    assert_true(plan.requires_byte_write())
    let report = engine.execute_content(plan, fn(_, _) { content })
    if !report.successful() {
      fail(report.diagnostics[0].message)
    }
    assert_eq(report.processed, 1)
    assert_eq(report.artifacts.length(), 4)
    assert_eq(report.projects.length(), 1)
    assert_eq(report.projects[0].root, ".morphir/out/compile.dest/main")
    assert_eq(report.projects[0].policy, @engine.SourceOnly)
    assert_true(
      report.artifacts.any(a => {
        a.path.has_suffix("/symbols.10n") && a.content is @data.Binary(_)
      }),
    )
  }
}

///|
test "generic generation validates membership and paths without MoonBit filenames" {
  let files = generation_files("other")
  let batches : Array[(@engine.GenerationBatch, Bool)] = [
    (
      {
        warnings: [],
        structured_warnings: [],
        files: [
          {
            path: "component/spec.txt",
            content: @data.Text("library"),
            format: "other-source",
          },
        ],
        projects: [
          {
            id: "other",
            root: "component",
            members: ["spec.txt"],
            dependencies: [],
            build_contract: "other-library-v1",
          },
        ],
      },
      true,
    ),
    (
      {
        warnings: [],
        structured_warnings: [],
        files: [
          { path: "../escape", content: @data.Text("bad"), format: "other", },
        ],
        projects: [
          {
            id: "other",
            root: "",
            members: ["../escape"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        structured_warnings: [],
        files: [
          { path: "one", content: @data.Text("bad"), format: "other", },
          { path: "ONE", content: @data.Text("bad"), format: "other", },
        ],
        projects: [
          {
            id: "other",
            root: "",
            members: ["one", "ONE"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        structured_warnings: [],
        files: [
          { path: "one", content: @data.Text("bad"), format: "other", },
          { path: "one/two", content: @data.Text("bad"), format: "other", },
        ],
        projects: [
          {
            id: "other",
            root: "",
            members: ["one", "one/two"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        structured_warnings: [],
        files: [{ path: "one", content: @data.Text("bad"), format: "other", }],
        projects: [
          {
            id: "other",
            root: "",
            members: ["missing"],
            dependencies: [],
            build_contract: "other",
          },
        ],
      },
      false,
    ),
    (
      {
        warnings: [],
        structured_warnings: [],
        files: [{ path: "one", content: @data.Text("bad"), format: "other", }],
        projects: [],
      },
      false,
    ),
  ]
  for (batch, valid) in batches {
    let engine = @engine.Engine::new()
    engine.register_generation_backend("other", {
      generate: fn(_, _, _) { batch },
      write_bytes: false,
      validate_options: fn(_) { () },
      targets: [],
    })
    let plan = generation_plan(engine, files)
    let report = engine.execute_content(plan, fn(_, _) {
      @data.Text(files["src/main.json"])
    })
    if valid && !report.successful() {
      fail(report.diagnostics[0].message)
    }
    assert_eq(report.successful(), valid)
    if !valid {
      assert_true(report.artifacts.is_empty())
      assert_true(report.projects.is_empty())
    }
  }
}

///|
test "input project roots reject case and ancestor collisions during planning" {
  for
    paths in [
      ["src/one.json", "src/ONE.json"],
      ["src/one.json", "src/one/two.json"],
    ] {
    let files = generation_files("moonbit")
    files.remove("src/main.json")
    for path in paths {
      files[path] = "ignored"
    }
    assert_true(
      try {
        ignore(generation_plan(@engine.Engine::new(), files))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "MoonBit recovery warnings are structured and strict naming stops publication" {
  let files = generation_files("moonbit")
  files["src/main.json"] = @ir_json.write(@fixtures.naming_library())
  let engine = @engine.Engine::new()
  let report = engine.execute_content(generation_plan(engine, files), fn(
    path,
    _,
  ) {
    @data.Text(files[path])
  })
  assert_true(report.successful())
  assert_eq(report.projects.length(), 1)
  assert_true(
    report.warnings.any(w => {
      w.details is Some(d) && d.code == "moonbit_backend.name_collision"
    }),
  )
  assert_true(
    report.warnings.all(w => w.details is Some(_) && w.stage == "backend"),
  )
  let warning_keys = report.warnings.map(w => w.details.unwrap().key())
  assert_eq(
    Map::from_array(warning_keys.map(k => (k, true))).length(),
    warning_keys.length(),
  )
  files["morphir.toml"] = files["morphir.toml"] + "\nstrict_naming=true\n"
  let strict = engine.execute_content(generation_plan(engine, files), fn(
    path,
    _,
  ) {
    @data.Text(files[path])
  })
  assert_false(strict.successful())
  assert_eq(strict.artifacts.length(), 0)
  assert_eq(strict.projects.length(), 0)
  assert_true(strict.diagnostics[0].message.contains("naming.strict"))
}

///|
test "MoonBit naming option is checked and legacy mode retains existing symbol spelling" {
  let files = generation_files("moonbit")
  let engine = @engine.Engine::new()
  files["morphir.toml"] = files["morphir.toml"] +
    "\n[backends.moonbit]\nnaming='legacy-hex'\n"
  let legacy = engine.execute_content(generation_plan(engine, files), fn(
    path,
    _,
  ) {
    @data.Text(files[path])
  })
  assert_true(legacy.successful())
  assert_eq(legacy.warnings.length(), 0)
  assert_true(
    legacy.artifacts.any(a => {
      a.path.has_suffix("library.mbt") &&
      a.content is @data.Text(t) &&
      t.contains("pub fn v_")
    }),
  )
  for value in ["'unknown'", "true", "1"] {
    files["morphir.toml"] = generation_files("moonbit")["morphir.toml"] +
      "\n[backends.moonbit]\nnaming=" +
      value +
      "\n"
    let failed = try {
      ignore(generation_plan(engine, files))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "declared target names survive both Ion checkpoints and engine consumes explicit host capabilities" {
  let registry = @data.Registry::new()
  let unit = @data.IRUnit::new("main", @metadata_fixtures.input(), metadata=[
    {
      node_id: "value:example:main#ready",
      data: @metadata_fixtures.adapter(
        "[" + @metadata_fixtures.row("ready") + "]",
      ),
    },
  ])
  let original = @ion_text.write_ion(unit.metadata[0].data)
  for language in ["ion-text", "ion-binary"] {
    let content = registry.encode(language, unit)
    let restored = registry.decode(language, { unit_id: "main", content, })
    assert_eq(@ion_text.write_ion(restored.metadata[0].data), original)
    let files = generation_files("moonbit", language~)
    files.remove("src/main.json")
    files["src/main" + (if language == "ion-text" { ".ion" } else { ".ionb" })] = "placeholder"
    let engine = @engine.Engine::new(
      metadata_capabilities=@metadata_fixtures.capabilities(),
    )
    let report = engine.execute_content(generation_plan(engine, files), fn(
      _,
      _,
    ) {
      content
    })
    if !report.successful() {
      fail(report.diagnostics[0].message)
    }
    assert_true(
      report.artifacts.any(a => {
        a.path.has_suffix("library.mbt") &&
        a.content is @data.Text(t) &&
        t.contains("pub fn wanted()")
      }),
    )
    let strict_files = files.copy()
    strict_files["morphir.toml"] = files["morphir.toml"] +
      "\nstrict_naming=true\n"
    let strict = engine.execute_content(generation_plan(engine, strict_files), fn(
      _,
      _,
    ) {
      content
    })
    assert_false(strict.successful())
    assert_eq(strict.artifacts.length(), 0)
    let unavailable = @engine.Engine::new()
    let refused = unavailable.execute_content(
      generation_plan(unavailable, files),
      fn(_, _) { content },
    )
    assert_false(refused.successful())
    assert_true(
      refused.diagnostics[0].message.contains("metadata.provider_unavailable"),
    )
    assert_eq(refused.artifacts.length(), 0)
    assert_eq(refused.projects.length(), 0)
  }
  try {
    ignore(registry.encode("morphir-json", unit))
    fail("metadata loss")
  } catch {
    @data.Invalid(code, _) => assert_eq(code, "data.lossy_conversion")
    other => raise other
  }
}
