///|
pub(all) struct Request {
  selector : String
  all : Bool
  invocation : String
  file : String?
  directory : String?
  script : String
  overlay : @configuration.Document
}

///|
pub fn Request::new() -> Request {
  {
    selector: "",
    all: false,
    invocation: "",
    file: None,
    directory: None,
    script: "",
    overlay: @configuration.empty(),
  }
}

///|
/// The project of a `PerProject` source compiler: one unit for all source files of the project.
priv struct ProjectJob {
  unit_id : String
  package_name : @ids.SourcePackageName
  exposed_modules : Array[@ids.SourceModuleName]
}

///|
priv struct Job {
  root : String
  source_root : String
  destination : String
  paths : Array[String]
  settings : Config
  module_prefix : String
  exposed : Array[String]?
  runtime : @scheme.Runtime
  frontend : Frontend?
  backend : Backend?
  read_bytes : Bool
  suffix : String
  boundary : Checkpoint?
  generator : GenerationBackend?
  generator_options : Json
  build_policy : BuildPolicy
  components : Array[ComponentStep]
  strict_naming : Bool
  inference : @typing.Mode?
  project : ProjectJob?
}

///|
pub struct Plan {
  priv jobs : Array[Job]
  priv mut consumed : Bool
  priv sources : Array[String]
  priv destinations : Array[String]
  output_root : String
}

///|
fn Config::overlay(
  self : Config,
  values : @configuration.Document,
) -> Unit raise {
  self.frontend = values.text("frontend.language", self.frontend)
  if values.get("frontend.provider") is Some(_) {
    self.frontend_provider = Some(
      source_constraint(values.text("frontend.provider", ""), "provider"),
    )
  }
  if values.get("frontend.profile") is Some(_) {
    self.frontend_profile = Some(
      source_constraint(values.text("frontend.profile", ""), "profile"),
    )
  }
  self.backend = values.text("pipeline.backend", self.backend)
  self.source = normalize(values.text("project.source_directory", self.source))
  self.package_name = values.text("project.name", self.package_name)
  self.inference = values.text("pipeline.inference", self.inference)
}

///|
/// True when `message` names `key` as a whole path, not as the start of a longer one.
fn names_key(message : String, key : String) -> Bool {
  message.has_suffix(key) ||
  [":", " ", ",", ")", "\n"].iter().any(end => message.contains(key + end))
}

///|
/// Where an option came from: the file of the key that the message names, or of its nearest table.
fn option_origin(
  document : @configuration.Document,
  table : String,
  message : String,
) -> String {
  let mut best_path = ""
  let mut best_origin = ""
  let origins : Array[String] = []
  for path, origin in document.provenance {
    if path != table && !path.has_prefix(table + ".") {
      continue
    }
    if !origins.contains(origin) {
      origins.push(origin)
    }
    // Try the leaf path and then each enclosing table, longest first.
    let mut candidate = path
    while candidate.length() > best_path.length() {
      if names_key(message, candidate) {
        best_path = candidate
        best_origin = origin
        break
      }
      match candidate.rev_find(".") {
        Some(i) => candidate = candidate[:i].to_owned()
        None => break
      }
    }
  }
  if best_origin != "" {
    " (set in " + best_origin + ")"
  } else if !origins.is_empty() {
    origins.sort()
    " (" + table + " set in " + origins.join(", ") + ")"
  } else {
    ""
  }
}

