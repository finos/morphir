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
  encoding : TreeEncoding
  limits : Limits
  split_members_only : Bool
  observe : () -> Unit raise
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
fn read_bounded_source_text(
  source : TreeSource,
  revision : String,
  physical : String,
  logical : String,
  limits : Limits,
) -> String raise {
  let text = (source.read)(revision, physical, limits.max_bytes) catch {
    TreeSourceError::DocumentTooLarge =>
      tree_error(
        "document_size_limit", logical, "Document byte budget exceeded",
      )
    error => raise error
  }
  check_source_bytes(text, limits) catch {
    @wire.Invalid("yaml_source_limit", _) =>
      tree_error(
        "document_size_limit", logical, "Document byte budget exceeded",
      )
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
  }
  text
}

///|
fn parse_bounded_source(
  source : TreeSource,
  revision : String,
  physical : String,
  logical : String,
  limits : Limits,
  encoding : TreeEncoding,
) -> Json raise {
  let text = read_bounded_source_text(
    source, revision, physical, logical, limits,
  )
  let (document, _, _) = parse_tree_document(
    physical,
    text,
    limits,
    contextual=!(encoding is Plain),
  ) catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
  }
  ignore(assembly_cost(document, limits.max_assembly_nodes)) catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
  }
  document
}

///|
priv enum DocumentAdmission {
  Ready(Json, @wire.DocumentNameContext?)
  Reopen(@wire.DocumentNameContext)
}

///|
fn admit_bounded_source(
  source : TreeSource,
  revision : String,
  physical : String,
  logical : String,
  limits : Limits,
  encoding : TreeEncoding,
) -> DocumentAdmission raise {
  let input = parse_bounded_source(
    source, revision, physical, logical, limits, encoding,
  )
  let (document, context) = @wire.admit_contextual_document(
    input,
    !(encoding is Plain),
  ) catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
  }
  if context is Some(names) {
    let mut schema_seen = false
    let mut context_seen = false
    for key, _ in @wire.object(input) {
      match key {
        "$schema" => schema_seen = true
        "context" => context_seen = true
        "document" => break
        _ => ()
      }
    }
    if encoding is ContextualDraft1Ordered && (!schema_seen || !context_seen) {
      tree_error(
        "context.after_document", logical, "Expected schema and context before document",
      )
    }
    if !context_seen {
      return Reopen(names)
    }
  }
  Ready(document, context.map(names => names.with_document(document)))
}

///|
fn bounded_document(
  source : TreeSource,
  revision : String,
  physical : String,
  logical : String,
  limits : Limits,
  encoding : TreeEncoding,
) -> (Json, @wire.DocumentNameContext?) raise {
  match
    admit_bounded_source(source, revision, physical, logical, limits, encoding) {
    Ready(document, context) => (document, context)
    Reopen(context) => {
      // The first parse tree has gone out of scope. The source must serve
      // exactly the same revision and cap the new read at the same limit.
      let input = parse_bounded_source(
        source, revision, physical, logical, limits, encoding,
      )
      let document = @wire.field(input, "document")
      (document, Some(context.with_document(document)))
    }
  }
}

///|
/// The selected per-file encoding for the document tree.
pub(all) enum TreeEncoding {
  Plain
  ContextualDraft1
  ContextualDraft1Ordered
}

