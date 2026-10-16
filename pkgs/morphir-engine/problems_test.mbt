///|
fn location(line : Int32) -> @ir.SourceLocation {
  { start_line: line, start_column: 1, end_line: line, end_column: 6, }
}

///|
test "a project frontend rejection keeps each problem's code, path and range" {
  let engine = project_engine(
    project_profile(fn(_, _, _) raise {
      raise @engine.RejectedSources([
        {
          code: "x.first",
          detail: "first",
          path: "Api.model",
          location: Some(location(2)),
        },
        {
          code: "x.second",
          detail: "second",
          path: "Nested/Util.model",
          location: None,
        },
      ])
    }),
  )
  let files = project_files()
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
  )
  @expect.expect_all(s => {
    let diagnostics = s.expect(report.diagnostics, label="diagnostics")
    diagnostics.to_have_length(2)
    let first = diagnostics.first()
    first.get("path", d => d.path).to_equal("src/Api.model")
    first.get("code", d => d.code()).to_equal(Some("x.first"))
    first
    .get("start line", d => d.location().map(l => l.start_line))
    .to_equal(Some(2))
    first.to_satisfy(
      d => {
        d.problem is Some(Source({ detail, .. })) && detail.has_prefix("first")
      },
      description="a source problem whose detail starts with first",
    )
    let second = diagnostics.element(1)
    second.get("path", d => d.path).to_equal("src/Nested/Util.model")
    second.get("location", d => d.location()).to_be_none()
  })
}

///|
fn rich_report(
  compile : (@engine.Source, String, () -> Bool) -> @data.IRUnit raise,
) -> @engine.ContentReport raise {
  let engine = @engine.Engine::new()
  engine.register_unit_frontend("rich", [".model"], compile)
  let files = rich_files()
  engine.execute_content(rich_plan(engine, files), fn(path, _) {
    @data.Text(files[path])
  })
}

///|
test "a per-file rejection becomes a source problem of that file" {
  let report = rich_report(fn(_, _, _) raise {
    raise @engine.Rejected("x.bad", "bad input", Some(location(3)))
  })
  @expect.expect_all(s => {
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").single()
    diagnostic.get("path", d => d.path).to_equal("src/Main.model")
    diagnostic.get("code", d => d.code()).to_equal(Some("x.bad"))
    diagnostic
    .get("start line", d => d.location().map(l => l.start_line))
    .to_equal(Some(3))
    diagnostic.to_satisfy(
      d => d.problem is Some(Source({ path: "Main.model", .. })),
      description="a source problem of Main.model",
    )
    diagnostic.get("message", d => d.message).to_start_with("x.bad: bad input")
  })
}

///|
test "a diagnostic without a known cause has no problem" {
  let report = rich_report(fn(_, _, _) raise { fail("plain failure") })
  @expect.expect_all(s => {
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").single()
    diagnostic.to_satisfy(d => d.problem is None, description="no problem")
    diagnostic.get("code", d => d.code()).to_be_none()
  })
}

///|
/// Property: a project rejection with any list of problems gives one diagnostic per problem, in order, each with
/// that problem's code, file and range.
test "every rejected problem becomes one diagnostic, in order" {
  @expect.for_all(
    (shape : Array[(UInt32, Bool)]) => {
      // Each element is one problem: which file (of two), and whether it has a range.
      let problems : Array[@engine.SourceProblem] = shape.mapi((i, item) => {
        let (file, ranged) = item
        {
          code: "x.p" + i.to_string(),
          detail: "problem " + i.to_string(),
          path: if file % 2 == 0 {
            "Api.model"
          } else {
            "Nested/Util.model"
          },
          location: if ranged {
            Some(location(i + 1))
          } else {
            None
          },
        }
      })
      guard !problems.is_empty() else { return }
      let engine = project_engine(
        project_profile(fn(_, _, _) raise {
          raise @engine.RejectedSources(problems)
        }),
      )
      let files = project_files()
      let report = engine.execute_content(
        project_plan(engine, files),
        project_read(files),
      )
      @expect.expect(
        report.diagnostics.map(d => {
          (d.code(), d.path, d.location().map(l => l.start_line))
        }),
      ).to_equal(
        problems.map(p => {
          (Some(p.code), "src/" + p.path, p.location.map(l => l.start_line))
        }),
      )
    },
    count=25,
  )
}