///|
pub fn Engine::plan(
  self : Engine,
  host : Host,
  workspace : @workspace.Workspace,
  request : Request,
  cancelled~ : () -> Bool = fn() { false },
  bind_runtime~ : (@scheme.Runtime) -> Unit raise = fn(_) { () },
  codecs~ : @data.Registry? = None,
) -> Plan raise {
  let jobs = []
  let sources = []
  let destinations = []
  let out_dir = normalize(
    workspace.document.text("workspace.out_dir", ".morphir/out"),
  )
  if out_dir == "" {
    raise @configuration.Invalid("workspace.out_dir must be nonempty")
  }
  let output_root = join(workspace.root, out_dir)
  let selection = workspace.select(
    selector=request.selector,
    all=request.all,
    invocation=request.invocation,
  )
  for selected in selection {
    let effective = @configuration.merge(selected.document, request.overlay)
    let (settings, runtime, version) = self.resolve_project_config(
      host,
      workspace,
      selected,
      request.script,
      request.overlay,
      cancelled,
      bind_runtime,
    )
    let module_prefix = effective.text("project.module_prefix", "")
    let exposed = match effective.get("project.exposed_modules") {
      Some(_) =>
        Some(effective.strings("project.exposed_modules").map(canonical_path))
      None => None
    }
    let root_script = join(workspace.root, "morphir.config.scm")
    let project_script = join(selected.root, "morphir.config.scm")
    let generator = self.generators.get(settings.backend)
    let checkpoint = settings.backend == "checkpoint" || generator is Some(_)
    let generator_options = match generator {
      Some(g) => {
        let options = match effective.json("backends." + settings.backend) {
          Some(value) => value
          None => Json::object(Map([]))
        }
        (g.validate_options)(options) catch {
          error => {
            let message = match error {
              @configuration.Invalid(text) => text
              other => other.to_string()
            }
            raise @configuration.Invalid(
              message +
              option_origin(effective, "backends." + settings.backend, message),
            )
          }
        }
        options
      }
      None => Json::object(Map([]))
    }
    let build_policy = match generator {
      Some(g) => {
        let fallback = if g.targets.is_empty() {
          "source-only"
        } else {
          "required"
        }
        match effective.text("pipeline.validation", fallback) {
          "source-only" => SourceOnly
          "required" => {
            let target = effective.text("pipeline.target", "wasm")
            if !g.targets.contains(target) {
              raise @configuration.Invalid(
                "build.unsupported_target: " + target,
              )
            }
            Required(target)
          }
          other =>
            raise @configuration.Invalid(
              "Unknown project validation policy: " + other,
            )
        }
      }
      None => SourceOnly
    }
    let component_names = effective.strings("pipeline.components")
    if !checkpoint && !component_names.is_empty() {
      raise @configuration.Invalid("component.typed_backend_required")
    }
    let policy_name = effective.text("pipeline.metadata_policy", "retain")
    let components = component_names.map(name => {
      let component = match self.components.get(name) {
        Some(c) => c
        None => raise @configuration.Invalid("component.unknown: " + name)
      }
      let policy = match self.metadata_policies.get(policy_name) {
        Some(p) => p
        None =>
          raise @configuration.Invalid(
            "component.unknown_metadata_policy: " + policy_name,
          )
      }
      ComponentStep::{ name, component, policy_name, policy, }
    })
    let input_format = self.data_formats.get(
      if settings.frontend == "ir-json" {
        "morphir-json"
      } else {
        settings.frontend
      },
    )
    let frontend = if input_format is Some(_) {
      if settings.frontend_provider is Some(_) ||
        settings.frontend_profile is Some(_) {
        raise @configuration.Invalid(
          "frontend.source_constraint_on_data_format: " + settings.frontend,
        )
      }
      self.frontends.get(settings.frontend)
    } else {
      self.select_source_frontend(settings)
    }
    if frontend is None && input_format is None {
      raise @configuration.Invalid("Unknown frontend: " + settings.frontend)
    }
    let project_compiler = frontend is Some(f) &&
      f.compiler is ProjectCompiler(_, _)
    let plain = if checkpoint {
      None
    } else {
      self.backends.get(settings.backend)
    }
    if !checkpoint &&
      frontend is Some(f) &&
      !(f.compiler is FileCompiler(_)) &&
      !(plain is Some(b) && b.rich_units) {
      raise @configuration.Invalid(
        "frontend.typed_backend_required: Rich source units require checkpoint or generation output",
      )
    }
    let whole_project = "frontend.project_compiler_file: " +
      settings.frontend +
      " compiles whole projects; select the project, not a file or directory"
    if project_compiler && request.file is Some(_) {
      raise @configuration.Invalid(whole_project)
    }
    let boundary = if checkpoint {
      let format = effective.text("pipeline.checkpoint_format", "ion-binary")
      let output = self.data_format(format)
      let registry = match codecs {
        Some(registry) => registry
        None => @data.Registry::new()
      }
      let required_codecs = [output.codec] +
        (match input_format {
          Some(input) => [input.codec]
          None => []
        })
      for codec in required_codecs {
        if !registry.has_codec(codec) {
          raise @configuration.Invalid("data.unknown_codec: " + codec)
        }
      }
      if version.major != 4U {
        raise @configuration.Invalid(
          "Checkpoint IR uses current version 4; use ir-json for historical export",
        )
      }
      if !settings.transforms.is_empty() ||
        (exposed is Some(_) && !project_compiler) {
        raise @configuration.Invalid(
          "Checkpoint identity processing does not yet support transforms or exposed_modules; metadata lineage is required",
        )
      }
      Some(Checkpoint::{ input: input_format, output, codecs: registry, })
    } else {
      if frontend is None && input_format is Some(_) {
        raise @configuration.Invalid(
          "Data-boundary inputs require the checkpoint backend",
        )
      }
      None
    }
    let backend = if checkpoint {
      None
    } else {
      let registered = match self.backends.get(settings.backend) {
        Some(b) => b
        None =>
          raise @configuration.Invalid("Unknown backend: " + settings.backend)
      }
      Some(
        if settings.backend == "ir-json" {
          Backend::{
            extension: registered.extension,
            emit: fn(ir) raise {
              @versioned_json.write(
                @migration.migrate(@versioned.V4(ir), version),
              )
            },
            rich_units: registered.rich_units,
          }
        } else {
          registered
        },
      )
    }
    let suffix = if generator is Some(_) {
      ".project"
    } else {
      match boundary {
        Some(boundary) => boundary.output.suffix
        None => backend.unwrap().extension
      }
    }
    let extensions = match boundary {
      Some(b) =>
        match b.input {
          Some(input) => input.extensions
          None => frontend.unwrap().extensions
        }
      None => frontend.unwrap().extensions
    }
    let read_bytes = match boundary {
      Some(b) =>
        match b.input {
          Some(input) => input.binary
          None => false
        }
      None => false
    }
    if !suffix.has_prefix(".") || suffix.contains("/") || suffix.contains("\\") {
      raise @configuration.Invalid("Invalid backend file suffix")
    }
    fn owned(path : String) -> Bool {
      !workspace.projects.any(other => {
        other.root != selected.root &&
        @workspace.within(selected.root, other.root) &&
        @workspace.within(other.root, path)
      })
    }
    let project_source = join(selected.root, settings.source)
    let requested = match request.directory {
      Some(directory) => normalize(directory)
      None => project_source
    }
    if !owned(requested) {
      raise @configuration.Invalid(
        "Input directory belongs to another workspace project",
      )
    }
    if !@workspace.within(selected.root, requested) {
      raise @configuration.Invalid(
        "Input directory is outside selected project",
      )
    }
    // A project compiler compiles from the project's source directory. A directory request selects the project
    // only when it holds that directory; a narrower one would compile part of the project.
    if project_compiler && !@workspace.within(requested, project_source) {
      raise @configuration.Invalid(whole_project)
    }
    let source_root = if project_compiler { project_source } else { requested }
    if @workspace.within(output_root, source_root) {
      raise @configuration.Invalid(
        "Source directory is inside output directory",
      )
    }
    let relative_project = if selected.root == workspace.root {
      ""
    } else if workspace.root == "" {
      selected.root
    } else {
      selected.root[workspace.root.length() + 1:].to_owned()
    }
    let destination = join(join(output_root, relative_project), "compile.dest")
    let output = join(destination, settings.output)
    let paths = match request.file {
      Some(file) => {
        let path = normalize(file)
        if !owned(path) {
          raise @configuration.Invalid(
            "File belongs to another workspace project: " + path,
          )
        }
        if !@workspace.within(source_root, path) || path == source_root {
          raise @configuration.Invalid(
            "File is outside selected source directory: " + path,
          )
        }
        [path]
      }
      None =>
        (host.list)(source_root).filter(fn(path) {
          owned(path) &&
          !@workspace.within(output_root, path) &&
          path != root_script &&
          path != project_script &&
          !["morphir.json", "morphir-workspace.json"].contains(
            path.split("/").last().unwrap_or("").to_owned(),
          ) &&
          extensions.any(extension => path.has_suffix(extension))
        })
    }
    paths.sort()
    let unique = []
    let seen = Map([])
    for path in paths {
      let path = normalize(path)
      if !owned(path) {
        continue
      }
      if !@workspace.within(source_root, path) || path == source_root {
        raise @configuration.Invalid(
          "Host listed a path outside source root: " + path,
        )
      }
      // A file compiler writes one output per source. A project compiler writes one output for the
      // project, so nested module paths (`Api` and `Api/Util`) do not collide.
      if !project_compiler {
        let rel = relative(source_root, path)
        let target = join(
          output,
          stem(rel) + (if generator is Some(_) { "" } else { suffix }),
        )
        let key = target.to_lower()
        if seen.contains(key) ||
          seen
          .keys()
          .any(existing => {
            @workspace.within(existing, key) || @workspace.within(key, existing)
          }) {
          raise @configuration.Invalid("Duplicate output path: " + target)
        }
        seen[key] = true
      }
      unique.push(path)
      sources.push(path)
    }
    if project_compiler &&
      frontend
      is Some({ capabilities: Some({ max_documents: Some(limit), .. }), .. }) &&
      unique.length() > limit {
      raise @configuration.Invalid(
        "frontend.too_many_documents: " +
        unique.length().to_string() +
        " sources; " +
        settings.frontend +
        " accepts at most " +
        limit.to_string(),
      )
    }
    if destinations.any(existing => {
        @workspace.within(existing, destination) ||
        @workspace.within(destination, existing)
      }) {
      raise @configuration.Invalid(
        "Task output destinations overlap: " + destination,
      )
    }
    destinations.push(destination)
    let inference = inference_mode(settings.inference) catch {
      @configuration.Invalid(message) =>
        raise @configuration.Invalid(
          message + option_origin(effective, "pipeline", message),
        )
      e => raise e
    }
    let generator = self.bind_project_metadata(settings.backend, generator, {
      workspace_root: workspace.root,
      project_root: selected.root,
      project_name: selected.name,
      request: effective.metadata_provider_request(),
    })
    jobs.push({
      root: selected.root,
      source_root,
      destination: output,
      paths: unique,
      settings,
      module_prefix,
      exposed: if project_compiler {
        None
      } else {
        exposed
      },
      runtime,
      frontend,
      backend,
      suffix,
      read_bytes,
      boundary,
      generator,
      generator_options,
      build_policy,
      components,
      strict_naming: effective.boolean("pipeline.strict_naming", false),
      inference,
      project: if project_compiler {
        let exposed = []
        if effective.get("project.exposed_modules") is Some(_) {
          for text in effective.strings("project.exposed_modules") {
            exposed.push(@ids.SourceModuleName::parse(text))
          }
        }
        Some({
          unit_id: canonical_path(settings.package_name),
          package_name: @ids.SourcePackageName::parse(settings.package_name),
          exposed_modules: exposed,
        })
      } else {
        None
      },
    })
  }
  { jobs, consumed: false, sources, destinations, output_root, }
}

