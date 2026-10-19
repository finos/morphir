///|
/// A pure document tree has relative physical paths and original UTF-8 text.
/// Files outside pkg/ and deps/ are ignored apart from the root manifest.
priv struct TreeReader {
  files : Map[String, (String, String)]
  consumed : Map[String, Bool]
  version : @version.FormatVersion
  limits : Limits
  mut nodes : Int32
  mut events : Int32
  mut assembly : Int32
  path_budget : Double
}

///|
fn[T] tree_error(
  code : String,
  path : String,
  detail : String,
) -> T raise @wire.CodecError {
  raise @wire.Invalid(code, path + "#: " + detail)
}

///|
fn TreeReader::charge(
  self : TreeReader,
  count : Int32,
) -> Unit raise @wire.CodecError {
  guard count <= self.limits.max_assembly_nodes - self.assembly else {
    tree_error(
      "yaml_assembly_limit", "manifest", "Tree assembly budget exceeded",
    )
  }
  self.assembly += count
}

///|
fn TreeReader::load(self : TreeReader, path : String) -> Json raise {
  guard self.files.get(path) is Some((physical, source)) else {
    tree_error("missing_member", path, "Missing tree file")
  }
  guard physical.length().to_double() <= self.path_budget else {
    tree_error(
      "invalid_distribution_shape", path, "Physical path exceeds pathBudget",
    )
  }
  if self.nodes >= self.limits.max_nodes {
    tree_error("yaml_node_limit", path, "Whole-tree node budget exceeded")
  }
  if self.events >= self.limits.max_events {
    tree_error("yaml_event_limit", path, "Whole-tree event budget exceeded")
  }
  if self.assembly >= self.limits.max_assembly_nodes {
    tree_error(
      "yaml_assembly_limit", path, "Whole-tree assembly budget exceeded",
    )
  }
  let (value, nodes, events) = parse_tree_document(physical, source, {
    ..self.limits,
    max_nodes: self.limits.max_nodes - self.nodes,
    max_events: self.limits.max_events - self.events,
    max_assembly_nodes: self.limits.max_assembly_nodes - self.assembly,
  }) catch {
    @wire.Invalid(code, detail) =>
      raise @wire.Invalid(code, physical + "#" + detail)
  }
  self.nodes += nodes
  self.events += events
  self.charge(
    assembly_cost(value, self.limits.max_assembly_nodes - self.assembly),
  )
  let version = @wire.read_version(@wire.field(value, "formatVersion"))
  if version != self.version {
    tree_error(
      "version_mismatch",
      path + "/formatVersion",
      "Every tree file must match the manifest revision",
    )
  }
  let fields = @wire.object(value)
  ignore(fields.remove("$meta"))
  self.consumed[path] = true
  value
}

///|
fn escaped_name(name : @ir.Name) -> String {
  let stem = name
    .to_segments()
    .map(segment => {
      match segment {
        Word(text) => text
        Initialism(text) => "_" + text.to_lower()
      }
    })
    .join("-")
  if [
      "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6",
      "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7",
      "lpt8", "lpt9",
    ].contains(stem) {
    stem + "_"
  } else {
    stem
  }
}

///|
fn escaped_path(path : @ir.Path) -> String {
  path.to_names().map(escaped_name).join("/")
}

///|
fn canonical_name(value : Json) -> @ir.Name raise {
  @ir.Name::parse(@wire.string(value))
}

///|
fn canonical_path(value : Json) -> @ir.Path raise {
  @ir.Path::parse(@wire.string(value))
}

///|
fn tree_doc(value : Json) -> Json raise {
  match value {
    String(_) => value
    Array(lines) => @wire.text(lines.map(line => @wire.string(line)).join("\n"))
    _ =>
      raise @wire.Invalid(
        "invalid_type", "Tree documentation must be a string or array of strings",
      )
  }
}

