///|
pub(all) enum FileRole {
  Source
  ElmManifest
  MorphirManifest
} derive(Eq, Debug)

///|
pub extend FileRole with Eq::{equal, not_equal}

///|
pub extend FileRole with @debug.Debug::{to_repr}

///|
pub(all) struct GeneratedFile {
  path : String
  role : FileRole
  content : String
} derive(Eq, Debug)

///|
pub extend GeneratedFile with Eq::{equal, not_equal}

///|
pub extend GeneratedFile with @debug.Debug::{to_repr}

///|
pub(all) struct ElmDependency {
  name : String
  range : String
} derive(Eq, Debug)

///|
pub extend ElmDependency with Eq::{equal, not_equal}

///|
pub extend ElmDependency with @debug.Debug::{to_repr}

///|
pub(all) struct Output {
  package_name : String
  files : Array[GeneratedFile]
  dependencies : Array[ElmDependency]
  warnings : Array[String]
}

///|
/// Elm package names are `author/project` in lowercase with hyphens.
pub fn elm_package_name(package_name : @ir.Path) -> String {
  let parts = package_name
    .to_names()
    .map(name => name.to_words().join("-").to_lower())
  match parts {
    [] => "morphir/model"
    [single] => "morphir/" + single
    _ => parts[0] + "/" + parts[1:].to_owned().join("-")
  }
}

///|
pub fn generate(
  unit_id : String,
  ir : @ir.IRFile,
  options : Options,
  cancelled~ : () -> Bool = fn() { false },
) -> Output raise ElmGenerationError {
  if ir.required_types().any(@ir.Type::has_union) {
    raise Failed([
      {
        code: "elm.unsupported_type",
        node_path: unit_id,
        detail: "Untagged unions are not supported by Elm generation",
      },
    ])
  }
  let (package_name, inputs) : (@ir.Path, Array[ModuleInput]) = match
    ir.distribution {
    Library(name, _, definition) =>
      (
        name,
        definition.modules
        .iter()
        .map(m => ModuleInput::from_definition(name, m.0, m.1.value, Map([])))
        .collect(),
      )
    Application(name, _, definition, entry_points) =>
      (
        name,
        definition.modules
        .iter()
        .map(m => {
          ModuleInput::from_definition(name, m.0, m.1.value, entry_points)
        })
        .collect(),
      )
    Specs(name, _, spec) =>
      (
        name,
        spec.modules
        .iter()
        .map(m => ModuleInput::from_specification(name, m.0, m.1))
        .collect(),
      )
  }
  let public_modules : Map[String, Bool] = Map([])
  match ir.distribution {
    Library(_, _, definition) | Application(_, _, definition, _) =>
      for m, access in definition.modules {
        if access.access is Public {
          public_modules[m.to_canonical()] = true
        }
      }
    Specs(_, _, spec) =>
      for m, _ in spec.modules {
        public_modules[m.to_canonical()] = true
      }
  }
  let problems = []
  let sources = []
  let mut uses_sdk = false
  let foreign : Map[String, Bool] = Map([])
  for input in inputs {
    if cancelled() {
      problems.push({
        code: "elm.cancelled",
        node_path: unit_id,
        detail: "Cancelled",
      })
      break
    }
    try generate_module(options, input) catch {
      Refused(problem) => problems.push(problem)
      Failed(more) => problems.append(more)
    } noraise {
      module_output => {
        uses_sdk = uses_sdk || module_output.uses_sdk_package
        for p in module_output.foreign_packages {
          foreign[p] = true
        }
        sources.push((input, module_output))
      }
    }
  }
  if !problems.is_empty() {
    raise Failed(problems)
  }
  let dependencies = [{ name: "elm/core", range: "1.0.5 <= v < 2.0.0", }]
  if uses_sdk {
    dependencies.push({
      name: options.elm_package.name,
      range: options.elm_package.range(),
    })
  }
  let foreign_names = foreign.keys().collect()
  foreign_names.sort()
  let warnings = options.warnings.copy()
  for p in foreign_names {
    match options.packages.get(p) {
      Some(elm_package) =>
        dependencies.push({
          name: elm_package.name,
          range: elm_package.range(),
        })
      None =>
        warnings.push(
          "no Elm package is configured for Morphir package " +
          p +
          " (backends.elm.packages)",
        )
    }
  }
  let files = sources.map(s => {
    path: "src/" + s.1.elm_module.join("/") + ".elm",
    role: Source,
    content: s.1.source,
  })
  let exposed = sources
    .filter(s => public_modules.contains(s.0.module_path.to_canonical()))
    .map(s => Json::string(s.1.elm_module.join(".")))
  let exposed_all = if exposed.is_empty() {
    sources.map(s => Json::string(s.1.elm_module.join(".")))
  } else {
    exposed
  }
  let elm_package = elm_package_name(package_name)
  let dependency_object = Map::from_array(
    dependencies.map(d => (d.name, Json::string(d.range))),
  )
  // Elm requires a summary of fewer than 80 bytes. Canonical names are ASCII.
  let summary_text = "Morphir model " + package_name.to_canonical()
  let summary = if summary_text.length() > 79 {
    summary_text[:79].to_owned()
  } else {
    summary_text
  }
  let elm_json = Json::object(
    Map::from_array([
      ("type", Json::string("package")),
      ("name", Json::string(elm_package)),
      ("summary", Json::string(summary)),
      ("license", Json::string("Apache-2.0")),
      ("version", Json::string("1.0.0")),
      ("exposed-modules", Json::array(exposed_all)),
      ("elm-version", Json::string("0.19.0 <= v < 0.20.0")),
      ("dependencies", Json::object(dependency_object)),
      ("test-dependencies", Json::object(Map([]))),
    ]),
  )
  let package_module = module_name(package_name, @ir.Path::from_names([]))
  let morphir_json = Json::object(
    Map::from_array([
      ("name", Json::string(package_module.join("."))),
      ("sourceDirectory", Json::string("src")),
      (
        "exposedModules",
        Json::array(
          exposed_all.map(m => {
            guard m is String(text) else { panic() }
            Json::string(
              text[package_module.join(".").length() + 1:].to_owned(),
            )
          }),
        ),
      ),
    ]),
  )
  files.push({
    path: "elm.json",
    role: ElmManifest,
    content: elm_json.stringify(indent=4) + "\n",
  })
  files.push({
    path: "morphir.json",
    role: MorphirManifest,
    content: morphir_json.stringify(indent=4) + "\n",
  })
  { package_name: elm_package, files, dependencies, warnings, }
}