///|
pub fn open_bounded_tree(
  source : TreeSource,
  limits~ : Limits = Limits::default(),
  encoding~ : TreeEncoding = Plain,
  split_members_only~ : Bool = false,
  observe~ : () -> Unit raise = fn() {  },
) -> BoundedTree raise {
  check_limits(limits)
  guard limits.max_depth > 0 else {
    tree_error(
      "yaml_invalid_limits", "manifest", "Bounded document depth must be positive",
    )
  }
  let revision = (source.revision)()
  let physical = tree_physical_path(source, revision, "manifest")
  let (document, context) = bounded_document(
    source, revision, physical, "manifest", limits, encoding,
  )
  let manifest = tree_manifest(document, context~)
  if tree_entry_points(document, manifest.kind) is Some(points) {
    let location = "manifest/entryPoints"
    guard points is Object(entries) && !entries.is_empty() else {
      tree_error(
        "invalid_type", location, "Expected a nonempty entry point map",
      )
    }
    // The manifest validates the target names without opening their bodies.
    ignore(@v4_json.read_entry_points(points, context~)) catch {
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
    let dependency = match context {
      Some(names) =>
        resolve_tree_slot("manifest/dependencies", () => names.package_path(raw))
      None => canonical_path(raw)
    }
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
    encoding,
    limits,
    split_members_only,
    observe,
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
fn BoundedTree::load(
  self : BoundedTree,
  logical : String,
  preserve_metadata~ : Bool = false,
) -> (Json, @wire.DocumentNameContext?) raise {
  let physical = tree_physical_path(self.source, self.revision, logical)
  guard physical.has_suffix(".json") != self.yaml &&
    safe_tree_path(physical) &&
    physical.length().to_double() <= self.manifest.path_budget else {
    tree_error(
      "invalid_distribution_shape", logical, "Invalid physical profile or path budget",
    )
  }
  let (document, context) = bounded_document(
    self.source,
    self.revision,
    physical,
    logical,
    self.limits,
    self.encoding,
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
  if !preserve_metadata {
    ignore(@wire.object(document).remove("$meta"))
  }
  (document, context)
}

///|
fn BoundedTree::load_module(
  self : BoundedTree,
  prefix : String,
  logical : String,
  role : TreeRole,
) -> (
  Json,
  @ir.Path,
  @common.Access?,
  Map[String, Json],
  @wire.DocumentNameContext?,
) raise {
  (self.observe)()
  let (document, context) = self.load(logical)
  if self.split_members_only {
    for field in ["types", "values"] {
      match @wire.optional(document, field) {
        None | Some(Array(_)) => ()
        Some(Object(entries)) if entries.is_empty() => ()
        _ =>
          tree_error(
            "split_members_required",
            logical + "/" + field,
            "Bounded generation requires split member files",
          )
      }
    }
  }
  let path = tree_module_path(
    document,
    logical,
    prefix,
    self.manifest.version,
    role == Specification,
    context~,
  )
  let access = if role == Definition {
    Some(tree_module_access(document, logical))
  } else {
    None
  }
  if @wire.optional(document, "doc") is Some(doc) {
    ignore(tree_doc(doc))
  }
  (
    document,
    path,
    access,
    tree_file_names(document, logical, context~, observe=self.observe),
    context,
  )
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
  let (module_doc, _, _, file_names, context) = self.load_module(
    prefix, module_path, role,
  )
  let items : Array[TreeMember] = []
  let mut index = 0
  for kind in [TreeMemberKind::TypeMember, ValueMember] {
    let seen : Map[String, Unit] = Map([])
    for (raw, inline) in module_entries(module_doc, kind) {
      (self.observe)()
      let name = canonical_name(
        raw,
        context~,
        location=module_path + "/" + kind.file_suffix() + "s",
      )
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
    let (_, path, access, _, _) = self.load_module(prefix, logical, role)
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
) -> (String, TreeRole, (Json, @wire.DocumentNameContext?)?) raise {
  let (prefix, role) = self.package_location(package_name)
  let directory = module_directory(prefix, module_name)
  let module_path = directory + "/module"
  let (module_doc, _, _, file_names, context) = self.load_module(
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
    return (module_path, role, Some((payload, context)))
  }
  let logical = tree_member_path(
    name,
    kind.file_suffix(),
    directory,
    file_names,
  )
  let mut found = false
  for raw in @wire.array(listing) {
    (self.observe)()
    let candidate = canonical_name(
      raw,
      context~,
      location=module_path + "/" + kind.file_suffix() + "s",
    )
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
  self.read_member_document(package_name, module_name, kind, name).0
}

///|
fn BoundedTree::read_member_document(
  self : BoundedTree,
  package_name : @ir.Path,
  module_name : @ir.Path,
  kind : TreeMemberKind,
  name : @ir.Name,
) -> (TreeMemberBody, String) raise {
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
    let (payload, context) = match inline {
      Some(selected) => selected
      None => {
        let (document, context) = self.load(logical)
        let payload = tree_node_payload(
          document,
          logical,
          name,
          role == Specification,
          context~,
        )
        (payload, context)
      }
    }
    decode_tree_member(
      self.manifest.version,
      kind,
      role,
      payload,
      context,
      !(self.encoding is Plain),
    )
  } catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
    error => raise error
  }
  self.check_revision()
  (body, logical)
}

///|
/// Select a physical document by its tree identity. An inline member
/// selects the containing module artifact.
pub(all) enum TreeArtifact {
  ManifestArtifact
  ModuleArtifact(@ir.Path, @ir.Path)
  MemberArtifact(@ir.Path, @ir.Path, TreeMemberKind, @ir.Name)
}

///|
fn BoundedTree::validated_artifact_path(
  self : BoundedTree,
  artifact : TreeArtifact,
) -> String raise {
  self.check_revision()
  match artifact {
    ManifestArtifact => "manifest"
    ModuleArtifact(package_name, module_name) => {
      let (prefix, role) = self.package_location(package_name)
      let path = module_directory(prefix, module_name) + "/module"
      ignore(self.load_module(prefix, path, role))
      path
    }
    MemberArtifact(package_name, module_name, kind, name) =>
      self.read_member_document(package_name, module_name, kind, name).1
  }
}

///|
/// Reopen one admitted document under the same revision and byte limit.
/// Return its physical path and original UTF-8 text for opaque pass-through.
pub fn BoundedTree::read_original_document(
  self : BoundedTree,
  artifact : TreeArtifact,
) -> (String, String) raise {
  let logical = self.validated_artifact_path(artifact)
  let physical = tree_physical_path(self.source, self.revision, logical)
  let text = read_bounded_source_text(
    self.source,
    self.revision,
    physical,
    logical,
    self.limits,
  )
  self.check_revision()
  (physical, text)
}

///|
/// Expand one revision-bound artifact to plain JSON. If the selected member is
/// inline, return the containing module. No output is returned on refusal.
pub fn BoundedTree::read_expanded_document(
  self : BoundedTree,
  artifact : TreeArtifact,
  max_output_bytes~ : Int32,
) -> (String, String) raise {
  let logical = self.validated_artifact_path(artifact)
  let output = logical + ".json"
  guard output.length().to_double() <= self.manifest.path_budget else {
    tree_error(
      "invalid_distribution_shape", logical, "Expanded physical path exceeds pathBudget",
    )
  }
  let (document, context) = self.load(logical, preserve_metadata=true)
  let expanded = @wire.expand_admitted_names(
    document,
    context,
    max_bytes=max_output_bytes,
  ) catch {
    @wire.Invalid(code, detail) => tree_error(code, logical, detail)
  }
  self.check_revision()
  (output, expanded)
}

///|
/// Limits for documents written to an expanded export's private stage.
pub(all) struct ExpandedTreeLimits {
  max_document_bytes : Int32
  max_total_bytes : Int64
  page_size : Int32
}

///|
/// Emit an expanded plain JSON tree a file at a time. The callback owns
/// staging. It must publish only after this walk succeeds, since a later
/// read, byte limit, or source revision change can fail the export.
pub fn BoundedTree::write_expanded_tree(
  self : BoundedTree,
  limits : ExpandedTreeLimits,
  stage_file : (String, String) -> Unit raise,
) -> Unit raise {
  guard limits.max_document_bytes > 0 && limits.max_total_bytes > 0L else {
    tree_error(
      "document_size_limit", "manifest", "Expected positive export byte limits",
    )
  }
  guard limits.page_size > 0 && limits.page_size <= 256 else {
    tree_error(
      "invalid_page_limit", "manifest", "Page size must be between 1 and 256",
    )
  }
  let mut remaining = limits.max_total_bytes
  let stage = fn(artifact) raise {
    guard remaining > 0L else {
      tree_error(
        "document_size_limit", "manifest", "Expanded export byte budget exhausted",
      )
    }
    let max_output_bytes = if remaining < limits.max_document_bytes.to_int64() {
      remaining.to_int()
    } else {
      limits.max_document_bytes
    }
    let (path, expanded) = self.read_expanded_document(
      artifact,
      max_output_bytes~,
    )
    remaining -= count_source_bytes(expanded, max_output_bytes).to_int64()
    stage_file(path, expanded)
  }
  let write_module = fn(module_info : TreeModule) raise {
    stage(ModuleArtifact(module_info.package_name, module_info.path))
    let mut cursor = None
    while true {
      let page = self.members(
        module_info.package_name,
        module_info.path,
        limit=limits.page_size,
        cursor?,
      )
      for entry in page.items {
        if entry.document == module_info.document {
          // The containing module is already staged. Check the inline
          // definition without writing another file for the same identity.
          ignore(
            self.read_member(
              entry.package_name,
              entry.module_name,
              entry.kind,
              entry.name,
            ),
          )
        } else {
          stage(
            MemberArtifact(
              entry.package_name,
              entry.module_name,
              entry.kind,
              entry.name,
            ),
          )
        }
      }
      guard page.next is Some(_) else { break }
      cursor = page.next
    }
  }
  let write_package = fn(package_name) raise {
    let mut cursor = None
    while true {
      let page = self.modules(package_name, limit=limits.page_size, cursor?)
      for module_info in page.items {
        write_module(module_info)
      }
      guard page.next is Some(_) else { break }
      cursor = page.next
    }
  }
  stage(ManifestArtifact)
  write_package(self.package_name())
  for dependency in self.dependency_packages() {
    write_package(dependency)
  }
  self.check_revision()
}

///|
fn decode_tree_member(
  version : @version.FormatVersion,
  kind : TreeMemberKind,
  role : TreeRole,
  payload : Json,
  context : @wire.DocumentNameContext?,
  preserve_input_order : Bool,
) -> TreeMemberBody raise {
  if version.major == 3U {
    let type_attribute = fn(value) raise { @wire.unit(value) }
    match (kind, role) {
      (TypeMember, Definition) =>
        V3TypeDefinition(
          @v3_json.read_access(payload, fn(doc) raise {
            @v3_json.read_documented(doc, fn(value) raise {
              @v3_json.read_type_definition_with_context(
                value, type_attribute, context,
              )
            })
          }),
        )
      (ValueMember, Definition) =>
        V3ValueDefinition(
          @v3_json.read_access(payload, fn(doc) raise {
            @v3_json.read_documented(doc, fn(value) raise {
              @v3_json.read_value_definition_with_context(
                value,
                type_attribute,
                fn(attribute) raise {
                  @v3_json.read_type_with_context(
                    attribute, type_attribute, context,
                  )
                },
                context,
              )
            })
          }),
        )
      (TypeMember, Specification) =>
        V3TypeSpecification(
          @v3_json.read_documented(payload, fn(value) raise {
            @v3_json.read_type_specification_with_context(
              value, type_attribute, context,
            )
          }),
        )
      (ValueMember, Specification) =>
        V3ValueSpecification(
          @v3_json.read_documented(payload, fn(value) raise {
            @v3_json.read_value_specification_with_context(
              value, type_attribute, context,
            )
          }),
        )
    }
  } else {
    match (kind, role) {
      (TypeMember, Definition) =>
        V4TypeDefinition(
          @v4_json.read_access(payload, fn(doc) raise {
            @v4_json.read_documented(doc, fn(value) raise {
              @v4_json.read_type_definition_with_context(value, context)
            })
          }),
        )
      (ValueMember, Definition) =>
        V4ValueDefinition(
          @v4_json.read_access(payload, fn(doc) raise {
            @v4_json.read_documented(doc, fn(value) raise {
              @v4_json.read_definition_with_context(
                value,
                context,
                preserve_input_order~,
              )
            })
          }),
        )
      (TypeMember, Specification) =>
        V4TypeSpecification(
          @v4_json.read_documented(payload, fn(value) raise {
            @v4_json.read_type_specification_with_context(
              value,
              context,
              preserve_input_order~,
            )
          }),
        )
      (ValueMember, Specification) =>
        V4ValueSpecification(
          @v4_json.read_documented(payload, fn(value) raise {
            @v4_json.read_value_specification_with_context(
              value,
              context,
              preserve_input_order~,
            )
          }),
        )
    }
  }
}
