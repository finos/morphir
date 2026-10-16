///|
pub(all) enum BuildPolicy {
  SourceOnly
  Required(String)
} derive(Eq, Debug)

///|
pub extend BuildPolicy with Eq::{equal, not_equal}

///|
pub extend BuildPolicy with @debug.Debug::{to_repr}

///|
pub(all) struct ProjectDependency {
  module_name : String
  version : String
  api_profile : String
  semantic_pin : String
}

///|
pub(all) struct GeneratedFile {
  path : String
  content : @data.Content
  format : String
}

///|
pub(all) struct GeneratedProject {
  id : String
  root : String
  members : Array[String]
  dependencies : Array[ProjectDependency]
  build_contract : String
}

///|
pub(all) struct GenerationBatch {
  warnings : Array[String]
  structured_warnings : Array[@diagnostics.Warning]
  files : Array[GeneratedFile]
  projects : Array[GeneratedProject]
}

///|
/// `targets` lists the build targets of `pipeline.validation = "required"`. An empty list means source-only.
pub(all) struct GenerationBackend {
  generate : (@data.IRUnit, Json, () -> Bool) -> GenerationBatch raise
  write_bytes : Bool
  validate_options : (Json) -> Unit raise
  targets : Array[String]
}

///|
pub(all) struct LibraryProject {
  id : String
  source : String
  root : String
  members : Array[String]
  dependencies : Array[ProjectDependency]
  build_contract : String
  policy : BuildPolicy
}

///|
pub fn Engine::register_generation_backend(
  self : Engine,
  name : String,
  backend : GenerationBackend,
) -> Unit raise {
  if name == "" ||
    name == "checkpoint" ||
    self.backends.contains(name) ||
    self.generators.contains(name) {
    raise @configuration.Invalid("generation.backend_conflict: " + name)
  }
  self.generators[name] = backend
}

///|
/// A generation backend refused the unit. Each problem names the IR node.
pub(all) suberror GenerationFailed {
  GenerationFailed(Array[GenerationProblem])
}

///|
fn elm_problems(problems : Array[@elm.Problem]) -> GenerationFailed {
  GenerationFailed(
    problems.map(p => {
      code: p.code,
      node_path: p.node_path,
      detail: p.detail,
    }),
  )
}

///|
fn moonbit_generation(
  unit : @data.IRUnit,
  options : Json,
  cancelled : () -> Bool,
  metadata_capabilities : @linked_metadata.Capabilities,
) -> GenerationBatch raise {
  let result = @moonbit.generate(
    {
      unit_id: unit.id,
      ir: unit.distribution,
      metadata: unit.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: unit.annotations,
      provenance: unit.provenance,
    },
    naming=moonbit_naming_style(options),
    metadata_capabilities~,
    cancelled~,
  ) catch {
    @moonbit.Invalid(code, node_path, detail) =>
      raise GenerationFailed([{ code, node_path, detail, }])
    error => raise error
  }
  {
    warnings: [],
    structured_warnings: result.warnings,
    files: result.artifacts.map(a => {
      path: a.path,
      content: match a.content {
        Text(t) => @data.Text(t)
        Binary(b) => @data.Binary(b)
      },
      format: match a.role {
        Source => "moonbit-source"
        ModuleManifest | PackageManifest => "moonbit-manifest"
        Metadata => "ion-binary"
      },
    }),
    projects: [
      {
        id: result.project.module_name,
        root: result.project.root,
        members: result.project.members,
        dependencies: result.project.dependencies.map(d => {
          module_name: d.module_name,
          version: d.version,
          api_profile: d.api_profile,
          semantic_pin: d.semantic_pin,
        }),
        build_contract: "moonbit-library-v1",
      },
    ],
  }
}

///|
fn elm_generation(
  unit : @data.IRUnit,
  options : Json,
  cancelled : () -> Bool,
) -> GenerationBatch raise {
  let output = @elm.generate(
    unit.id,
    unit.distribution,
    @elm.Options::from_json(options),
    cancelled~,
  ) catch {
    Failed(problems) => raise elm_problems(problems)
    Refused(p) => raise elm_problems([p])
  }
  {
    warnings: output.warnings,
    structured_warnings: [],
    files: output.files.map(f => {
      path: f.path,
      content: @data.Text(f.content),
      format: match f.role {
        Source => "elm-source"
        ElmManifest => "elm-manifest"
        MorphirManifest => "morphir-manifest"
      },
    }),
    projects: [
      {
        id: output.package_name,
        root: "",
        members: output.files.map(f => f.path),
        dependencies: output.dependencies.map(d => {
          module_name: d.name,
          version: d.range,
          api_profile: "elm-package",
          semantic_pin: "",
        }),
        build_contract: "elm-package-v1",
      },
    ],
  }
}