///|
fn TreeReader::entries(
  self : TreeReader,
  module_doc : Json,
  directory : String,
  kind : String,
  specification : Bool,
) -> Json raise {
  let listing = @wire.optional(module_doc, kind + "s").unwrap_or(
    Json::array([]),
  )
  let file_names = @wire.object(
    @wire.optional(module_doc, "fileNames").unwrap_or(@wire.obj([])),
  )
  let entries : Map[String, Json] = Map([])
  match listing {
    Object(fields) =>
      for name, value in fields {
        ignore(canonical_name(@wire.text(name)))
        self.charge(1)
        entries[name] = value
      }
    Array(names) =>
      for name in names {
        let parsed = canonical_name(name)
        let name = parsed.to_canonical()
        if entries.contains(name) {
          tree_error(
            "duplicate_member",
            directory,
            "Duplicate listed name " + name,
          )
        }
        let stem = match file_names.get(name) {
          None => escaped_name(parsed)
          Some(value) => @wire.string(value)
        }
        guard valid_stem(stem) &&
          directory.length() + stem.length() + kind.length() + 2 <= 4096 else {
          tree_error(
            "invalid_distribution_shape", directory, "Invalid or oversized fileNames stem",
          )
        }
        let path = directory + "/" + stem + "." + kind
        let node = self.load(path)
        @wire.fields(node, ["formatVersion", "name", "def", "spec"])
        if canonical_name(@wire.field(node, "name")) != parsed {
          tree_error(
            "invalid_distribution_shape",
            path + "/name",
            "Node name disagrees with its module listing",
          )
        }
        let body = if specification { "spec" } else { "def" }
        let other = if specification { "def" } else { "spec" }
        guard @wire.optional(node, other) is None &&
          @wire.optional(node, body) is Some(payload) else {
          tree_error(
            "invalid_distribution_shape", path, "Node must carry exactly the body required by its module role",
          )
        }
        self.charge(1)
        entries[name] = payload
      }
    _ =>
      tree_error(
        "invalid_type", directory, "Module entries must be a names array or inline mapping",
      )
  }
  if self.version.major == 3U {
    let pairs : Array[Json] = []
    for name, payload in entries {
      self.charge(2)
      pairs.push(
        Json::array([
          @wire.write_legacy_name(canonical_name(@wire.text(name))),
          payload,
        ]),
      )
    }
    Json::array(pairs)
  } else {
    Json::object(entries)
  }
}

