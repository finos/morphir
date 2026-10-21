///|
/// Compile the files the person edits. Only the browser's source-only validation policy is overlaid.
/// Projects execute independently so one failure cannot discard another project's results.
fn compile_workspace(engine : @engine.Engine, request : Json) -> Json raise {
  let files = @workspace_files.Files::from_json(
    @wire.field(request, "workspace"),
  )
  let tree = files.tree()
  let workspace = files.discover()
  let selector = optional_text(request, "projectPath").unwrap_or("")
  if optional_text(request, "operation") == Some("run-project") &&
    selector == "" {
    raise @config.Invalid("Compile & run requires a current project path")
  }
  let projects = workspace.select(selector~)
  let host = @engine.Host::memory(tree.files)
  let overlay = @config.parse(
    "[pipeline]\nvalidation = 'source-only'\n",
    origin="Browser host",
  )
  let results : Array[Json] = []
  let artifacts : Array[Json] = []
  let mut successful = true
  for project in projects {
    let path = if project.root == workspace.root {
      "."
    } else if workspace.root == "" {
      project.root
    } else {
      project.root[workspace.root.length() + 1:].to_owned()
    }
    let language = project.document.text("frontend.language", "scheme")
    let target = project.document.text("pipeline.backend", "ir-json")
    let reply = try {
      if project.error is Some(message) {
        raise @config.Invalid(message)
      }
      let plan = engine.plan(host, workspace, {
        ..@engine.Request::new(),
        selector: path,
        overlay,
      })
      let units : Array[@data.IRUnit] = []
      let sources : Array[String] = []
      let report = engine.execute_content(
        plan,
        fn(source, _) raise {
          files.content(source).unwrap_or(@data.Text((host.read)(source)))
        },
        on_unit=compiled => {
          units.push(compiled.unit)
          sources.push(compiled.source)
        },
      )
      let selected_unit = files
        .opened()
        .bind(opened => sources.search_by(source => source == opened))
        .unwrap_or(0)
      let run : EngineRun = {
        unit: units.get(selected_unit),
        report,
        selection: plan.source_frontends().get(selected_unit),
      }
      let fields = compile_reply(
        run,
        @ids.LanguageId::parse(language),
        if target == "checkpoint" || target == "ir-json" {
          ""
        } else {
          target
        },
      )
      if sources.get(selected_unit) is Some(source) {
        fields.push(("source", @wire.text(source)))
      }
      if optional_text(request, "operation") == Some("run-project") {
        if language != "scheme" {
          raise @config.Invalid(
            "Compile, then evaluate this project's functions in Explorer",
          )
        }
        let index = files
          .opened()
          .bind(opened => sources.search_by(source => source == opened))
          .unwrap_or(0)
        if units.get(index) is Some(unit) {
          let main = @ids.SourcePackageName::parse(project.name)
            .to_path()
            .to_canonical()
          let source_root = @workspace.join(
            project.root,
            project.document.text("project.source_directory", "src"),
          )
          let relative = sources[index]
            .strip_prefix(source_root + "/")
            .unwrap_or(sources[index][:])
            .to_owned()
          let stem = relative
            .rev_find(".")
            .map(dot => relative[:dot].to_owned())
            .unwrap_or(relative)
          let prefix = project.document.text("project.module_prefix", "")
          let module_name = if prefix == "" {
            stem
          } else {
            prefix + "/" + stem
          }
          fields.push(
            (
              "value",
              @wire.text(
                @scheme.value_to_string(
                  @backend.run_file(
                    unit.distribution,
                    @ir.FQName::parse(
                      main + ":" + @ids.canonical_path(module_name) + "#main",
                    ),
                    [],
                  ),
                ),
              ),
            ),
          )
        }
      }
      fields.push(("success", Json::boolean(report.successful())))
      fields.push(("artifacts", artifacts_json(report)))
      fields.push(
        (
          "units",
          Json::array(
            units.mapi((index, unit) => {
              let fields = compile_reply(
                {
                  unit: Some(unit),
                  report,
                  selection: plan.source_frontends().get(index),
                },
                @ids.LanguageId::parse(language),
                "",
              )
              fields.push(("source", @wire.text(sources[index])))
              @wire.obj(fields)
            }),
          ),
        ),
      )
      @wire.obj(fields)
    } catch {
      CompileFailed(reply) => reply
      @config.Invalid(message) =>
        failure(message, "workbench.project_configuration", "compile")
      error =>
        failure(
          @scheme.error_message(error),
          "workbench.project_compile",
          "compile",
        )
    }
    if @wire.optional(reply, "success") != Some(Json::boolean(true)) {
      successful = false
    }
    let generated = match @wire.optional(reply, "artifacts") {
      Some(Array(items)) => items
      _ => []
    }
    for artifact in generated {
      guard artifact is Object(fields) else { continue }
      let fields = fields.copy()
      let file = @wire.string(@wire.field(artifact, "path"))
      fields["path"] = @wire.text(
        (if path == "." { "root" } else { "projects/" + path }) + "/" + file,
      )
      fields["projectPath"] = @wire.text(path)
      artifacts.push(Json::object(fields))
    }
    results.push(
      @wire.obj([
        ("path", @wire.text(path)),
        ("name", @wire.text(project.name)),
        ("languageId", @wire.text(language)),
        ("target", @wire.text(target)),
        ("result", reply),
      ]),
    )
  }
  @wire.obj([
    ("success", Json::boolean(successful)),
    ("projects", Json::array(results)),
    ("artifacts", Json::array(artifacts)),
    ("browserBuildPolicy", @wire.text("source-only")),
    ("discovery", workspace.to_json()),
  ])
}
