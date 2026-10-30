///|
pub(all) suberror Invalid {
  Invalid(String)
}

///|
/// Values and merge decisions belong to Moon-Lander. The origin projection keeps
/// Morphir's existing path strings at command and Workbench boundaries.
pub(all) struct Document {
  priv configuration : @lander.Config
  provenance : Map[String, String]
}

///|
pub fn from_framework(configuration : @lander.Config) -> Document {
  let provenance = Map([])
  for (key, origins) in configuration.provenance() {
    if origins.last() is Some(origin) {
      provenance[key.to_string()] = origin.location.unwrap_or(origin.source)
    }
  }
  { configuration, provenance, }
}

///|
pub fn Document::framework(self : Document) -> @lander.Config {
  self.configuration
}

///|
/// Project already resolved host documents into framework file sources without
/// losing a winning leaf's original file. No merge decision is repeated here.
pub fn Document::sources(
  self : Document,
  role : @lander.FileRole,
  priority : Int32,
  fallback : String,
) -> Array[@lander.ConfigSource] raise @lander.ConfigError {
  let groups : Map[String, Array[(String, @lander.ConfigValue)]] = Map([])
  for (key, _) in self.configuration.provenance() {
    if self.configuration.get(key) is Some(value) {
      let path = self.provenance.get(key.to_string()).unwrap_or(fallback)
      let pairs = groups.get(path).unwrap_or([])
      pairs.push((key.to_string(), value))
      groups[path] = pairs
    }
  }
  fn empty_tables(
    value : @ion.Ion,
    names : Array[String],
  ) -> Unit raise @lander.ConfigError {
    if value.kind() is Struct(fields) {
      if fields.is_empty() && !names.is_empty() {
        let pairs = groups.get(fallback).unwrap_or([])
        pairs.push(
          (@lander.KeyPath::from_names(names).to_string(), @lander.fields([])),
        )
        groups[fallback] = pairs
      } else {
        for field in fields {
          empty_tables(field.value(), [..names, field.name().text().unwrap()])
        }
      }
    }
  }
  empty_tables(self.value().to_ion(), [])
  let names = groups.keys().collect()
  names.sort()
  names.map(path => {
    let value = @lander.build([@lander.ConfigSource::overrides(groups[path])]).value()
    @lander.ConfigSource::parsed_file(path, value, role~, priority~)
  })
}

///|
pub fn Document::value(self : Document) -> @lander.ConfigValue {
  self.configuration.value()
}

///|
pub fn parse(text : String, origin~ : String = "<memory>") -> Document raise {
  from_framework(
    @lander.build([
      @lander.ConfigSource::parsed_file(
        origin,
        @lander_toml.parse(text, origin~),
      ),
    ]),
  ) catch {
    error => raise Invalid(error.message())
  }
}

///|
pub fn empty() -> Document {
  from_framework(@lander.build([])) catch {
    _ => abort("empty configuration")
  }
}

///|
pub fn from_json(
  value : Json,
  origin~ : String = "<overlay>",
) -> Document raise {
  from_framework(
    @lander.build([
      @lander.ConfigSource::parsed_file(
        origin,
        @lander.ConfigValue::from_json(value, origin~),
      ),
    ]),
  ) catch {
    error => raise Invalid(error.message())
  }
}

///|
pub fn Document::get(self : Document, path : String) -> @ion.Ion? {
  let key = @lander.KeyPath::parse(path) catch { _ => return None }
  self.configuration.get(key).map(value => value.to_ion())
}

///|
pub fn Document::json(self : Document, path : String) -> Json? raise {
  let value = if path == "" {
    Some(self.value().to_ion())
  } else {
    self.get(path)
  }
  value.map(value => @ion_json.to_json(value)) catch {
    error =>
      raise Invalid(
        "Cannot represent configuration as JSON at " +
        path +
        ": " +
        error.message(),
      )
  }
}

///|
pub fn Document::text(
  self : Document,
  path : String,
  fallback : String,
) -> String raise {
  match self.get(path) {
    None => fallback
    Some(value) =>
      match value.kind() {
        String(text) => text
        _ => raise Invalid("Expected string at " + path)
      }
  }
}

///|
pub fn Document::strings(self : Document, path : String) -> Array[String] raise {
  match self.get(path) {
    None => []
    Some(value) =>
      match value.kind() {
        List(items) =>
          items.map(item => {
            match item.kind() {
              String(text) => text
              _ => raise Invalid("Expected string array at " + path)
            }
          })
        _ => raise Invalid("Expected array at " + path)
      }
  }
}

