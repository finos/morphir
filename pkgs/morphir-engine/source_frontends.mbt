///|
priv enum SourceCompiler {
  FileCompiler((Source) -> @ir.IRFile raise)
  UnitCompiler((Source, String, () -> Bool) -> @data.IRUnit raise, @data.Limits)
  ProjectCompiler(
    (ProjectSources, String, () -> Bool) -> @data.IRUnit raise,
    @data.Limits
  )
}

///|
/// One problem of a project compiler. `path` is relative to the source directory; it is empty for a problem of the
/// whole project.
pub(all) struct SourceProblem {
  code : String
  detail : String
  path : String
  location : @ir.SourceLocation?
}

///|
/// Source adapters translate their errors without adding a parser dependency to core. A project compiler reports
/// all of its problems with `RejectedSources`.
pub(all) suberror SourceFrontendError {
  Rejected(String, String, @ir.SourceLocation?)
  RejectedSources(Array[SourceProblem])
}

///|
/// A description of a selected source compiler, without reading model bodies.
pub(all) struct SourceFrontendSelection {
  source : String
  unit_id : String
  frontend : String
  language : String
  provider : String
  profile : String?
  default_profile : Bool
  available_profiles : Array[String]
  capabilities : SourceCapabilities?
  evidence : SourceEvidence
  dependencies : Map[String, String]
  output_contract : String
}

///|
/// Unit callbacks receive canonical package/module names and a host-owned logical
/// ID. They run only during execution. Registrations are fixed in each plan.
pub fn Engine::register_unit_frontend(
  self : Engine,
  name : String,
  extensions : Array[String],
  compile : (Source, String, () -> Bool) -> @data.IRUnit raise,
  profile? : String? = None,
  dependencies? : Map[String, String] = Map([]),
  limits? : @data.Limits = @data.Limits::default(),
) -> Unit raise {
  if name == "" ||
    self.frontends.contains(name) ||
    self.source_providers.contains(name) ||
    self.data_formats.contains(name) {
    raise @configuration.Invalid("frontend.registration_conflict: " + name)
  }
  if extensions.is_empty() ||
    !extensions.all(s => {
      s.length() > 1 &&
      s.has_prefix(".") &&
      !s.contains("/") &&
      !s.contains("\\") &&
      !s.contains(":") &&
      !s.contains("\u0000")
    }) {
    raise @configuration.Invalid("frontend.invalid_extensions: " + name)
  }
  if limits.max_bytes <= 0 || limits.max_depth < 0 || limits.max_values <= 0 {
    raise @data.Invalid(
      "data.invalid_limits", "Source unit limits must be positive",
    )
  }
  self.frontends[name] = {
    extensions: extensions.copy(),
    compiler: UnitCompiler(compile, limits),
    profile,
    dependencies: dependencies.copy(),
    provider: name,
    default_profile: true,
    available_profiles: profile.map(p => [p]).unwrap_or([]),
    capabilities: None,
    evidence: Declared,
  }
}

///|
fn Frontend::compile_unit(
  self : Frontend,
  source : Source,
  unit_id : String,
  cancelled : () -> Bool,
) -> @data.IRUnit raise {
  match self.compiler {
    FileCompiler(run) => @data.IRUnit::new(unit_id, run(source))
    UnitCompiler(run, limits) => {
      let canonical = {
        ..source,
        package_name: canonical_path(source.package_name),
        module_name: canonical_path(source.module_name),
      }
      let unit = run(canonical, unit_id, cancelled) catch {
        Rejected(code, detail, location) =>
          raise Rejected(code, detail + self.context(), location)
        error => raise error
      }
      if unit.id != unit_id {
        raise @data.Invalid("data.unit_mismatch", unit_id)
      }
      unit.validate(limits~)
      unit
    }
    ProjectCompiler(_, _) =>
      raise @configuration.Invalid(
        "frontend.project_compiler: " +
        self.provider +
        " compiles whole projects",
      )
  }
}

///|
/// The provider and profile of a provider frontend, for its diagnostics.
fn Frontend::context(self : Frontend) -> String {
  if self.capabilities is Some(_) {
    " [provider " +
    self.provider +
    "; profile " +
    self.profile.unwrap_or("") +
    "]"
  } else {
    ""
  }
}

///|
fn Frontend::compile_project(
  self : Frontend,
  sources : ProjectSources,
  unit_id : String,
  cancelled : () -> Bool,
) -> @data.IRUnit raise {
  guard self.compiler is ProjectCompiler(run, limits) else {
    raise @configuration.Invalid(
      "frontend.project_compiler: " +
      self.provider +
      " compiles one file at a time",
    )
  }
  let context = self.context()
  let unit = run(sources, unit_id, cancelled) catch {
    Rejected(code, detail, location) =>
      raise Rejected(code, detail + context, location)
    // An empty rejection is still a failed compile; it must not pass without a diagnostic.
    RejectedSources([]) =>
      raise Rejected(
        "frontend.rejected",
        "the compiler reported no problems" + context,
        None,
      )
    RejectedSources(problems) =>
      raise RejectedSources(
        problems.map(p => { ..p, detail: p.detail + context, }),
      )
    error => raise error
  }
  if unit.id != unit_id {
    raise @data.Invalid("data.unit_mismatch", unit_id)
  }
  unit.validate(limits~)
  unit
}

///|
pub fn Plan::source_frontends(self : Plan) -> Array[SourceFrontendSelection] {
  let result = []
  for job in self.jobs {
    // Codec-backed inputs already have BoundarySelection descriptors.
    if job.boundary is Some(b) && b.input is Some(_) {
      continue
    }
    if job.frontend is Some(frontend) {
      for source in job.paths {
        result.push({
          source,
          unit_id: match job.project {
            Some(project) => project.unit_id
            None =>
              stem(
                if job.source_root == "" {
                  source
                } else {
                  source[job.source_root.length() + 1:].to_owned()
                },
              )
          },
          frontend: job.settings.frontend,
          language: job.settings.frontend,
          provider: frontend.provider,
          profile: frontend.profile,
          default_profile: frontend.default_profile,
          available_profiles: frontend.available_profiles.copy(),
          capabilities: frontend.capabilities.map(SourceCapabilities::snapshot),
          evidence: frontend.evidence,
          dependencies: frontend.dependencies.copy(),
          output_contract: match frontend.compiler {
            FileCompiler(_) => "ir-file"
            UnitCompiler(_, _) => "ir-unit"
            ProjectCompiler(_, _) => "ir-project"
          },
        })
      }
    }
  }
  result
}
