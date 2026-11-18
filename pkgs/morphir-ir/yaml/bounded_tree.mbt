///|
/// Refusals that a revision-bound source must report before returning data.
pub(all) suberror TreeSourceError {
  RevisionChanged
  DocumentTooLarge
}

///|
/// A source must serve the exact revision passed to each callback or raise
/// RevisionChanged. A revision must never be reused for different content.
/// contains(revision, path) probes physical metadata without opening a body.
/// next_module(revision, prefix, after) returns the first extensionless module
/// document under prefix after the optional previous logical path, in lexical
/// order. It enumerates storage metadata without opening documents.
/// read(revision, path, max_bytes) returns valid UTF-8 or raises
/// DocumentTooLarge before allocating a buffer larger than max_bytes.
pub(all) struct TreeSource {
  revision : () -> String raise
  contains : (String, String) -> Bool raise
  next_module : (String, String, String?) -> String? raise
  read : (String, String, Int32) -> String raise
}

///|
struct BoundedTree {
  source : TreeSource
  revision : String
  binding : Ref[Unit]
  manifest : TreeManifest
  dependencies : Array[@ir.Path]
  yaml : Bool
  limits : Limits
}

///|
#derive(Eq, Debug)
pub(all) enum TreeRole {
  Definition
  Specification
}

///|
pub extend TreeRole with Eq::{equal, not_equal}

///|
pub extend TreeRole with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum TreeMemberKind {
  TypeMember
  ValueMember
}

///|
pub extend TreeMemberKind with Eq::{equal, not_equal}

///|
pub extend TreeMemberKind with @debug.Debug::{to_repr}

///|
pub struct TreeMember {
  package_name : @ir.Path
  module_name : @ir.Path
  name : @ir.Name
  kind : TreeMemberKind
  role : TreeRole
  document : String
}

///|
#derive(Eq)
priv enum TreeSelection {
  Modules(@ir.Path)
  Members(@ir.Path, @ir.Path)
}

///|
priv enum TreePosition {
  ModulePath(String)
  MemberOffset(Int32)
}

///|
struct TreeCursor {
  binding : Ref[Unit]
  selection : TreeSelection
  position : TreePosition
}

///|
pub struct TreePage[T] {
  items : Array[T]
  next : TreeCursor?
}

///|
fn tree_physical_path(
  source : TreeSource,
  revision : String,
  logical : String,
) -> String raise {
  guard safe_tree_path(logical) else {
    tree_error("invalid_distribution_shape", "/", "Unsafe logical tree path")
  }
  let mut found = None
  for extension in [".json", ".yaml", ".yml"] {
    let path = logical + extension
    if (source.contains)(revision, path) {
      guard found is None else {
        tree_error(
          "invalid_distribution_shape", logical, "Ambiguous physical files for one logical document",
        )
      }
      found = Some(path)
    }
  }
  guard found is Some(path) else {
    tree_error("missing_member", logical, "Missing tree file")
  }
  path
}

///|
fn bounded_document(
  source : TreeSource,
  revision : String,
  physical : String,
  logical : String,
  limits : Limits,
) -> Json raise {
  let text = (source.read)(revision, physical, limits.max_bytes) catch {
    TreeSourceError::DocumentTooLarge =>
      tree_error(
        "document_size_limit", logical, "Document byte budget exceeded",
      )
    error => raise error
  }
  let (document, _, _) = try {
    if physical.has_suffix(".json") {
      check_source_bytes(text, limits)
    }
    parse_tree_document(physical, text, limits)
  } catch {
    @wire.Invalid("yaml_source_limit", _) =>
      tree_error(
        "document_size_limit", logical, "Document byte budget exceeded",
      )
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
  }
  ignore(assembly_cost(document, limits.max_assembly_nodes)) catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
  }
  document
}

