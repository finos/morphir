///|
/// A frontend failure, as the reply the worker returns.
priv suberror CompileFailed {
  CompileFailed(Json)
}

///|
priv struct EngineRun {
  unit : @data.IRUnit?
  report : @engine.ContentReport
  selection : @engine.SourceFrontendSelection?
}

///|
fn backend_for(target : String) -> String raise {
  match target {
    "" => "checkpoint"
    "scheme" | "elm" | "moonbit" => target
    _ =>
      raise @wire.Invalid(
        "workbench.unavailable_target",
        "This generation target is unavailable: " + target,
      )
  }
}

///|
/// One compile of `project` through the engine. The unit comes from `on_unit`, so the model is there even when
/// generation fails.
fn run_engine(
  engine : @engine.Engine,
  project : ProjectRequest,
  target : String,
) -> EngineRun raise {
  let tree = project_tree(project)
  let host = @engine.Host::memory(tree.files)
  let request = {
    ..@engine.Request::new(),
    overlay: overlay(project, backend_for(target)),
  }
  let plan = engine.plan(host, @workspace.discover(tree), request)
  let selection = plan.source_frontends().get(0)
  let units : Array[@data.IRUnit] = []
  // A pipe cannot feed `plan` here: it is the first argument of a method of another receiver.
  let report = engine.execute_content(
    plan,
    fn(path, _) raise { @data.Text((host.read)(path)) },
    on_unit=compiled => units.push(compiled.unit),
  )
  { unit: units.get(0), report, selection, }
}

///|
fn coordinate_profile(language : @ids.LanguageId) -> String {
  match language.to_string() {
    "moonbit" => "moonbit-parser-position-v1"
    "elm" => "elm-source-position-v1"
    _ => "morphir-source-location-v1"
  }
}

///|
fn location_json(location : @ir.SourceLocation?) -> Json {
  match location {
    Some(loc) =>
      @wire.obj([
        ("startLine", Json::number(loc.start_line.to_double())),
        ("startColumn", Json::number(loc.start_column.to_double())),
        ("endLine", Json::number(loc.end_line.to_double())),
        ("endColumn", Json::number(loc.end_column.to_double())),
      ])
    None => Json::null()
  }
}

///|
fn problem_detail(diagnostic : @engine.Diagnostic) -> String {
  match diagnostic.problem {
    Some(Source(p)) => p.detail
    Some(Generation(p)) => p.detail
    None => diagnostic.message
  }
}

///|
fn problem_json(diagnostic : @engine.Diagnostic, profile : String) -> Json {
  let (code, detail) = match diagnostic.problem {
    Some(Source(p)) => (p.code, p.detail)
    Some(Generation(p)) => (p.code, p.detail)
    None => ("", diagnostic.message)
  }
  @wire.obj([
    ("code", @wire.text(code)),
    ("coordinateProfile", @wire.text(profile)),
    ("detail", @wire.text(detail)),
    ("path", @wire.text(diagnostic.path)),
    ("source", location_json(diagnostic.location())),
  ])
}

///|
/// The failure reply of a compile that produced no unit. Problems are grouped by file, in report order.
fn frontend_failure(
  diagnostics : Array[@engine.Diagnostic],
  language : @ids.LanguageId,
) -> Json {
  let profile = coordinate_profile(language)
  guard diagnostics is [first, ..] else {
    return @wire.obj([
      ("success", Json::boolean(false)),
      ("message", @wire.text("The engine compiled no unit")),
    ])
  }
  let files : Array[(String, Array[Json])] = []
  for diagnostic in diagnostics {
    match files.search_by(entry => entry.0 == diagnostic.path) {
      Some(i) => files[i].1.push(problem_json(diagnostic, profile))
      None => files.push((diagnostic.path, [problem_json(diagnostic, profile)]))
    }
  }
  let message = match first.code() {
    Some(code) => code + ": " + problem_detail(first)
    None => first.message
  }
  @wire.obj([
    ("success", Json::boolean(false)),
    ("message", @wire.text(message)),
    ("frontendDiagnostic", problem_json(first, profile)),
    (
      "frontendDiagnostics",
      Json::array(
        files.map(entry => {
          @wire.obj([
            ("path", @wire.text(entry.0)),
            ("problems", Json::array(entry.1)),
          ])
        }),
      ),
    ),
  ])
}

///|
fn target_label(target : String) -> String {
  match target {
    "elm" => "Elm"
    "moonbit" => "MoonBit"
    _ => "Scheme"
  }
}