///|
test "on_unit gets the compiled unit of each source before generation" {
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      {
        ..@data.IRUnit::new(id, @fixtures.pricing()),
        metadata: [
          {
            node_id: "value:pricing:scalars#rate/body",
            data: @ion.IonValue::string("hint"),
          },
        ],
      }
    }),
  )
  let files = project_files()
  let seen : Array[@engine.CompiledUnit] = []
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
    on_unit=compiled => seen.push(compiled),
  )
  @expect.expect_all(s => {
    s
    .expect(report.diagnostics.map(d => d.message), label="diagnostics")
    .to_be_empty()
    let unit = s.expect(seen, label="units").single()
    unit.get("source", c => c.source).to_equal("src")
    unit.get("metadata", c => c.unit.metadata.length()).to_equal(1)
  })
}

///|
test "on_unit is not called for a source that the frontend rejects" {
  let engine = project_engine(
    project_profile(fn(_, _, _) raise {
      raise @engine.Rejected("x.bad", "bad", None)
    }),
  )
  let files = project_files()
  let seen : Array[String] = []
  ignore(
    engine.execute_content(project_plan(engine, files), project_read(files), on_unit=c => {
      seen.push(c.source)
    }),
  )
  @expect.expect(seen, label="units").to_be_empty()
}

///|
test "on_unit gets a plain unit for a plain frontend and backend" {
  let engine = @engine.Engine::new()
  let files = generation_files("scheme", language="ir-json")
  let seen : Array[@engine.CompiledUnit] = []
  let report = engine.execute_content(
    generation_plan(engine, files),
    fn(path, _) { @data.Text(files[path]) },
    on_unit=c => seen.push(c),
  )
  @expect.expect_all(s => {
    s
    .expect(report.diagnostics.map(d => d.message), label="diagnostics")
    .to_be_empty()
    let unit = s.expect(seen, label="units").single()
    unit.get("source", c => c.source).to_equal("src/main.json")
    unit.get("metadata", c => c.unit.metadata.length()).to_equal(0)
  })
}

///|
fn scheme_files(backend : String, source : String) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='user'\n[frontend]\nlanguage='scheme'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'",
    ),
    ("src/main.scm", source),
  ])
}

///|
fn run_scheme(
  backend : String,
  source : String,
) -> (@engine.ContentReport, Array[@engine.CompiledUnit]) raise {
  let engine = @engine.Engine::new()
  let files = scheme_files(backend, source)
  let seen : Array[@engine.CompiledUnit] = []
  let report = engine.execute_content(
    generation_plan(engine, files),
    fn(path, _) { @data.Text(files[path]) },
    on_unit=c => seen.push(c),
  )
  (report, seen)
}

///|
fn generation_problem(d : @engine.Diagnostic) -> @engine.GenerationProblem? {
  match d.problem {
    Some(Generation(problem)) => Some(problem)
    _ => None
  }
}

///|
test "an Elm generation refusal gives a generation problem and keeps the unit" {
  let (report, seen) = run_scheme("elm", "18446744073709551616")
  @expect.expect_all(s => {
    s.expect(seen.length(), label="units").to_equal(1)
    s.expect(report.artifacts.length(), label="artifacts").to_equal(0)
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").first()
    diagnostic.get("stage", d => d.stage).to_equal("backend")
    diagnostic.get("path", d => d.path).to_equal("src/main.scm")
    diagnostic.get("code", d => d.code()).to_equal(Some("elm.int_literal"))
    diagnostic
    .get("message", d => d.message)
    .to_start_with("elm.int_literal at ")
    diagnostic
    .get("node path", d => {
      generation_problem(d).map(p => p.node_path).unwrap_or("")
    })
    .to_start_with("user:main#main")
  })
}

