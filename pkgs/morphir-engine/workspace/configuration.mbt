///|
/// Host controls are separate from the existing workspace wire request.
pub(all) struct ConfigurationOptions {
  directory : @lander.FileTreePath
  selected : String?
  profiles : @lander.ProfileSelection
  isolated : Bool
  suppress : Array[String]
  external_files : Map[String, String]
  platform : @lander.Platform
}

///|
pub fn ConfigurationOptions::new(
  directory? : @lander.FileTreePath,
  selected? : String,
  profiles~ : @lander.ProfileSelection = Unspecified,
  isolated~ : Bool = false,
  suppress~ : Array[String] = [],
  external_files~ : Map[String, String] = Map([]),
  platform~ : @lander.Platform = Linux,
) -> ConfigurationOptions {
  let directory = directory.unwrap_or(
    @lander.FileTreePath::parse("/__morphir_workspace") catch {
      _ => abort("workspace path")
    },
  )
  {
    directory,
    selected,
    profiles,
    isolated,
    suppress: suppress.copy(),
    external_files: external_files.copy(),
    platform,
  }
}

///|
let configuration_groups : Array[Array[String]] = [
  ["json", "json5"],
  ["yaml", "yml"],
  ["toml"],
]

///|
/// Morphir owns names and policy. All directory discovery and ambiguity checks
/// are performed by the published conventions and candidate source APIs.
pub fn configuration_conventions(
  boundary? : String,
) -> @conventions.Conventions raise @lander.ConfigError {
  let groups = configuration_groups.mapi((index, extensions) => {
    let extensions = extensions.map(@conventions.Extension::parse)
    if index == 0 {
      @conventions.FormatGroup::new(
        extensions,
        supplemental=@conventions.SupplementalFile::new(
          "morphir-workspace.json",
          @conventions.Extension::parse("json"),
        ),
      )
    } else {
      @conventions.FormatGroup::new(extensions)
    }
  })
  let result = @conventions.app_dirs("morphir", display="Morphir")
    |> @conventions.without(LocalOverrides)
    |> @conventions.format_layers(@conventions.FormatLayers::new(groups))
    |> @conventions.root_policy(
      WorkspaceFirst(@lander.KeyPath::parse("workspace")),
    )
    |> @conventions.selected_file_policy(Overlay)
  match boundary {
    Some(path) => result |> @conventions.boundary(path)
    None => result
  }
}

///|
priv struct ConfigurationParsers {
  values : Map[String, @lander.ConfigValue]
  manifests : Map[String, Bool]
  notes : Array[String]
}

///|
fn ConfigurationParsers::new() -> ConfigurationParsers {
  { values: Map([]), manifests: Map([]), notes: [], }
}

///|
fn manifest_error(path : String, detail : String) -> @lander.ConfigError {
  @lander.Parse(
    format="Morphir JSON",
    origin=path,
    message=detail,
    line=None,
    column=None,
  )
}