///|
fn TreeReader::assemble_package(
  self : TreeReader,
  prefix : String,
  specification : Bool,
) -> Json raise {
  let paths = self.files
    .keys()
    .filter(path => path.has_prefix(prefix + "/") && path.has_suffix("/module"))
    .collect()
  paths.sort()
  let modules : Map[String, Json] = Map([])
  for physical in paths {
    let module_doc = self.load(physical)
    @wire.fields(
      module_doc,
      if self.version.major == 3U {
        [
          "formatVersion", "path", "access", "doc", "types", "values", "fileNames",
        ]
      } else {
        [
          "formatVersion", "path", "module", "access", "doc", "types", "values",
          "fileNames",
        ]
      },
    )
    if specification && @wire.optional(module_doc, "access") is Some(_) {
      tree_error(
        "unknown_member",
        physical + "/access",
        "Module specifications have no access",
      )
    }
    if @wire.optional(module_doc, "path") is Some(_) &&
      @wire.optional(module_doc, "module") is Some(_) {
      tree_error("duplicate_member", physical, "Use one module path member")
    }
    let name = canonical_path(
      @wire.optional(module_doc, "path").unwrap_or_else(() => {
        @wire.optional(module_doc, "module").unwrap_or(Json::null())
      }),
    )
    let expected = prefix + "/" + escaped_path(name) + "/module"
    if physical != expected {
      tree_error(
        "invalid_distribution_shape",
        physical + "/path",
        "Module path disagrees with directory",
      )
    }
    let directory = physical[:physical.length() - 7].to_owned()
    let types = self.entries(module_doc, directory, "type", specification)
    let values = self.entries(module_doc, directory, "value", specification)
    if @wire.optional(module_doc, "fileNames") is Some(file_names) {
      for key, value in @wire.object(file_names) {
        ignore(canonical_name(@wire.text(key)))
        if !valid_stem(@wire.string(value)) {
          tree_error(
            "invalid_distribution_shape",
            physical + "/fileNames",
            "Invalid file stem",
          )
        }
        let listed = ["types", "values"].any(kind => {
          match @wire.optional(module_doc, kind) {
            Some(Object(items)) => items.contains(key)
            Some(Array(items)) => items.contains(@wire.text(key))
            _ => false
          }
        })
        if !listed {
          tree_error(
            "unknown_member",
            physical + "/fileNames",
            "Stem map key is not listed in types or values",
          )
        }
      }
    }
    self.charge(6)
    let body = @wire.obj([("types", types), ("values", values)])
    if @wire.optional(module_doc, "doc") is Some(doc) {
      @wire.object(body)["doc"] = tree_doc(doc)
    }
    let entry = if specification {
      body
    } else {
      let access = @wire.optional(module_doc, "access").unwrap_or(
        @wire.text("Public"),
      )
      if access != @wire.text("Public") && access != @wire.text("Private") {
        tree_error(
          "invalid_access",
          physical + "/access",
          "Expected Public or Private",
        )
      }
      @wire.obj([("access", access), ("value", body)])
    }
    let key = name.to_canonical()
    if modules.contains(key) {
      tree_error("duplicate_member", physical, "Duplicate module")
    }
    modules[key] = entry
  }
  self.charge(2)
  if self.version.major == 3U {
    let pairs : Array[Json] = []
    for name, body in modules {
      self.charge(2)
      pairs.push(
        Json::array([
          @wire.write_legacy_path(canonical_path(@wire.text(name))),
          body,
        ]),
      )
    }
    @wire.obj([("modules", Json::array(pairs))])
  } else {
    @wire.obj([("modules", Json::object(modules))])
  }
}