///|
pub fn open_bounded_tree(
  source : TreeSource,
  limits~ : Limits = Limits::default(),
) -> BoundedTree raise {
  check_limits(limits)
  guard limits.max_depth > 0 else {
    tree_error(
      "yaml_invalid_limits", "manifest", "Bounded document depth must be positive",
    )
  }
  let revision = (source.revision)()
  let physical = tree_physical_path(source, revision, "manifest")
  let document = bounded_document(
    source, revision, physical, "manifest", limits,
  )
  let manifest = tree_manifest(document)
  if tree_entry_points(document, manifest.kind) is Some(points) {
    let location = "manifest/entryPoints"
    guard points is Object(entries) && !entries.is_empty() else {
      tree_error(
        "invalid_type", location, "Expected a nonempty entry point map",
      )
    }
    // Use the v4 entry point decoder with an empty package body. Opening
    // the manifest does not load modules or resolve the targets.
    let application = @wire.tag(
      "Application",
      @wire.obj([
        ("packageName", @wire.text(manifest.package_name.to_canonical())),
        ("entryPoints", points),
      ]),
    )
    ignore(@v4_json.read_distribution(application)) catch {
      @wire.Invalid(code, detail) => tree_error(code, location, detail)
      error => raise error
    }
  }
  match @wire.optional(document, "layout") {
    None | Some(String("VfsMode")) => ()
    _ =>
      tree_error(
        "unsupported_tree_layout", "manifest/layout", "Bounded access requires the document tree layout",
      )
  }
  let dependencies = []
  let listed = @wire.array(
    @wire.optional(document, "dependencies").unwrap_or(Json::array([])),
  )
  let seen : Map[@ir.Path, Unit] = Map([])
  for raw in listed {
    let dependency = canonical_path(raw)
    guard dependency != manifest.package_name else {
      tree_error(
        "invalid_distribution_shape", "manifest/dependencies", "A package cannot depend on itself",
      )
    }
    guard !seen.contains(dependency) else {
      tree_error(
        "duplicate_member", "manifest/dependencies", "Duplicate dependency",
      )
    }
    seen[dependency] = ()
    dependencies.push(dependency)
  }
  guard physical.length().to_double() <= manifest.path_budget else {
    tree_error(
      "invalid_distribution_shape", "manifest", "Physical path exceeds pathBudget",
    )
  }
  let tree : BoundedTree = {
    source,
    revision,
    binding: Ref(()),
    manifest,
    dependencies,
    yaml: !physical.has_suffix(".json"),
    limits,
  }
  tree.check_revision()
  tree
}

///|
pub fn BoundedTree::format_version(
  self : BoundedTree,
) -> @version.FormatVersion {
  self.manifest.version
}

///|
pub fn BoundedTree::package_name(self : BoundedTree) -> @ir.Path {
  self.manifest.package_name
}

///|
pub fn BoundedTree::dependency_packages(self : BoundedTree) -> Iter[@ir.Path] {
  self.dependencies.iter()
}

///|
fn BoundedTree::check_revision(self : BoundedTree) -> Unit raise {
  guard (self.source.revision)() == self.revision else {
    raise TreeSourceError::RevisionChanged
  }
}

///|
fn BoundedTree::package_location(
  self : BoundedTree,
  package_name : @ir.Path,
) -> (String, TreeRole) raise {
  if package_name == self.manifest.package_name {
    let role = if self.manifest.kind == Specs {
      Specification
    } else {
      Definition
    }
    return ("pkg/" + escaped_path(package_name), role)
  }
  guard self.dependencies.contains(package_name) else {
    tree_error(
      "missing_member", "manifest/dependencies", "Package is outside the snapshot",
    )
  }
  let role = if self.manifest.kind == Application {
    Definition
  } else {
    Specification
  }
  ("deps/" + escaped_path(package_name) + "/@", role)
}