///|
test "a MoonBit generation refusal gives a generation problem" {
  let (report, _) = run_scheme("moonbit", "(lambda (x) x)")
  @expect.expect_all(s => {
    let diagnostic = s.expect(report.diagnostics, label="diagnostics").first()
    diagnostic.get("stage", d => d.stage).to_equal("backend")
    diagnostic
    .get("code", d => d.code().unwrap_or(""))
    .to_start_with("moonbit.")
    diagnostic.to_satisfy(
      d => d.message.has_prefix(d.code().unwrap_or("?") + " at "),
      description="a message that starts with its code and node",
    )
  })
}

///|
/// Up to `count` node ids that the library fixture owns, for metadata that passes validation.
fn owned_nodes(id : String, count : Int32) -> Array[String] raise {
  @identities.nodes(id, @fixtures.library())[:count].to_owned()
}

///|
/// A plain backend that accepts rich units and keeps only their IR: Plan B's behaviour, for the warning.
fn with_plain_backend(engine : @engine.Engine) -> @engine.Engine {
  engine.register_backend("plain", ".scm", @backend.emit_file, rich_units=true)
  engine
}

///|
/// The `metadata` and `source_provenance` lists of a Scheme symbols sidecar.
fn sidecar_lists(
  content : @data.Content,
) -> (Array[@ion.IonValue], Array[@ion.IonValue]) raise {
  guard content is @data.Binary(bytes) else {
    fail("Expected a binary sidecar")
  }
  guard @ion_binary.read_binary_value(bytes[:]).kind() is @ion.Struct(fields) else {
    fail("Expected a symbols record")
  }
  let mut metadata = []
  let mut provenance = []
  for field in fields {
    match (field.name().text(), field.value().kind()) {
      (Some("metadata"), @ion.List(items)) => metadata = items
      (Some("source_provenance"), @ion.List(items)) => provenance = items
      _ => ()
    }
  }
  (metadata, provenance)
}

///|
test "the scheme backend keeps a rich project unit's metadata in a sidecar" {
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      {
        ..@data.IRUnit::new(id, @fixtures.library()),
        metadata: owned_nodes(id, 1).map(node_id => {
          node_id,
          data: @ion.IonValue::string("hint"),
        }),
      }
    }),
  )
  let files = project_files(backend="scheme")
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
  )
  let (metadata, _) = sidecar_lists(report.artifacts[1].content)
  @expect.expect_all(s => {
    s
    .expect(report.diagnostics.map(d => d.message), label="diagnostics")
    .to_be_empty()
    s
    .expect(report.artifacts.map(a => (a.format, a.path)), label="artifacts")
    .to_satisfy_respectively([
      it => it.all(pair => pair.snd().to_end_with(".scm")),
      it => it.all(pair => pair.snd().to_end_with(".symbols.10n")),
    ])
    s
    .expect(report.warnings.map(w => w.message), label="warnings")
    .to_be_empty()
    s.expect(metadata, label="sidecar metadata").to_have_length(1)
  })
}