///|
/// The generated files of `report`, with paths relative to the generated project root.
fn artifacts_json(report : @engine.ContentReport) -> Json {
  let prefix = match report.projects.get(0) {
    Some(project) => project.root + "/"
    None => ""
  }
  Json::array(
    report.artifacts.map(artifact => {
      let path = match artifact.path.strip_prefix(prefix) {
        Some(rest) => rest.to_owned()
        None => artifact.path
      }
      let (content, binary, encoding) = match artifact.content {
        Text(text) => (text, false, "utf-8")
        Binary(bytes) => (@base64.encode(bytes[:]), true, "base64")
      }
      @wire.obj([
        ("path", @wire.text(path)),
        ("content", @wire.text(content)),
        ("binary", Json::boolean(binary)),
        ("encoding", @wire.text(encoding)),
      ])
    }),
  )
}

///|
/// The generation fields of a reply: artifacts and warnings, or the refusal with its problems.
fn generation_fields(
  report : @engine.ContentReport,
  target : String,
) -> Array[(String, Json)] {
  let refused = report.diagnostics.filter(d => d.stage == "backend")
  if !refused.is_empty() {
    let problems = refused.map(d => {
      match d.problem {
        Some(Generation(p)) =>
          @wire.obj([
            ("code", @wire.text(p.code)),
            ("nodePath", @wire.text(p.node_path)),
            ("detail", @wire.text(p.detail)),
          ])
        _ =>
          @wire.obj([
            ("code", @wire.text("")),
            ("nodePath", @wire.text("")),
            ("detail", @wire.text(d.message)),
          ])
      }
    })
    return [
      ("artifacts", Json::array([])),
      ("generationDiagnostics", Json::array(problems)),
      (
        "generationMessage",
        @wire.text(
          target_label(target) +
          " generation failed: " +
          refused.map(d => d.message).join("; "),
        ),
      ),
    ]
  }
  let fields = [("artifacts", artifacts_json(report))]
  let source = report.artifacts.filter(a => {
    a.format == "elm-source" || a.format == "scheme"
  })
  if target != "moonbit" && source is [first, ..] && first.content is Text(text) {
    fields.push(("generated", @wire.text(text)))
  }
  let warnings = report.warnings
    .filter(w => w.stage != "frontend")
    .map(w => {
      match w.details {
        Some(warning) => naming_warning(warning)
        None => @wire.text(w.message)
      }
    })
  fields.push(("generationWarnings", Json::array(warnings)))
  fields
}

///|
fn compile_reply(
  run : EngineRun,
  project : ProjectRequest,
  target : String,
) -> Array[(String, Json)] raise {
  // A rejected file fails the compile even when another file produced a unit.
  let rejected = run.report.diagnostics.filter(d => d.stage != "backend")
  guard run.unit is Some(unit) && rejected.is_empty() else {
    raise CompileFailed(
      frontend_failure(
        if rejected.is_empty() {
          run.report.diagnostics
        } else {
          rejected
        },
        project.language,
      ),
    )
  }
  let file = unit.distribution
  let (package_name, distribution_kind) = match file.distribution {
    Library(name, _, _) => (name, "Library")
    Specs(name, _, _) => (name, "Specification")
    Application(name, _, _, _) => (name, "Application")
  }
  let result = [
    ("success", Json::boolean(true)),
    ("ir", @codec.to_json(file)),
    ("irSource", @wire.text(@codec.to_json(file).stringify())),
    ("nodes", Json::array(describe(file))),
    ("evaluations", evaluation_profiles(file)),
    ("typedEvaluations", typed_profiles(file)),
    ("package", @wire.text(package_name.to_canonical())),
    ("distributionKind", @wire.text(distribution_kind)),
    ("formatVersion", @wire.text(file.format_version.to_release_string())),
  ]
  if run.selection is Some(selection) && selection.profile is Some(profile) {
    source_ui(result, unit.metadata)
    result.push(("sourceWarnings", source_warnings(unit.provenance)))
    match @data.Registry::new().encode("ion-text", unit) {
      Text(text) => result.push(("sourceUnitIon", @wire.text(text)))
      Binary(_) => ()
    }
    result.push(("sourceProfile", @wire.text(profile)))
    result.push(("sourceProvider", @wire.text(selection.provider)))
    let entries = match
      @wire.field(@wire.field(@wire.obj(result), "typedEvaluations"), "entries") {
      Object(entries) => entries.keys().collect()
      _ => []
    }
    entries.sort()
    result.push(("sourceEntries", Json::array(entries.map(@wire.text))))
    if profile == @moonbit_frontend.PROFILE {
      let entry = unit.metadata[0].node_id
        .strip_prefix("value:")
        .unwrap()
        .to_owned()
      result.push(("sourceEntry", @wire.text(entry)))
      result.push(("sourcePublic", Json::boolean(entries.contains(entry))))
    }
  }
  if target != "" {
    result.append(generation_fields(run.report, target))
  }
  result
}