///|
/// Assemble v4 and exactly v3.1.0 trees under shared whole-tree budgets.
/// Physical parsing and version-specific semantic decoding remain the existing
/// shared boundaries. This function performs only tree ownership and assembly.
pub fn read_tree_versioned(
  files : Map[String, String],
  limits~ : Limits = Limits::default(),
) -> @versions.IRFile raise {
  guard files.length() <= 4096 else {
    tree_error("yaml_source_limit", "manifest", "Tree has more than 4096 files")
  }
  let logical : Map[String, (String, String)] = Map([])
  let mut bytes = 0
  let mut manifest_yaml : Bool? = None
  for path, source in files {
    guard path.length() <= 4096 &&
      !path.has_prefix("/") &&
      !path.contains("\\") &&
      !path.contains(":") &&
      !path.contains("\u0000") &&
      path
      .split("/")
      .all(part => !part.is_empty() && part != "." && part != "..") else {
      tree_error("invalid_distribution_shape", "/", "Unsafe physical tree path")
    }
    guard source.length() <= limits.max_bytes - bytes else {
      tree_error(
        "yaml_source_limit", "manifest", "Whole-tree source byte budget exceeded",
      )
    }
    for c in source {
      bytes += if c.to_int() < 128 {
        1
      } else if c.to_int() < 2048 {
        2
      } else if c.to_int() < 65536 {
        3
      } else {
        4
      }
      if bytes > limits.max_bytes {
        tree_error(
          "yaml_source_limit", "manifest", "Whole-tree source byte budget exceeded",
        )
      }
    }
    let extension = if path.has_suffix(".yaml") {
      5
    } else if path.has_suffix(".yml") {
      4
    } else if path.has_suffix(".json") {
      5
    } else {
      0
    }
    if extension == 0 {
      continue
    }
    let key = path[:path.length() - extension].to_owned()
    // Unrelated files remain subject to capture bounds, but do not identify
    // model documents and therefore cannot make a model document ambiguous.
    if key != "manifest" && !key.has_prefix("pkg/") && !key.has_prefix("deps/") {
      continue
    }
    if logical.contains(key) {
      tree_error(
        "invalid_distribution_shape", key, "Ambiguous physical files for one logical document",
      )
    }
    logical[key] = (path, source)
    if key == "manifest" {
      manifest_yaml = Some(!path.has_suffix(".json"))
    }
  }
  guard manifest_yaml is Some(yaml) &&
    logical.get("manifest") is Some((manifest_path, source)) else {
    tree_error("missing_member", "manifest", "Missing distribution manifest")
  }
  let (manifest, nodes, events) = parse_tree_document(
    manifest_path, source, limits,
  )
  let version = @wire.read_version(@wire.field(manifest, "formatVersion"))
  if version.major == 3U && version.to_release_string() != "3.1.0" {
    tree_error(
      "version_mismatch", "manifest/formatVersion", "A v3 tree is exactly 3.1.0",
    )
  }
  guard version.major == 3U || version.major == 4U else {
    tree_error(
      "version_mismatch", "manifest/formatVersion", "Tree versions are v3.1.0 and supported v4",
    )
  }
  version.check_supported()
  ignore(@wire.object(manifest).remove("$meta"))
  @wire.fields(
    manifest,
    if version.major == 3U {
      ["formatVersion", "distribution", "package", "pathBudget", "dependencies"]
    } else {
      [
        "formatVersion", "distribution", "package", "pathBudget", "dependencies",
        "entryPoints", "version", "created", "layout",
      ]
    },
  )
  let kind = @wire.string(@wire.field(manifest, "distribution"))
  guard kind == "Library" ||
    kind == "Specs" ||
    (kind == "Application" && version.major == 4U) else {
    tree_error(
      "invalid_distribution_shape", "manifest/distribution", "Unsupported tree distribution kind",
    )
  }
  let package_name = canonical_path(@wire.field(manifest, "package"))
  let budget_value = @wire.field(manifest, "pathBudget")
  guard @wire.is_integral_number(budget_value) &&
    @wire.float(budget_value) >= 64 else {
    tree_error(
      "invalid_type", "manifest/pathBudget", "pathBudget must be an integer of at least 64",
    )
  }
  let path_budget = @wire.float(budget_value)
  for key in ["version", "created", "layout"] {
    if @wire.optional(manifest, key) is Some(value) {
      ignore(@wire.string(value))
    }
  }
  let reader = TreeReader::{
    files: logical,
    consumed: Map([("manifest", true)]),
    version,
    limits,
    nodes,
    events,
    assembly: nodes,
    path_budget,
  }
  for key, (physical, _) in logical {
    if key == "manifest" || key.has_prefix("pkg/") || key.has_prefix("deps/") {
      if physical.has_suffix(".json") == yaml {
        tree_error(
          "invalid_distribution_shape", physical, "Tree files must share one serialization profile",
        )
      }
      if physical.length().to_double() > path_budget {
        tree_error(
          "invalid_distribution_shape", physical, "Physical path exceeds pathBudget",
        )
      }
    }
  }
  let dependencies : Map[String, Json] = Map([])
  let listed = @wire.array(
    @wire.optional(manifest, "dependencies").unwrap_or(Json::array([])),
  )
  for raw in listed {
    let name = canonical_path(raw)
    let key = name.to_canonical()
    if name == package_name {
      tree_error(
        "invalid_distribution_shape", "manifest/dependencies", "A package cannot depend on itself",
      )
    }
    if dependencies.contains(key) {
      tree_error(
        "duplicate_member", "manifest/dependencies", "Duplicate dependency",
      )
    }
    let body = reader.assemble_package(
      "deps/" + escaped_path(name) + "/@",
      kind != "Application",
    )
    reader.charge(1)
    dependencies[key] = body
  }
  let own = reader.assemble_package(
    "pkg/" + escaped_path(package_name),
    kind == "Specs",
  )
  for path, _ in logical {
    if (path.has_prefix("pkg/") || path.has_prefix("deps/")) &&
      !reader.consumed.contains(path) {
      tree_error(
        "invalid_distribution_shape", path, "File belongs to no listed module_doc; dependencies require a bare @ segment",
      )
    }
  }
  reader.charge(8)
  let distribution = if version.major == 3U {
    let pairs : Array[Json] = []
    for name, body in dependencies {
      reader.charge(2)
      pairs.push(
        Json::array([
          @wire.write_legacy_path(canonical_path(@wire.text(name))),
          body,
        ]),
      )
    }
    Json::array([
      @wire.text(kind),
      @wire.write_legacy_path(package_name),
      Json::array(pairs),
      own,
    ])
  } else {
    let payload = @wire.obj([
      ("packageName", @wire.text(package_name.to_canonical())),
      ("dependencies", Json::object(dependencies)),
      (if kind == "Specs" { "spec" } else { "def" }, own),
    ])
    if kind == "Application" {
      @wire.object(payload)["entryPoints"] = @wire.field(
        manifest, "entryPoints",
      )
    } else if @wire.optional(manifest, "entryPoints") is Some(_) {
      tree_error(
        "unknown_member", "manifest/entryPoints", "Only Application has entry points",
      )
    }
    @wire.tag(kind, payload)
  }
  let value = @wire.obj([
    ("formatVersion", @wire.write_version(version)),
    ("distribution", distribution),
  ])
  reader.charge(
    assembly_cost(value, limits.max_assembly_nodes - reader.assembly),
  )
  @versioned.from_json(value)
}