///|
fn BoundedTree::load(self : BoundedTree, logical : String) -> Json raise {
  let physical = tree_physical_path(self.source, self.revision, logical)
  guard physical.has_suffix(".json") != self.yaml &&
    safe_tree_path(physical) &&
    physical.length().to_double() <= self.manifest.path_budget else {
    tree_error(
      "invalid_distribution_shape", logical, "Invalid physical profile or path budget",
    )
  }
  let document = bounded_document(
    self.source,
    self.revision,
    physical,
    logical,
    self.limits,
  )
  let version = @wire.read_version(@wire.field(document, "formatVersion")) catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
    error => raise error
  }
  guard version == self.manifest.version else {
    tree_error(
      "version_mismatch",
      logical + "/formatVersion",
      "Every tree file must match the manifest revision",
    )
  }
  ignore(@wire.object(document).remove("$meta"))
  document
}

///|
fn BoundedTree::load_module(
  self : BoundedTree,
  prefix : String,
  logical : String,
  role : TreeRole,
) -> (Json, @ir.Path, @common.Access?, Map[String, Json]) raise {
  let document = self.load(logical)
  let path = tree_module_path(
    document,
    logical,
    prefix,
    self.manifest.version,
    role == Specification,
  )
  let access = if role == Definition {
    Some(tree_module_access(document, logical))
  } else {
    None
  }
  if @wire.optional(document, "doc") is Some(doc) {
    ignore(tree_doc(doc))
  }
  (document, path, access, tree_file_names(document, logical))
}

///|
fn BoundedTree::page_start(
  self : BoundedTree,
  selection : TreeSelection,
  limit : Int32,
  cursor : TreeCursor?,
) -> TreePosition? raise {
  guard limit > 0 && limit <= 256 else {
    tree_error(
      "invalid_page_limit", "manifest", "Page size must be between 1 and 256",
    )
  }
  self.check_revision()
  match cursor {
    None => None
    Some(cursor) => {
      guard physical_equal(self.binding, cursor.binding) &&
        cursor.selection == selection else {
        tree_error(
          "invalid_cursor", "manifest", "Cursor belongs to another snapshot or selection",
        )
      }
      Some(cursor.position)
    }
  }
}

///|
fn TreeMemberKind::file_suffix(self : TreeMemberKind) -> String {
  match self {
    TypeMember => "type"
    ValueMember => "value"
  }
}

///|
fn module_entries(
  module_doc : Json,
  kind : TreeMemberKind,
) -> Iter[(Json, Json?)] raise {
  match @wire.optional(module_doc, kind.file_suffix() + "s") {
    None => [].iter()
    Some(Array(names)) => names.iter().map(name => (name, None))
    Some(Object(entries)) =>
      entries.iter().map(entry => (@wire.text(entry.0), Some(entry.1)))
    _ =>
      raise @wire.Invalid(
        "invalid_type", "Module entries must be a names array or inline mapping",
      )
  }
}

///|
fn module_directory(prefix : String, module_name : @ir.Path) -> String raise {
  let canonical = @ir.Path::parse(module_name.to_canonical()) catch {
    _ =>
      tree_error(
        "invalid_distribution_shape", "module", "Expected a canonical module path",
      )
  }
  guard module_name == canonical else {
    tree_error(
      "invalid_distribution_shape", "module", "Expected a canonical module path",
    )
  }
  prefix + "/" + escaped_path(module_name)
}

///|
pub fn BoundedTree::members(
  self : BoundedTree,
  package_name : @ir.Path,
  module_name : @ir.Path,
  limit~ : Int32,
  cursor? : TreeCursor,
) -> TreePage[TreeMember] raise {
  let selection = Members(package_name, module_name)
  let offset = match self.page_start(selection, limit, cursor) {
    Some(MemberOffset(offset)) => offset
    _ => 0
  }
  let (prefix, role) = self.package_location(package_name)
  let directory = module_directory(prefix, module_name)
  let module_path = directory + "/module"
  let (module_doc, _, _, file_names) = self.load_module(
    prefix, module_path, role,
  )
  let items : Array[TreeMember] = []
  let mut index = 0
  for kind in [TreeMemberKind::TypeMember, ValueMember] {
    let seen : Map[String, Unit] = Map([])
    for (raw, inline) in module_entries(module_doc, kind) {
      let name = canonical_name(raw)
      let document = if inline is Some(_) {
        module_path
      } else {
        tree_member_path(name, kind.file_suffix(), directory, file_names)
      }
      // Inline members have distinct names in a single document. Split
      // members must have distinct document paths within their kind.
      let key = if inline is Some(_) { name.to_canonical() } else { document }
      guard !seen.contains(key) else {
        tree_error(
          "duplicate_member", document, "Multiple members use one document",
        )
      }
      seen[key] = ()
      if index >= offset && items.length() < limit {
        items.push({ package_name, module_name, name, kind, role, document, })
      }
      index += 1
    }
  }
  self.check_revision()
  let next_offset = offset + items.length()
  let next = if next_offset < index {
    Some({
      binding: self.binding,
      selection,
      position: MemberOffset(next_offset),
    })
  } else {
    None
  }
  { items, next, }
}