///|
pub fn Document::boolean(
  self : Document,
  path : String,
  fallback : Bool,
) -> Bool raise {
  match self.get(path) {
    None => fallback
    Some(value) =>
      match value.kind() {
        Bool(flag) => flag
        _ => raise Invalid("Expected boolean at " + path)
      }
  }
}

///|
/// Compatibility composition delegates all value and provenance decisions to
/// the framework, then projects the winning source back to its original label.
pub fn merge(base : Document, overlay : Document) -> Document raise {
  let resolved = @lander.build([
    @lander.ConfigSource::parsed_file("base", base.value(), priority=0),
    @lander.ConfigSource::parsed_file("overlay", overlay.value(), priority=1),
  ]) catch {
    error => raise Invalid(error.message())
  }
  let document = from_framework(resolved)
  for (key, origins) in resolved.provenance() {
    let path = key.to_string()
    let source = if origins.last().map(origin => origin.location) ==
      Some(Some("overlay")) {
      overlay
    } else {
      base
    }
    if source.provenance.get(path) is Some(origin) {
      document.provenance[path] = origin
    }
  }
  document
}

///|
pub fn environment(values : Map[String, String]) -> Document raise {
  from_framework(
    @lander.build([
      @lander.ConfigSource::env(
        prefix="MORPHIR",
        reserved=["MORPHIR_HOME", "MORPHIR_PROFILES"],
        selection=Explicit(values),
      ),
    ]),
  ) catch {
    error => raise Invalid(error.message())
  }
}

///|
pub fn Document::shared(self : Document) -> Document raise {
  let source = @lander.ConfigSource::parsed_file("inherited", self.value()).exclude(
    [@lander.KeyPath::parse("project"), @lander.KeyPath::parse("workspace")],
    warn=false,
  )
  let result = from_framework(@lander.build([source]))
  for path, _ in result.provenance {
    if self.provenance.get(path) is Some(origin) {
      result.provenance[path] = origin
    }
  }
  result
}

///|
/// TOML remains the only written format. This is a representation adapter for
/// the writer, not a configuration parser or merge engine.
fn written_value(value : @ion.Ion) -> @toml.TomlValue raise {
  match value.kind() {
    String(text) =>
      if value
        .annotations()
        .any(annotation => annotation.text() == Some("toml_local_time")) {
        match @toml.parse("value = " + text) {
          TomlTable(fields) => fields["value"]
          _ => raise Invalid("Invalid TOML local time")
        }
      } else {
        @toml.TomlString(text)
      }
    Int(number) => {
      let narrowed = number.to_int64()
      guard narrowed.to_string() == number.to_string() else {
        raise Invalid("Integer is outside the TOML range")
      }
      @toml.TomlInteger(narrowed)
    }
    Float(number) => @toml.TomlFloat(number)
    Bool(flag) => @toml.TomlBoolean(flag)
    List(items) => @toml.TomlArray(items.map(written_value))
    Struct(fields) => {
      let result = Map([])
      for field in fields {
        result[field.name().text().unwrap()] = written_value(field.value())
      }
      @toml.TomlTable(result)
    }
    Timestamp(_) =>
      match @toml.parse("value = " + @ion_text.write_ion(value)) {
        TomlTable(fields) => fields["value"]
        _ => raise Invalid("Invalid TOML timestamp")
      }
    _ => raise Invalid("Configuration value cannot be written as TOML")
  }
}

///|
pub fn Document::encode(self : Document) -> String raise {
  written_value(self.value().to_ion()).to_string()
}

///|
pub fn Document::validate(self : Document) -> Unit raise {
  for
    section in [
      "workspace", "project", "frontend", "ir", "pipeline", "backends",
    ] {
    match self.get(section) {
      None => ()
      Some(value) if value.kind() is Struct(_) => ()
      _ => raise Invalid("Expected table at " + section)
    }
  }
  for
    path in [
      "workspace.name", "workspace.root", "workspace.out_dir", "workspace.default_member",
      "project.name", "project.version", "project.source_directory", "project.module_prefix",
      "frontend.language", "frontend.provider", "frontend.profile", "ir.layout",
      "ir.format", "ir.mode", "pipeline.backend", "pipeline.checkpoint_format", "pipeline.inference",
    ] {
    ignore(self.text(path, ""))
  }
  for
    path in [
      "workspace.members", "workspace.exclude", "project.exposed_modules", "project.authors",
    ] {
    ignore(self.strings(path))
  }
  ignore(self.boolean("ir.strict_mode", false))
  ignore(self.boolean("pipeline.strict_naming", false))
  ignore(self.metadata_provider_request())
}
