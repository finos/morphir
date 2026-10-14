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
  cancelled? : () -> Bool = fn() { false },
  bind_runtime? : (@scheme.Runtime) -> Unit raise = fn(_) { () },
  codecs? : @data.Registry? = None,
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
    if !checkpoint && frontend is Some(f) && f.compiler is UnitCompiler(_, _) {
      raise @configuration.Invalid(
        "frontend.typed_backend_required: Rich source units require checkpoint or generation output",
      )
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
      if !settings.transforms.is_empty() || exposed is Some(_) {
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
    let source_root = match request.directory {
      Some(directory) => normalize(directory)
      None => join(selected.root, settings.source)
    }
    if !owned(source_root) {
      raise @configuration.Invalid(
        "Input directory belongs to another workspace project",
      )
    }
    if !@workspace.within(selected.root, source_root) {
      raise @configuration.Invalid(
        "Input directory is outside selected project",
      )
    }
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
      unique.push(path)
      sources.push(path)
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
    jobs.push({
      root: selected.root,
      source_root,
      destination: output,
      paths: unique,
      settings,
      module_prefix,
      exposed,
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
    })
  }
  { jobs, consumed: false, sources, destinations, output_root, }
}

///|
pub fn Engine::execute_content(
  _self : Engine,
  plan : Plan,
  read : (String, Bool) -> @data.Content raise,
  cancelled? : () -> Bool = fn() { false },
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
        },
      ],
    }
  }
  plan.consumed = true
  for job in plan.jobs {
    job.runtime.set_cancelled(cancelled)
    for path in job.paths {
      let mut stage = "read"
      try {
        if cancelled() {
          raise @configuration.Invalid("Cancelled")
        }
        let relative_path = relative(job.source_root, path)
        let content = read(path, job.read_bytes)
        let unit_id = stem(relative_path)
        stage = "frontend"
        let mut checkpoint_unit = match job.boundary {
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
          let source = Source::{
            path,
            relative_path,
            content: match content {
              Text(text) => text
              Binary(_) =>
                raise @configuration.Invalid(
                  "data.encoding_mismatch: Expected text frontend content",
                )
            },
            package_name: job.settings.package_name,
            module_name: if job.module_prefix == "" {
              stem(relative_path)
            } else {
              job.module_prefix + "/" + stem(relative_path)
            },
          }
          checkpoint_unit = Some(
            job.frontend.unwrap().compile_unit(source, unit_id, cancelled),
          )
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
          None => @data.Text((job.backend.unwrap().emit)(ir))
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
          path: join(job.destination, stem(relative_path) + job.suffix),
          source: path,
          content,
          format: match job.boundary {
            Some(b) => b.output.codec
            None => job.settings.backend
          },
        })
      } catch {
        @typing.InferenceFailed(problems) =>
          for problem in problems {
            diagnostics.push({
              path,
              stage: "inference",
              message: problem.display(),
              details: None,
            })
          }
        e =>
          diagnostics.push({
            path,
            stage,
            message: diagnostic_message(e),
            details: None,
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