///|
pub struct TreeModule {
  package_name : @ir.Path
  path : @ir.Path
  document : String
  role : TreeRole
  access : @common.Access?
}

///|
pub fn BoundedTree::modules(
  self : BoundedTree,
  package_name : @ir.Path,
  limit~ : Int32,
  cursor? : TreeCursor,
) -> TreePage[TreeModule] raise {
  let selection = Modules(package_name)
  let after = match self.page_start(selection, limit, cursor) {
    Some(ModulePath(path)) => Some(path)
    _ => None
  }
  let (prefix, role) = self.package_location(package_name)
  let directory = prefix + "/"
  let items : Array[TreeModule] = []
  let mut previous = after
  while (self.source.next_module)(self.revision, directory, previous)
        is Some(logical) {
    guard logical.has_prefix(directory) &&
      logical.has_suffix("/module") &&
      safe_tree_path(logical) &&
      previous.map_or(true, key => key[:].lexical_compare(logical[:]) < 0) else {
      tree_error(
        "invalid_distribution_shape", prefix, "Source returned an unsafe or unordered module path",
      )
    }
    if items.length() == limit {
      self.check_revision()
      let next = previous.map(after => {
        binding: self.binding,
        selection,
        position: ModulePath(after),
      })
      return { items, next, }
    }
    let (_, path, access, _) = self.load_module(prefix, logical, role)
    items.push({ package_name, path, role, access, document: logical, })
    previous = Some(logical)
  }
  self.check_revision()
  { items, next: None, }
}

///|
pub(all) enum TreeMemberBody {
  V3TypeDefinition(
    @v3.AccessControlled[@v3.Documented[@v3.TypeDefinition[Unit]]]
  )
  V3ValueDefinition(
    @v3.AccessControlled[
      @v3.Documented[@v3.ValueDefinition[Unit, @v3.Type[Unit]]],
    ]
  )
  V3TypeSpecification(@v3.Documented[@v3.TypeSpecification[Unit]])
  V3ValueSpecification(@v3.Documented[@v3.ValueSpecification[Unit]])
  V4TypeDefinition(@v4.AccessControlled[@v4.Documented[@v4.TypeDefinition]])
  V4ValueDefinition(@v4.AccessControlled[@v4.Documented[@v4.ValueDefinition]])
  V4TypeSpecification(@v4.Documented[@v4.TypeSpecification])
  V4ValueSpecification(@v4.Documented[@v4.ValueSpecification])
}

///|
fn BoundedTree::resolve_member(
  self : BoundedTree,
  package_name : @ir.Path,
  module_name : @ir.Path,
  kind : TreeMemberKind,
  name : @ir.Name,
) -> (String, TreeRole, Json?) raise {
  let (prefix, role) = self.package_location(package_name)
  let directory = module_directory(prefix, module_name)
  let module_path = directory + "/module"
  let (module_doc, _, _, file_names) = self.load_module(
    prefix, module_path, role,
  )
  let listing = @wire.optional(module_doc, kind.file_suffix() + "s").unwrap_or(
    Json::array([]),
  )
  if listing is Object(entries) {
    guard entries.get(name.to_canonical()) is Some(payload) else {
      tree_error(
        "missing_member", module_path, "Member is outside its module listing",
      )
    }
    return (module_path, role, Some(payload))
  }
  let logical = tree_member_path(
    name,
    kind.file_suffix(),
    directory,
    file_names,
  )
  let mut found = false
  for raw in @wire.array(listing) {
    let candidate = canonical_name(raw)
    if tree_member_path(candidate, kind.file_suffix(), directory, file_names) ==
      logical {
      guard candidate == name && !found else {
        tree_error(
          "duplicate_member", logical, "Multiple members use one document",
        )
      }
      found = true
    }
  }
  guard found else {
    tree_error(
      "missing_member", logical, "Member is outside its module listing",
    )
  }
  (logical, role, None)
}

