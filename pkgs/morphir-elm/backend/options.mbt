///|
pub(all) enum Profile {
  Model
  Literal
} derive(Eq, Debug)

///|
pub extend Profile with Eq::{equal, not_equal}

///|
pub extend Profile with @debug.Debug::{to_repr}

///|
pub(all) enum Placeholders {
  Refuse
  DebugTodo
} derive(Eq, Debug)

///|
pub extend Placeholders with Eq::{equal, not_equal}

///|
pub extend Placeholders with @debug.Debug::{to_repr}

///|
pub(all) struct ElmPackageRef {
  name : String
  version : String
} derive(Eq, Debug)

///|
pub extend ElmPackageRef with Eq::{equal, not_equal}

///|
pub extend ElmPackageRef with @debug.Debug::{to_repr}

///|
fn is_decimal(text : String) -> Bool {
  !text.is_empty() && text.iter().all(c => c >= '0' && c <= '9')
}

///|
pub fn ElmPackageRef::parse(
  text : String,
  at : String,
) -> ElmPackageRef raise ElmGenerationError {
  let parts = text.split(" ").map(p => p.to_owned()).collect()
  guard parts is [name, version] &&
    name.split("/").collect() is [author, project] &&
    !author.is_empty() &&
    !project.is_empty() &&
    version.split(".").count() == 3 &&
    version.split(".").all(n => is_decimal(n.to_owned())) else {
    refuse(
      "invalid_option",
      at,
      "expected \"author/name 1.2.3\", got \"" + text + "\"",
    )
  }
  { name, version, }
}

///|
pub fn ElmPackageRef::range(self : ElmPackageRef) -> String {
  let major = @parse.parse_int(self.version.split(".").collect()[0].to_owned()) catch {
    _ => panic()
  }
  self.version + " <= v < " + (major + 1).to_string() + ".0.0"
}

///|
pub(all) struct Options {
  profile : Profile
  placeholders : Placeholders
  width : Int32
  elm_package : ElmPackageRef
  mapping : Mapping
  packages : Map[String, ElmPackageRef]
  warnings : Array[String]
}

///|
pub fn Options::default() -> Options {
  {
    profile: Model,
    placeholders: Refuse,
    width: 120,
    elm_package: { name: "finos/morphir-elm", version: "22.0.2", },
    mapping: Mapping::builtin(),
    packages: Map([]),
    warnings: [],
  }
}

///|
fn text_option(
  fields : Map[String, Json],
  key : String,
) -> String? raise ElmGenerationError {
  match fields.get(key) {
    None => None
    Some(String(text)) => Some(text)
    Some(_) => refuse("invalid_option", "backends.elm." + key, "expected text")
  }
}

///|
pub fn Options::from_json(json : Json) -> Options raise ElmGenerationError {
  guard json is Object(fields) else {
    refuse("invalid_option", "backends.elm", "expected a table")
  }
  for key, _ in fields {
    if ![
        "profile", "placeholders", "width", "elm_package", "mapping", "packages",
      ].contains(key) {
      refuse("invalid_option", "backends.elm." + key, "unknown option")
    }
  }
  let profile = match text_option(fields, "profile") {
    None | Some("model") => Model
    Some("literal") => Literal
    Some(other) =>
      refuse(
        "invalid_option",
        "backends.elm.profile",
        "unknown profile " + other,
      )
  }
  let placeholders = match text_option(fields, "placeholders") {
    None | Some("refuse") => Refuse
    Some("debug-todo") => DebugTodo
    Some(other) =>
      refuse(
        "invalid_option",
        "backends.elm.placeholders",
        "unknown policy " + other,
      )
  }
  let width = match fields.get("width") {
    None => 120
    Some(Number(n, ..)) if n >= 1.0 && n <= 1000.0 && n == n.floor() =>
      n.to_int()
    Some(_) =>
      refuse(
        "invalid_option", "backends.elm.width", "expected an integer from 1 to 1000",
      )
  }
  let elm_package = match text_option(fields, "elm_package") {
    None => Options::default().elm_package
    Some(text) => ElmPackageRef::parse(text, "backends.elm.elm_package")
  }
  let overrides : Map[String, MappingEntry] = Map([])
  match fields.get("mapping") {
    None => ()
    Some(Object(entries)) =>
      for key, value in entries {
        overrides[key] = parse_mapping_entry(key, value)
      }
    Some(_) =>
      refuse("invalid_option", "backends.elm.mapping", "expected a table")
  }
  let packages : Map[String, ElmPackageRef] = Map([])
  match fields.get("packages") {
    None => ()
    Some(Object(entries)) =>
      for key, value in entries {
        let at = "backends.elm.packages." + key
        guard value is Object(entry) &&
          entry.length() == 1 &&
          entry.get("package") is Some(String(text)) else {
          refuse(
            "invalid_option", at, "expected { package = \"author/name 1.2.3\" }",
          )
        }
        packages[key] = ElmPackageRef::parse(text, at)
      }
    Some(_) =>
      refuse("invalid_option", "backends.elm.packages", "expected a table")
  }
  let warnings = []
  if profile is Literal && !overrides.is_empty() {
    warnings.push("backends.elm.mapping is ignored by the literal profile")
  }
  {
    profile,
    placeholders,
    width,
    elm_package,
    mapping: Mapping::builtin().with_overrides(overrides),
    packages,
    warnings,
  }
}

///|
pub fn validate_options(json : Json) -> Unit raise {
  ignore(Options::from_json(json))
}
