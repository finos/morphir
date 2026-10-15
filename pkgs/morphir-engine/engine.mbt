///| Configuration precedence: manifest, workspace script, project script, explicit script.

///|
/// Transforms accumulate in that order. Results are returned without host writes.
pub fn Engine::run(
  self : Engine,
  host : Host,
  input : Input,
  config? : String = "",
  bind_runtime? : (@scheme.Runtime) -> Unit raise = fn(_) { () },
) -> Report {
  let artifacts : Array[Artifact] = []
  let diagnostics : Array[Diagnostic] = []
  let outputs : Map[String, Bool] = Map([])
  let seen_projects : Map[String, Bool] = Map([])
  fn project(
    root : String,
    project_manifest : Bool,
    file : String?,
    inherited : String,
  ) -> Unit {
    let mut stage = "configuration"
    try {
      let runtime = config_runtime(self.limits)
      bind_runtime(runtime)
      let settings = Config::{
        frontend: "scheme",
        frontend_provider: None,
        frontend_profile: None,
        backend: "ir-json",
        output: "dist",
        package_name: "user",
        source: "",
        inference: "off",
        transforms: [],
      }
      if project_manifest {
        let fields = manifest(host, root, "morphir.json")
        settings.package_name = optional_string(fields, "name", "user")
        settings.source = normalize(
          optional_string(fields, "sourceDirectory", "src"),
        )
      }
      if inherited != "" {
        settings.apply(runtime, inherited)
      }
      let config_path = join(root, "morphir.config.scm")
      if (host.exists)(config_path) {
        settings.apply(runtime, (host.read)(config_path))
      }
      if config != "" {
        settings.apply(runtime, config)
      }
      if settings.inference != "off" {
        raise @scheme.Invalid(
          "pipeline.inference needs the planned pipeline (Engine::plan)",
        )
      }
      let frontend = match self.select_source_frontend(settings) {
        Some(value) => value
        None => raise @scheme.Invalid("Unknown frontend: " + settings.frontend)
      }
      let backend = match self.backends.get(settings.backend) {
        Some(value) => value
        None => raise @scheme.Invalid("Unknown backend: " + settings.backend)
      }
      if !(frontend.compiler is FileCompiler(_)) {
        raise @scheme.Invalid(
          "frontend.typed_backend_required: Rich source units require a planned checkpoint or generation backend",
        )
      }
      if !backend.extension.has_prefix(".") || backend.extension.contains("/") {
        raise @scheme.Invalid("Backend extension must be a dotted file suffix")
      }
      let source_root = if file is Some(_) {
        root
      } else {
        join(root, settings.source)
      }
      let output_root = join(root, settings.output)
      if source_root == output_root || within(output_root, source_root) {
        raise @scheme.Invalid("Source directory is inside output directory")
      }
      stage = "discovery"
      let paths = match file {
        Some(path) => [path]
        None => (host.list)(source_root)
      }
      paths.sort()
      let seen : Map[String, Bool] = Map([])
      for path in paths {
        let path = normalize(path)
        let relative_path = relative(source_root, path)
        if seen.contains(path) {
          continue
        }
        seen[path] = true
        if file is None &&
          (
            path == config_path ||
            path == join(root, "morphir.json") ||
            path == join(root, "morphir-workspace.json") ||
            within(output_root, path)
          ) {
          continue
        }
        if file is None &&
          !frontend.extensions.any(extension => path.has_suffix(extension)) {
          continue
        }
        let mut file_stage = "read"
        try {
          let source = Source::{
            path,
            relative_path,
            content: (host.read)(path),
            package_name: settings.package_name,
            module_name: stem(relative_path),
          }
          file_stage = "frontend"
          let mut ir = frontend.compile_unit(source, stem(relative_path), fn() {
              false
            }).distribution
          file_stage = "transform"
          runtime.set_global("source-path", @scheme.Text(path))
          runtime.set_global("project-root", @scheme.Text(root))
          for transform in settings.transforms {
            ir = runtime.call(transform, [@scheme.IRFile(ir)]).as_file()
          }
          file_stage = "backend"
          let content = (backend.emit)(ir)
          file_stage = "output"
          let path = join(output_root, stem(relative_path) + backend.extension)
          if outputs.contains(path) {
            raise @scheme.Invalid("Duplicate output path: " + path)
          }
          outputs[path] = true
          artifacts.push({ path, source: source.path, content, })
        } catch {
          error =>
            diagnostics.push({
              path,
              stage: file_stage,
              message: diagnostic_message(error),
              details: None,
            })
        }
      }
    } catch {
      error =>
        diagnostics.push({
          path: root,
          stage,
          message: diagnostic_message(error),
          details: None,
        })
    }
  }
  let mut requested_path = ""
  try {
    match input {
      File(path) => {
        requested_path = path
        let path = normalize(path)
        if path == "" {
          raise @scheme.Invalid("File path must be nonempty")
        }
        project(parent(path), false, Some(path), "")
      }
      Directory(root) => {
        requested_path = root
        project(normalize(root), false, None, "")
      }
      Project(root) => {
        requested_path = root
        project(normalize(root), true, None, "")
      }
      Workspace(root) => {
        requested_path = root
        let root = normalize(root)
        let fields = manifest(host, root, "morphir-workspace.json")
        let projects = match fields.get("projects") {
          Some(Array(items)) => items
          _ => raise @scheme.Invalid("Workspace requires a projects array")
        }
        let config_path = join(root, "morphir.config.scm")
        let inherited = if (host.exists)(config_path) {
          (host.read)(config_path)
        } else {
          ""
        }
        for item in projects {
          try {
            let path = match item {
              String(path) => path
              _ =>
                raise @scheme.Invalid(
                  "Workspace project must be a relative path",
                )
            }
            let path = join(root, path)
            if path == root {
              raise @scheme.Invalid("Workspace projects must be subdirectories")
            }
            if seen_projects.contains(path) {
              continue
            }
            seen_projects[path] = true
            project(path, true, None, inherited)
          } catch {
            error =>
              diagnostics.push({
                path: root,
                stage: "discovery",
                message: diagnostic_message(error),
                details: None,
              })
          }
        }
      }
    }
  } catch {
    error =>
      diagnostics.push({
        path: requested_path,
        stage: "discovery",
        message: diagnostic_message(error),
        details: None,
      })
  }
  { processed: artifacts.length(), artifacts, diagnostics, }
}

///|
fn rejection_message(
  code : String,
  detail : String,
  location : @ir.SourceLocation?,
) -> String {
  code +
  ": " +
  detail +
  (match location {
    Some(loc) =>
      " at " +
      loc.start_line.to_string() +
      ":" +
      loc.start_column.to_string() +
      "-" +
      loc.end_line.to_string() +
      ":" +
      loc.end_column.to_string()
    None => ""
  })
}

///|
fn diagnostic_message(error : Error) -> String {
  match error {
    Rejected(code, detail, location) =>
      rejection_message(code, detail, location)
    RejectedSources(problems) =>
      problems
      .map(p => rejection_message(p.code, p.detail, p.location))
      .join("\n")
    @configuration.Invalid(message) => message
    @wire.Invalid(code, message) => code + ": " + message
    @data.Invalid(code, message) => code + ": " + message
    @moonbit.Invalid(code, context, message) =>
      code + " at " + context + ": " + message
    _ => {
      let code = @wire.diagnostic(error)
      if code == "unknown_error" {
        @scheme.error_message(error)
      } else {
        code
      }
    }
  }
}