///|
/// Resolve the requested semantic identity through its owning module, then
/// decode the selected definition or specification with its version's codec.
pub fn BoundedTree::read_member(
  self : BoundedTree,
  package_name : @ir.Path,
  module_name : @ir.Path,
  kind : TreeMemberKind,
  name : @ir.Name,
) -> TreeMemberBody raise {
  self.check_revision()
  let canonical = @ir.Name::parse(name.to_canonical()) catch {
    _ =>
      tree_error(
        "invalid_distribution_shape", "module", "Expected a canonical member name",
      )
  }
  guard name == canonical else {
    tree_error(
      "invalid_distribution_shape", "module", "Expected a canonical member name",
    )
  }
  let (logical, role, inline) = self.resolve_member(
    package_name, module_name, kind, name,
  )
  let body = try {
    let payload = match inline {
      Some(payload) => payload
      None =>
        tree_node_payload(
          self.load(logical),
          logical,
          name,
          role == Specification,
        )
    }
    decode_tree_member(self.manifest.version, kind, role, payload)
  } catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
    error => raise error
  }
  self.check_revision()
  body
}

///|
fn decode_tree_member(
  version : @version.FormatVersion,
  kind : TreeMemberKind,
  role : TreeRole,
  payload : Json,
) -> TreeMemberBody raise {
  if version.major == 3U {
    let type_attribute = fn(value) raise { @wire.unit(value) }
    match (kind, role) {
      (TypeMember, Definition) =>
        V3TypeDefinition(
          @v3_json.read_access(payload, fn(doc) raise {
            @v3_json.read_documented(doc, fn(value) raise {
              @v3_json.read_type_definition(value, type_attribute)
            })
          }),
        )
      (ValueMember, Definition) =>
        V3ValueDefinition(
          @v3_json.read_access(payload, fn(doc) raise {
            @v3_json.read_documented(doc, fn(value) raise {
              @v3_json.read_value_definition(value, type_attribute, fn(
                attribute,
              ) raise {
                @v3_json.read_type(attribute, type_attribute)
              })
            })
          }),
        )
      (TypeMember, Specification) =>
        V3TypeSpecification(
          @v3_json.read_documented(payload, fn(value) raise {
            @v3_json.read_type_specification(value, type_attribute)
          }),
        )
      (ValueMember, Specification) =>
        V3ValueSpecification(
          @v3_json.read_documented(payload, fn(value) raise {
            @v3_json.read_value_specification(value, type_attribute)
          }),
        )
    }
  } else {
    match (kind, role) {
      (TypeMember, Definition) =>
        V4TypeDefinition(
          @v4_json.read_access(payload, fn(doc) raise {
            @v4_json.read_documented(doc, @v4_json.read_type_definition)
          }),
        )
      (ValueMember, Definition) =>
        V4ValueDefinition(
          @v4_json.read_access(payload, fn(doc) raise {
            @v4_json.read_documented(doc, @v4_json.read_definition)
          }),
        )
      (TypeMember, Specification) =>
        V4TypeSpecification(
          @v4_json.read_documented(payload, @v4_json.read_type_specification),
        )
      (ValueMember, Specification) =>
        V4ValueSpecification(
          @v4_json.read_documented(payload, @v4_json.read_value_specification),
        )
    }
  }
}