///|
fn parse_tree_document(
  path : String,
  source : String,
  limits : Limits,
) -> (Json, Int32, Int32) raise @wire.CodecError {
  if !path.has_suffix(".json") {
    return parse_document(source, limits)
  }
  let cap = limits.max_nodes
    .min(limits.max_assembly_nodes)
    .min(limits.max_events / 2)
  guard cap > 0 else {
    raise @wire.Invalid("json_limit", "Whole-tree parse budget exceeded")
  }
  let root = @wire.parse_bounded(
    source,
    max_depth=limits.max_depth,
    max_nodes=cap,
    max_string_units=limits.max_scalar_units,
  )
  let pending = [root]
  let mut nodes = 0
  while pending.pop() is Some(value) {
    nodes += 1
    match value {
      Object(fields) =>
        for _, item in fields {
          pending.push(item)
        }
      Array(items) =>
        for item in items {
          pending.push(item)
        }
      _ => ()
    }
  }
  (root, nodes, nodes * 2)
}

///|
fn valid_stem(text : String) -> Bool {
  if text.is_empty() || text.length() > 4096 {
    return false
  }
  let parts = text.split("__").collect()
  if parts.length() > 2 {
    return false
  }
  let base = parts[0]
  if parts.length() == 2 {
    let hash = parts[1]
    let hash = if hash.has_suffix("_") {
      hash[:hash.length() - 1]
    } else {
      hash
    }
    if hash.length() != 8 ||
      !hash.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      return false
    }
  }
  let base = if base.has_suffix("_") { base[:base.length() - 1] } else { base }
  base
  .split("-")
  .all(part => {
    let part = if part.has_prefix("_") { part[1:] } else { part }
    !part.is_empty() &&
    part.iter().all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
  })
}

///|
pub fn read_tree(
  files : Map[String, String],
  limits~ : Limits = Limits::default(),
) -> @ir.IRFile raise {
  @migration.to_current(read_tree_versioned(files, limits~))
}