///|
/// The elm backend reports option problems as configuration errors, so the engine needs no Elm types.
fn elm_validate_options(options : Json) -> Unit raise {
  @elm.validate_options(options) catch {
    @elm.ElmGenerationError::Refused(p) =>
      raise @configuration.Invalid(
        p.code + " at " + p.node_path + ": " + p.detail,
      )
    @elm.ElmGenerationError::Failed(problems) =>
      raise @configuration.Invalid(
        problems
        .map(p => p.code + " at " + p.node_path + ": " + p.detail)
        .join("\n"),
      )
    other => raise other
  }
}

///|
/// The naming option selects a documented generation policy; other options remain ignored.
fn moonbit_naming_style(options : Json) -> @moonbit.NamingStyle raise {
  guard options is Object(fields) else {
    raise @configuration.Invalid("backends.moonbit must be a table")
  }
  match fields.get("naming") {
    None | Some(String("readable")) => @moonbit.Readable
    Some(String("legacy-hex")) => @moonbit.LegacyHex
    _ =>
      raise @configuration.Invalid(
        "backends.moonbit.naming must be 'readable' or 'legacy-hex'",
      )
  }
}

///|
fn moonbit_validate_options(options : Json) -> Unit raise {
  ignore(moonbit_naming_style(options))
}

///|
fn portable_path(path : String, allow_empty~ : Bool = false) -> Unit raise {
  if (path == "" && !allow_empty) ||
    normalize(path) != path ||
    path.contains(":") ||
    path.contains("\\") ||
    path.contains("\u0000") {
    raise @configuration.Invalid("generation.invalid_path: " + path)
  }
  for part in path.split("/") {
    if part.has_suffix(".") ||
      part.has_suffix(" ") ||
      part.to_owned().to_array().any(c => c.to_int() < 32 || c.to_int() > 126) {
      raise @configuration.Invalid("generation.nonportable_path: " + path)
    }
  }
}

///|
fn validate_batch(
  batch : GenerationBatch,
  base : String,
  source : String,
  policy : BuildPolicy,
  artifacts : Array[ContentArtifact],
  projects : Array[LibraryProject],
) -> Unit raise {
  let seen = Map([])
  for file in batch.files {
    portable_path(file.path)
    let key = file.path.to_lower()
    if seen.contains(key) ||
      seen
      .keys()
      .any(existing => {
        @workspace.within(existing, key) || @workspace.within(key, existing)
      }) {
      raise @configuration.Invalid("generation.path_collision: " + file.path)
    }
    seen[key] = true
  }
  let roots = []
  let members = Map([])
  let ids = Map([])
  for project in batch.projects {
    portable_path(project.root, allow_empty=true)
    if project.id == "" ||
      ids.contains(project.id) ||
      project.build_contract == "" {
      raise @configuration.Invalid("generation.invalid_project: " + project.id)
    }
    ids[project.id] = true
    let key = project.root.to_lower()
    if roots.any(r => @workspace.within(r, key) || @workspace.within(key, r)) {
      raise @configuration.Invalid(
        "generation.project_overlap: " + project.root,
      )
    }
    roots.push(key)
    if project.members.is_empty() {
      raise @configuration.Invalid("generation.empty_project: " + project.id)
    }
    for member_path in project.members {
      portable_path(member_path)
      let path = join(project.root, member_path)
      if !batch.files.any(f => f.path == path) || members.contains(path) {
        raise @configuration.Invalid("generation.invalid_membership: " + path)
      }
      members[path] = true
    }
  }
  if members.length() != batch.files.length() || batch.projects.is_empty() {
    raise @configuration.Invalid("generation.unclaimed_artifact")
  }
  for file in batch.files {
    artifacts.push({
      path: join(base, file.path),
      source,
      content: file.content,
      format: file.format,
    })
  }
  for project in batch.projects {
    projects.push({
      id: project.id,
      source,
      root: join(base, project.root),
      members: project.members.map(m => join(join(base, project.root), m)),
      dependencies: project.dependencies.copy(),
      build_contract: project.build_contract,
      policy,
    })
  }
}