///|
/// The frontend source of one file. File and project compilers both use it, so they name modules the same way.
fn Job::source(
  self : Job,
  path : String,
  relative_path : String,
  content : @data.Content,
) -> Source raise {
  {
    path,
    relative_path,
    content: match content {
      Text(text) => text
      Binary(_) =>
        raise @configuration.Invalid(
          "data.encoding_mismatch: Expected text frontend content",
        )
    },
    package_name: self.settings.package_name,
    module_name: if self.module_prefix == "" {
      stem(relative_path)
    } else {
      self.module_prefix + "/" + stem(relative_path)
    },
  }
}

///|
pub fn Engine::execute_content(
  _self : Engine,
  plan : Plan,
  read : (String, Bool) -> @data.Content raise,
  cancelled~ : () -> Bool = fn() { false },
  on_unit~ : (CompiledUnit) -> Unit = _ => (),
) -> ContentReport {
  let artifacts = []
  let projects = []
  let mut processed = 0
  let diagnostics = []
  let warnings = []
  if plan.consumed {
    return {
      artifacts,
      projects,
      warnings,
      processed: 0,
      diagnostics: [
        {
          path: "",
          stage: "plan",
          message: "Execution plans are single-use; prepare a fresh plan",
          details: None,
          problem: None,
        },
      ],
    }
  }
  plan.consumed = true
  for job in plan.jobs {
    job.runtime.set_cancelled(cancelled)
    // A project compiler gives one unit for all sources of its project; it reports at the source directory.
    let inputs = match job.project {
      Some(_) => if job.paths.is_empty() { [] } else { [job.source_root] }
      None => job.paths
    }
    for path in inputs {
      let mut stage = "read"
      // The file of a `read` diagnostic: a project reads every source before its compile.
      let mut diagnostic_path = path
      try {
        if cancelled() {
          raise @configuration.Invalid("Cancelled")
        }
        let mut checkpoint_unit : @data.IRUnit? = None
        let unit_id = match job.project {
          Some(project) => {
            let sources : Array[Source] = []
            for source_path in job.paths {
              diagnostic_path = source_path
              sources.push(
                job.source(
                  source_path,
                  relative(job.source_root, source_path),
                  read(source_path, false),
                ),
              )
            }
            diagnostic_path = path
            stage = "frontend"
            checkpoint_unit = Some(
              job.frontend
              .unwrap()
              .compile_project(
                {
                  package_name: project.package_name,
                  exposed_modules: project.exposed_modules.copy(),
                  sources,
                },
                project.unit_id,
                cancelled,
              ),
            )
            project.unit_id
          }
          None => {
            let relative_path = relative(job.source_root, path)
            let content = read(path, job.read_bytes)
            let unit_id = stem(relative_path)
            stage = "frontend"
            checkpoint_unit = match job.boundary {
              Some(boundary) =>
                match boundary.input {
                  Some(format) =>
                    Some(
                      boundary.codecs.decode(format.codec, { unit_id, content, }),
                    )
                  None => None
                }
              None => None
            }
            if checkpoint_unit is None {
              checkpoint_unit = Some(
                job.frontend
                .unwrap()
                .compile_unit(
                  job.source(path, relative_path, content),
                  unit_id,
                  cancelled,
                ),
              )
            }
            unit_id
          }
        }
        let seen_warnings : Map[String, Bool] = Map([])
        for item in checkpoint_unit.unwrap().provenance {
          if @diagnostics.warning_from_ion(item) is Some(warning) {
            let key = warning.key()
            if seen_warnings.contains(key) {
              continue
            }
            seen_warnings[key] = true
            warnings.push({
              path,
              stage: warning.stage,
              message: warning.display(),
              details: Some(warning),
              problem: None,
            })
            if job.strict_naming &&
              (
                warning.code.has_prefix("moonbit_frontend.name_") ||
                warning.code.has_prefix("moonbit_backend.name_")
              ) {
              raise @configuration.Invalid(
                "naming.strict: " + warning.display(),
              )
            }
          }
        }
        let mut ir = checkpoint_unit.unwrap().distribution
        if job.exposed is Some(exposed) {
          match ir.distribution {
            Library(name, dependencies, package_def) => {
              let modules = package_def.modules.map(fn(module_name, access) {
                {
                  ..access,
                  access: if exposed.contains(module_name.to_canonical()) {
                    @ir.Access::Public
                  } else {
                    @ir.Access::Private
                  },
                }
              })
              ir = @ir.IRFile::new(
                @ir.Distribution::Library(name, dependencies, { modules, }),
              )
            }
            _ =>
              raise @configuration.Invalid(
                "exposed_modules requires a library distribution",
              )
          }
        }
        stage = "component"
        if !job.components.is_empty() {
          let mut unit = checkpoint_unit.unwrap_or(
            @data.IRUnit::new(unit_id, ir),
          )
          for component in job.components {
            if cancelled() {
              raise @configuration.Invalid("Cancelled")
            }
            unit = apply_component(unit, component)
          }
          ir = unit.distribution
          checkpoint_unit = Some(unit)
        }
        stage = "transform"
        job.runtime.set_global("source-path", @scheme.Text(path))
        job.runtime.set_global("project-root", @scheme.Text(job.root))
        for transform in job.settings.transforms {
          if cancelled() {
            raise @configuration.Invalid("Cancelled")
          }
          ir = job.runtime.call(transform, [@scheme.IRFile(ir)]).as_file()
        }
        stage = "inference"
        if job.inference is Some(mode) {
          let checkpoint = job.boundary is Some(_) || job.generator is Some(_)
          let unit = match checkpoint_unit {
            Some(unit) if checkpoint => unit
            _ => @data.IRUnit::new(unit_id, ir)
          }
          let result = infer_unit(unit, mode, checkpoint)
          ir = result.distribution
          if checkpoint {
            checkpoint_unit = Some(result)
          }
        }
        on_unit({
          source: path,
          unit: { ..checkpoint_unit.unwrap(), distribution: ir, },
        })
        stage = "backend"
        if cancelled() {
          raise @configuration.Invalid("Cancelled")
        }
        if job.generator is Some(generator) {
          let unit = match checkpoint_unit {
            Some(unit) => unit
            None => @data.IRUnit::new(unit_id, ir)
          }
          let batch = (generator.generate)(
            unit,
            job.generator_options,
            cancelled,
          )
          for warning in batch.warnings {
            warnings.push({
              path,
              stage: "backend",
              message: warning,
              details: None,
              problem: None,
            })
          }
          for warning in batch.structured_warnings {
            let key = warning.key()
            if !seen_warnings.contains(key) {
              seen_warnings[key] = true
              warnings.push({
                path,
                stage: warning.stage,
                message: warning.display(),
                details: Some(warning),
                problem: None,
              })
            }
            if job.strict_naming &&
              warning.code.has_prefix("moonbit_backend.name_") {
              raise @configuration.Invalid(
                "naming.strict: " + warning.display(),
              )
            }
          }
          validate_batch(
            batch,
            join(job.destination, unit_id),
            path,
            job.build_policy,
            artifacts,
            projects,
          )
          processed += 1
          continue
        }
        let content = match job.boundary {
          Some(boundary) =>
            boundary.codecs.encode(
              boundary.output.codec,
              match checkpoint_unit {
                Some(unit) => unit
                None => @data.IRUnit::new(unit_id, ir)
              },
            )
          None => {
            let unit = checkpoint_unit.unwrap()
            // every unit carries the pipeline marker annotation; only other annotations are dropped data
            let marker = @data.IRUnit::new(unit.id, ir).annotations
            let (n, m, k) = (
              unit.metadata.length(),
              unit.provenance.length(),
              unit.annotations.filter(a => !marker.contains(a)).length(),
            )
            if n + m + k > 0 {
              warnings.push({
                path,
                stage: "backend",
                message: "backend.metadata_dropped: " +
                job.settings.backend +
                " keeps the IR only; it drops \{n} node metadata entries, \{m} provenance entries and \{k} annotations",
                details: None,
                problem: None,
              })
            }
            @data.Text((job.backend.unwrap().emit)(ir))
          }
        }
        if job.boundary is Some(boundary) {
          if (content is @data.Binary(_)) != boundary.output.binary {
            raise @configuration.Invalid(
              "data.encoding_mismatch: Codec output disagrees with registered format",
            )
          }
        }
        processed += 1
        artifacts.push({
          path: join(job.destination, unit_id + job.suffix),
          source: path,
          content,
          format: match job.boundary {
            Some(b) => b.output.codec
            None => job.settings.backend
          },
        })
      } catch {
        RejectedSources(problems) =>
          for problem in problems {
            diagnostics.push({
              path: if problem.path == "" {
                path
              } else {
                join(job.source_root, problem.path) catch {
                  _ => path
                }
              },
              stage,
              message: rejection_message(
                problem.code,
                problem.detail,
                problem.location,
              ),
              details: None,
              problem: Some(Source(problem)),
            })
          }
        Rejected(code, detail, location) =>
          diagnostics.push({
            path: diagnostic_path,
            stage,
            message: rejection_message(code, detail, location),
            details: None,
            problem: Some(
              Source({
                code,
                detail,
                path: relative(job.source_root, diagnostic_path) catch {
                  _ => diagnostic_path
                },
                location,
              }),
            ),
          })
        GenerationFailed(problems) =>
          for problem in problems {
            diagnostics.push({
              path,
              stage: "backend",
              message: problem.code +
              " at " +
              problem.node_path +
              ": " +
              problem.detail,
              details: None,
              problem: Some(Generation(problem)),
            })
          }
        @typing.InferenceFailed(problems) =>
          for problem in problems {
            diagnostics.push({
              path,
              stage: "inference",
              message: problem.display(),
              details: None,
              problem: None,
            })
          }
        e =>
          diagnostics.push({
            path: diagnostic_path,
            stage,
            message: diagnostic_message(e),
            details: None,
            problem: None,
          })
      }
    }
  }
  { processed, artifacts, projects, diagnostics, warnings, }
}

///|
pub fn Plan::sources(self : Plan) -> Array[String] {
  self.sources.copy()
}

///|
pub fn Plan::destinations(self : Plan) -> Array[String] {
  self.destinations.copy()
}