///|
fn ConfigurationParsers::manifest(
  self : ConfigurationParsers,
  value : @lander.ConfigValue,
  path : String,
) -> @lander.ConfigValue raise @lander.ConfigError {
  let json = @ion_json.to_json(value.to_ion()) catch {
    _ => raise manifest_error(path, "Expected JSON configuration values")
  }
  guard json is Object(original) else {
    raise manifest_error(path, "Expected configuration object")
  }
  let fields = original.copy()
  let legacy = ["name", "sourceDirectory", "exposedModules"].any(key => {
    fields.contains(key)
  })
  if legacy {
    let project = match fields.get("project") {
      None => Map([])
      Some(Object(project)) => project.copy()
      _ => raise manifest_error(path, "project must be an object")
    }
    for
      (old, canonical) in [
        ("name", "name"),
        ("sourceDirectory", "source_directory"),
        ("exposedModules", "exposed_modules"),
      ] {
      if fields.contains(old) && project.contains(canonical) {
        raise manifest_error(path, old + " conflicts with project." + canonical)
      }
    }
    let name = match fields.get("name") {
      None => "user"
      Some(String(text)) => text
      _ => raise manifest_error(path, "name must be a string")
    }
    ignore(@ids.SourcePackageName::parse(name)) catch {
      _ => raise manifest_error(path, "name must be a valid package name")
    }
    let source = match fields.get("sourceDirectory") {
      None => "src"
      Some(String(text)) => text
      _ => raise manifest_error(path, "sourceDirectory must be a string")
    }
    guard fields.get("exposedModules") is Some(Array(exposed)) else {
      raise manifest_error(
        path, "exposedModules must be a list of module names",
      )
    }
    for item in exposed {
      guard item is String(text) else {
        raise manifest_error(
          path, "exposedModules must be a list of module names",
        )
      }
      ignore(@ids.SourceModuleName::parse(text)) catch {
        _ =>
          raise manifest_error(
            path, "exposedModules must contain valid module names",
          )
      }
    }
    if !project.contains("name") {
      project["name"] = Json::string(name)
    }
    if !project.contains("source_directory") {
      project["source_directory"] = Json::string(source)
    }
    if !project.contains("exposed_modules") {
      project["exposed_modules"] = Json::array(exposed)
    }
    fields["project"] = Json::object(project)
    let frontend = match fields.get("frontend") {
      None => Map([])
      Some(Object(frontend)) => frontend.copy()
      _ => raise manifest_error(path, "frontend must be an object")
    }
    if !frontend.contains("language") {
      frontend["language"] = Json::string("elm")
    }
    fields["frontend"] = Json::object(frontend)
    for name in ["name", "sourceDirectory", "exposedModules"] {
      fields.remove(name)
    }
    self.manifests[path] = true
  }
  for key in ["dependencies", "localDependencies", "decorations"] {
    let present = match fields.get(key) {
      None | Some(Null) => false
      Some(Array(items)) => !items.is_empty()
      Some(Object(items)) => !items.is_empty()
      _ => true
    }
    if present {
      self.notes.push(
        "Ignoring morphir.json " + key + " (not supported): " + path,
      )
    }
    fields.remove(key)
  }
  @lander.ConfigValue::from_json(Json::object(fields), origin=path)
}

///|
fn ConfigurationParsers::formats(
  self : ConfigurationParsers,
) -> Array[@lander.Format] {
  [@json5.format(), @yaml.format(), @toml_format.format()].map(format => {
    ..format,
    parse: (text, path) => {
      if self.values.get(path) is Some(value) {
        return value
      }
      let value = (format.parse)(text, path)
      let value = if format.name == "JSON5" &&
        !path.has_suffix("morphir-workspace.json") {
        self.manifest(value, path)
      } else {
        value
      }
      self.values[path] = value
      value
    },
  })
}

///|
pub fn configuration_formats() -> Array[@lander.Format] {
  ConfigurationParsers::new().formats()
}

///|
fn configuration_path(
  directory : @lander.FileTreePath,
  path : String,
) -> @lander.FileTreePath raise @lander.ConfigError {
  if path == "" {
    directory
  } else {
    directory.join(path)
  }
}

///|
fn config_tree(
  tree : Tree,
  options : ConfigurationOptions,
) -> @lander.FileTree raise @lander.ConfigError {
  let files : Map[@lander.FileTreePath, String] = Map([])
  for path, text in tree.files {
    files[configuration_path(options.directory, path)] = text
  }
  for path, text in options.external_files {
    files[@lander.FileTreePath::parse(path)] = text
  }
  let listings : Map[@lander.FileTreePath, Array[@lander.DirEntry]] = Map([])
  let add = fn(path : @lander.FileTreePath, kind : @lander.EntryKind) {
    if path.parent() is Some(parent) && path.name() is Some(name) {
      let entries = listings.get(parent).unwrap_or([])
      if !entries.any(entry => entry.name == name) {
        entries.push({ name, kind, })
      }
      listings[parent] = entries
    }
  }
  for path, _ in files {
    add(path, File)
    let mut parent = path.parent()
    while parent is Some(directory) {
      add(directory, Directory)
      parent = directory.parent()
    }
  }
  for directory in tree.directories {
    let path = configuration_path(options.directory, directory)
    add(path, Directory)
    if !listings.contains(path) {
      listings[path] = []
    }
  }
  let mut result = @lander.FileTree::new(complete=true)
  for path, text in files {
    result = result.with_file(path, text)
  }
  for path, entries in listings {
    result = result.with_listing(path, entries)
  }
  result
}

///|
fn relative_origin(path : String, directory : @lander.FileTreePath) -> String {
  let prefix = directory.to_string() + "/"
  if path.has_prefix(prefix) {
    path[prefix.length():].to_owned()
  } else {
    path
  }
}

///|
priv struct ConfigurationFile {
  path : String
  value : @lander.ConfigValue
  role : @lander.FileRole
}