///|
test "a plain rich_units backend accepts a rich project unit and warns about dropped metadata" {
  let engine = project_engine(
      project_profile(fn(_, id, _) raise {
        {
          ..@data.IRUnit::new(id, @fixtures.library()),
          metadata: owned_nodes(id, 1).map(node_id => {
            node_id,
            data: @ion.IonValue::string("hint"),
          }),
        }
      }),
    )
    |> with_plain_backend
  let files = project_files(backend="plain")
  let seen : Array[@engine.CompiledUnit] = []
  let report = engine.execute_content(
    project_plan(engine, files),
    project_read(files),
    on_unit=c => seen.push(c),
  )
  // The plain backend gets the same IR as a checkpoint: the project compiler applied exposed_modules itself.
  let checkpoint : Array[@engine.CompiledUnit] = []
  let files = project_files()
  ignore(
    engine.execute_content(project_plan(engine, files), project_read(files), on_unit=c => {
      checkpoint.push(c)
    }),
  )
  @expect.expect_all(s => {
    s
    .expect(report.diagnostics.map(d => d.message), label="diagnostics")
    .to_be_empty()
    s
    .expect(report.artifacts.map(a => a.path), label="artifacts")
    .single()
    .to_end_with(".scm")
    s
    .expect(report.warnings.map(w => w.message), label="warnings")
    .single()
    .all(it => {
      it.to_start_with("backend.metadata_dropped")
      it.to_contain("1 node metadata entries")
    })
    s
    .expect(
      seen.map(c => @codec.to_json(c.unit.distribution)),
      label="plain IR",
    )
    .to_equal(checkpoint.map(c => @codec.to_json(c.unit.distribution)))
  })
}

///|
test "ir-json still refuses a rich frontend" {
  let engine = project_engine(
    project_profile(fn(_, id, _) raise {
      @data.IRUnit::new(id, @fixtures.library())
    }),
  )
  @expect.expect(
    plan_error(() => {
      ignore(project_plan(engine, project_files(backend="ir-json")))
    }),
  ).to_start_with("frontend.typed_backend_required")
}

///|
test "a plain unit through the scheme backend gives no warning" {
  let (report, _) = run_scheme("scheme", "(define answer 42)")
  @expect.expect_all(s => {
    s
    .expect(report.diagnostics.map(d => d.message), label="diagnostics")
    .to_be_empty()
    s
    .expect(report.warnings.map(w => w.message), label="warnings")
    .to_be_empty()
  })
}

///|
/// Property: a plain rich_units backend warns exactly when the unit carries metadata, and the warning states each
/// count; the scheme backend never warns and its sidecar keeps every entry.
test "the metadata warning states what it drops, and only then" {
  @expect.for_all(
    (counts : (UInt32, UInt32)) => {
      let n = (counts.0 % 4).reinterpret_as_int()
      let m = (counts.1 % 4).reinterpret_as_int()
      let engine = project_engine(
          project_profile(fn(_, id, _) raise {
            {
              ..@data.IRUnit::new(id, @fixtures.library()),
              metadata: owned_nodes(id, n).map(node_id => {
                node_id,
                data: @ion.IonValue::string("hint"),
              }),
              provenance: Array::makei(m, _ => @ion.IonValue::string("origin")),
            }
          }),
        )
        |> with_plain_backend
      let scheme_files = project_files(backend="scheme")
      let scheme = engine.execute_content(
        project_plan(engine, scheme_files),
        project_read(scheme_files),
      )
      let (metadata, provenance) = sidecar_lists(scheme.artifacts[1].content)
      @expect.expect_all(s => {
        s.expect(scheme.warnings, label="scheme warnings").to_be_empty()
        s.expect(metadata, label="sidecar metadata").to_have_length(n)
        s.expect(provenance, label="sidecar provenance").to_have_length(m)
      })
      let files = project_files(backend="plain")
      let warnings = engine.execute_content(
          project_plan(engine, files),
          project_read(files),
        ).warnings
        .map(w => w.message)
        .filter(text => text.has_prefix("backend.metadata_dropped"))
      if n + m == 0 {
        @expect.expect(warnings, label="no metadata").to_be_empty()
      } else {
        @expect.expect(warnings, label="metadata")
        .single()
        .all(it => {
          it.to_contain("\{n} node metadata entries")
          it.to_contain("\{m} provenance entries")
        })
      }
    },
    count=25,
  )
}