///|
fn location_files(
  context : @lander.LoadContext,
  directory : @lander.FileTreePath,
  parsers : ConfigurationParsers,
  isolated : Bool,
) -> Array[ConfigurationFile] raise @lander.ConfigError {
  let conventions = configuration_conventions(boundary=directory.to_string())
    |> @conventions.without(SystemDir)
    |> @conventions.without(UserConfigDir)
    |> @conventions.without(AppHome)
  let builder = context.formats.fold(
      init=@lander.builder()
        |> @lander.working_dir(directory.to_string())
        |> @lander.platform(context.platform.unwrap_or(Linux))
        |> @lander.env_vars(context.env_vars),
      (builder, format) => builder |> @lander.format(format),
    )
    |> @conventions.add(
      conventions,
      options=@conventions.DiscoveryOptions::new(isolated~),
    )
  guard @lander.load(builder, context.tree) is Done(resolved) else {
    raise manifest_error(
      directory.to_string(),
      "Incomplete configuration snapshot",
    )
  }
  resolved
  .reports()
  .filter_map(report => {
    if report.status is Loaded &&
      report.path is Some(path) &&
      report.kind is File(role) &&
      parsers.values.get(path) is Some(value) {
      Some({ path, value, role, })
    } else {
      None
    }
  })
}

///|
fn machine_files(
  context : @lander.LoadContext,
  parsers : ConfigurationParsers,
  isolated : Bool,
) -> Array[ConfigurationFile] raise @lander.ConfigError {
  if isolated {
    return []
  }
  let builder = context.formats.fold(
      init=@lander.builder()
        |> @lander.working_dir(context.working_dir.unwrap().to_string())
        |> @lander.platform(context.platform.unwrap_or(Linux))
        |> @lander.env_vars(context.env_vars),
      (builder, format) => builder |> @lander.format(format),
    )
    |> @conventions.add(
      configuration_conventions(),
      options=@conventions.DiscoveryOptions::new(config=Skip),
    )
  guard @lander.load(builder, context.tree) is Done(resolved) else {
    raise manifest_error("host", "Incomplete host configuration snapshot")
  }
  resolved
  .reports()
  .filter_map(report => {
    if report.status is Loaded &&
      report.path is Some(path) &&
      report.kind is File(role) &&
      parsers.values.get(path) is Some(value) {
      Some({ path, value, role, })
    } else {
      None
    }
  })
}

///|
fn source(
  file : ConfigurationFile,
  role : @lander.FileRole,
  priority : Int32,
  exclude : Array[String],
) -> @lander.ConfigSource raise @lander.ConfigError {
  @lander.ConfigSource::parsed_file(file.path, file.value, role~, priority~).exclude(
    exclude.map(@lander.KeyPath::parse),
    warn=role is Member,
  )
}

///|
fn profile_stems(
  files : Array[ConfigurationFile],
  directory : @lander.FileTreePath,
) -> Array[String] {
  let stems = []
  for file in files {
    if !(file.role is Workspace) {
      continue
    }
    let name = if file.path.has_suffix("morphir-workspace.json") {
      file.path[:file.path.length() - "morphir-workspace.json".length()].to_owned() +
      "morphir"
    } else {
      file.path[:file.path.length() -
      file.path.split(".").last().unwrap().length() -
      1].to_owned()
    }
    if !stems.contains(name) {
      stems.push(name)
    }
  }
  if stems.is_empty() {
    stems.push(directory.to_string() + "/morphir")
  }
  stems
}

///|
priv struct ConfigurationResult {
  document : @config.Document
  primary : @config.Document
  anchor : String
  warnings : Array[String]
}

///|
fn resolve_configuration(
  tree : Tree,
  root : String,
  member_path : String?,
  options : ConfigurationOptions,
  system : @config.Document,
  global : @config.Document,
  environment : Map[String, String],
  overlay : @config.Document,
) -> ConfigurationResult raise @lander.ConfigError {
  let parsers = ConfigurationParsers::new()
  let directory = configuration_path(options.directory, root)
  let context : @lander.LoadContext = {
    tree: config_tree(tree, options),
    working_dir: Some(directory),
    platform: Some(options.platform),
    env_vars: environment,
    formats: parsers.formats(),
  }
  let primaries = location_files(context, directory, parsers, options.isolated)
  let member_directory = member_path.map(path => {
    configuration_path(options.directory, path)
  })
  let member_files = match member_directory {
    Some(path) => location_files(context, path, parsers, options.isolated)
    None => []
  }
  let machine = machine_files(context, parsers, options.isolated)
  let base = primaries.filter(file => file.role is Workspace)
  let own_primary = if member_path is Some(_) {
    member_files.filter(file => file.role is Workspace)
  } else {
    base
  }
  let primary = @config.from_framework(
    @lander.build(own_primary.map(file => source(file, Workspace, 300, []))),
  )

  let variable = environment
    .get("MORPHIR_PROFILES")
    .map(value => ("MORPHIR_PROFILES", value))
  let selection = @profiles.SelectionInput::new(options.profiles, variable?)
  let controls = if selection.disabled() {
    []
  } else {
    base.map(file => {
      @profiles.ControlLayer::new(file.value, {
        kind: File(Workspace),
        source: file.path,
        priority: 300,
        location: Some(file.path),
      })
    })
  }
  let mut resolution = @profiles.resolve_layers(
    @profiles.Policy::new(),
    selection,
    @profiles.ControlLayers::new(controls),
  )
  let selected = options.selected.map(path => {
    let parsed = @lander.FileTreePath::parse(path)
    if parsed.is_absolute() {
      parsed.to_string()
    } else {
      directory.resolve(parsed).to_string()
    }
  })
  if selected is Some(path) && base.any(file => file.path == path) {
    resolution = resolution.with_control_authority({
      kind: File(Explicit),
      source: path,
      priority: 325,
      location: Some(path),
    })
  }
  let defaults = @toml_format.parse(
    "[workspace]\nout_dir = '.morphir/out'\n[frontend]\nlanguage = 'scheme'\n[project]\nsource_directory = 'src'\n[ir]\nformat_version = 4\nlayout = 'single-file'\nformat = 'json'\n",
    origin="defaults",
  )
  let sources = [
    @lander.ConfigSource::defaults_value(defaults, name="defaults", priority=0),
  ]
  let own = if member_path is Some(_) { member_files } else { primaries }
  if own
    .iter()
    .find_first(file => {
      file.role is Workspace && parsers.manifests.contains(file.path)
    })
    is Some(manifest) {
    sources.push(
      @lander.ConfigSource::defaults(
        {
          "pipeline": {
            "backend": "checkpoint",
            "checkpoint_format": "morphir-json",
          },
        },
        name=manifest.path,
        priority=1,
      ),
    )
  }
  if !options.isolated {
    for
      (document, role, priority, name) in [
        (system, @lander.FileRole::System, 100, "system"),
        (global, Global, 200, "global"),
      ] {
      sources.append(
        document
        .sources(role, priority, name)
        .map(source => {
          source.exclude(
            [
              @lander.KeyPath::parse("project"),
              @lander.KeyPath::parse("workspace"),
            ],
            warn=false,
          )
        }),
      )
    }
  }
  for file in machine {
    if selected == Some(file.path) {
      continue
    }
    sources.push(
      source(file, file.role, if file.role is System { 100 } else { 200 }, [
        "project", "workspace",
      ]),
    )
  }
  let inherited = if member_path is Some(_) {
    ["project", "workspace"]
  } else {
    []
  }
  let scoped = ["workspace.out_dir", "workspace.output_dir"]
  for file in base {
    if selected != Some(file.path) {
      sources.push(source(file, Workspace, 300, inherited))
    }
  }
  if selected is Some(path) {
    let value = match context.tree.file(@lander.FileTreePath::parse(path)) {
      Found(text) => @lander.parse_file(context.formats, path, text)
      _ => raise @lander.FileNotFound(path~)
    }
    let as_member = member_files.any(file => file.path == path)
    sources.push(
      source(
        { path, value, role: Explicit, },
        Explicit,
        325,
        if as_member {
          scoped
        } else {
          inherited
        },
      ),
    )
  }
  for file in member_files {
    if file.role is Workspace && selected != Some(file.path) {
      sources.push(source(file, Member, 350, scoped))
    }
  }
  if !resolution.disabled() {
    let root_stems = profile_stems(primaries, directory)
    let member_stems = member_directory
      .map(path => profile_stems(member_files, path))
      .unwrap_or([])
    for name in resolution.active().names() {
      for (stems, filters) in [(root_stems, inherited), (member_stems, scoped)] {
        for group in configuration_groups {
          let paths = stems
            .map(stem => {
              group.map(extension => {
                stem + ".profile." + name.to_string() + "." + extension
              })
            })
            .flatten()
          if !paths.is_empty() {
            sources.push(
              @lander.ConfigSource::candidates(
                paths,
                display="Morphir profile " + name.to_string(),
                role=ProfileFile(name),
                priority=380,
              ).exclude(
                [
                  ..filters, "workspace.root", "workspace.members", "workspace.exclude",
                  "workspace.default_member",
                ].map(@lander.KeyPath::parse),
                warn=false,
              ),
            )
          }
        }
      }
    }
  }
  for (files, filters) in [(primaries, inherited), (member_files, scoped)] {
    for file in files {
      if file.role is UserOverride && selected != Some(file.path) {
        sources.push(source(file, UserOverride, 400, filters))
      }
    }
  }
  sources.push(
    @lander.ConfigSource::env(
      prefix="MORPHIR",
      reserved=["MORPHIR_HOME", "MORPHIR_PROFILES"],
      selection=Explicit(environment),
      priority=600,
    ),
  )
  sources.push(
    @lander.ConfigSource::overrides_value(
      overlay.value(),
      name="CLI",
      priority=700,
    ),
  )
  let builder = context.formats.fold(
      init=@lander.builder() |> @lander.working_dir(directory.to_string()),
      (builder, format) => builder |> @lander.format(format),
    )
    |> @lander.provider({
      name: "Morphir configuration",
      expand: _ => Done(@lander.Expansion::new(sources, profiles=resolution)),
    })
  guard @lander.load(builder, context.tree) is Done(configuration) else {
    raise manifest_error(
      directory.to_string(),
      "Incomplete configuration snapshot",
    )
  }
  let document = @config.from_framework(configuration)
  for path, origin in document.provenance {
    document.provenance[path] = relative_origin(origin, options.directory)
  }
  let warnings = parsers.notes.map(note => {
    note.replace_all(old=options.directory.to_string() + "/", new="")
  })
  let suppressed = options.suppress.copy()
  for
    value in environment
    .get("MORPHIR_DIAGNOSTICS__SUPPRESS")
    .unwrap_or("")
    .split(",") {
    if value.trim() != "" {
      suppressed.push(value.trim().to_owned())
    }
  }
  let host_values = @config.from_framework(
    @lander.build(
      machine.map(file => {
        source(file, file.role, if file.role is System { 100 } else { 200 }, [])
      }),
    ),
  )
  for host in [system, global, host_values] {
    if host.get("diagnostics.suppress") is Some(_) {
      let codes : Array[String] = @lander.bind(
        host.framework(),
        "diagnostics.suppress",
      )
      suppressed.append(codes)
    }
  }
  for code in suppressed {
    if !["config.yaml_beside_toml", "config.json_keys_below_toml"].contains(
        code,
      ) &&
      !warnings.contains("Unknown configuration warning code: " + code) {
      warnings.push("Unknown configuration warning code: " + code)
    }
  }
  for files in [primaries, member_files] {
    let base = files.filter(file => file.role is Workspace)
    let tomls = base.filter(file => file.path.has_suffix(".toml"))
    if tomls.is_empty() {
      continue
    }
    if !suppressed.contains("config.yaml_beside_toml") {
      for
        yaml in base.filter(file => {
          file.path.has_suffix(".yaml") || file.path.has_suffix(".yml")
        }) {
        warnings.push(
          "config.yaml_beside_toml: " +
          relative_origin(yaml.path, options.directory) +
          " beside " +
          relative_origin(tomls[0].path, options.directory),
        )
      }
    }
    if !suppressed.contains("config.json_keys_below_toml") {
      let merged = @lander.build(
        base.map(file => source(file, Workspace, 300, [])),
      )
      for
        json in base.filter(file => {
          file.path.has_suffix(".json") || file.path.has_suffix(".json5")
        }) {
        let keys = merged
          .provenance()
          .filter_map(pair => {
            if !pair.0.to_string().has_prefix("profiles.") &&
              pair.1.last().map(origin => origin.location) ==
              Some(Some(json.path)) {
              Some(pair.0.to_string())
            } else {
              None
            }
          })
        if !keys.is_empty() {
          warnings.push(
            "config.json_keys_below_toml: " +
            relative_origin(json.path, options.directory) +
            " supplies " +
            keys.join(", "),
          )
        }
      }
    }
  }
  let anchor = own
    .filter(file => file.role is Workspace)
    .last()
    .map(file => relative_origin(file.path, options.directory))
    .unwrap_or("")
  { document, primary, anchor, warnings, }
}
