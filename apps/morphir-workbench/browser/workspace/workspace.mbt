// Workbench workspaces: identified user-facing contexts that hold intent, conceptual models, source projects,
// model documents and scratch work. A preset seeds a workspace's first contents; it never restricts what the
// workspace can hold later. This is not the engine's root-based Workspace, and it grants no host authority.

///|
/// The identity of a workbench workspace, stable for its whole life in this browser.
pub struct WorkspaceId {
  priv value : Int32
} derive(Eq, Hash, Debug)

///|
pub extend WorkspaceId with Eq::{equal, not_equal}

///|
pub extend WorkspaceId with Hash::{hash, hash_combine}

///|
pub extend WorkspaceId with @debug.Debug::{to_repr}

///|
pub impl Show for WorkspaceId with fn output(self, logger) {
  logger.write_string("w" + self.value.to_string())
}

///|
pub extend WorkspaceId with Show::{to_string, output}

///|
/// The id that `text` spells, such as `w3`.
pub fn WorkspaceId::parse(text : String) -> WorkspaceId? {
  guard text.has_prefix("w") && text.length() > 1 && text.length() < 10 else {
    return None
  }
  let digits = text[1:].to_owned()
  guard digits.iter().all(c => c >= '0' && c <= '9') && !digits.has_prefix("0") else {
    return None
  }
  let mut value = 0
  for c in digits {
    value = value * 10 + (c.to_int() - '0'.to_int())
  }
  if value > 0 {
    Some({ value, })
  } else {
    None
  }
}

///|
/// A workspace name a person can read: trimmed, between 1 and 80 characters, without control characters.
pub struct WorkspaceName {
  priv text : String
} derive(Eq, Debug)

///|
pub extend WorkspaceName with Eq::{equal, not_equal}

///|
pub extend WorkspaceName with @debug.Debug::{to_repr}

///|
pub impl Show for WorkspaceName with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend WorkspaceName with Show::{to_string, output}

///|
pub let max_name_length : Int32 = 80

///|
/// The name `text` gives, or why it is not a workspace name.
pub fn WorkspaceName::parse(text : String) -> Result[WorkspaceName, String] {
  let trimmed = text.trim().to_owned()
  if trimmed == "" {
    Err("Enter a name for the workspace")
  } else if trimmed.length() > max_name_length {
    Err("Use at most \{max_name_length} characters")
  } else if trimmed.iter().any(c => c.to_int() < 32 || c.to_int() == 127) {
    Err("Remove control characters from the name")
  } else {
    Ok({ text: trimmed, })
  }
}

///|
/// How a workspace starts. A preset is a starting point, not a kind: any workspace can later hold any content.
pub(all) enum Preset {
  Empty
  SourceProject
  ModelExploration
  Sandbox
} derive(Eq, Debug)

///|
pub extend Preset with Eq::{equal, not_equal}

///|
pub extend Preset with @debug.Debug::{to_repr}

///|
pub let presets : Array[Preset] = [
  Empty,
  SourceProject,
  ModelExploration,
  Sandbox,
]

///|
pub fn Preset::id(self : Preset) -> String {
  match self {
    Empty => "empty"
    SourceProject => "source"
    ModelExploration => "model"
    Sandbox => "sandbox"
  }
}

///|
pub fn Preset::from_id(id : String) -> Preset? {
  presets.iter().find_first(preset => preset.id() == id)
}

///|
pub fn Preset::label(self : Preset) -> String {
  match self {
    Empty => "Empty workspace"
    SourceProject => "Source project"
    ModelExploration => "Model exploration"
    Sandbox => "Sandbox"
  }
}

///|
/// The name a new workspace of this preset gets when the person gives none.
pub fn Preset::base_name(self : Preset) -> String {
  match self {
    Empty => "Workspace"
    SourceProject => "Source project"
    ModelExploration => "Model"
    Sandbox => "Sandbox"
  }
}

///|
/// A kind of content a workspace holds. Intent and conceptual models are the person's own drafts; they are not
/// executable Morphir IR and are not compiled or inferred.
pub(all) enum Content {
  Intent
  ConceptualModel
  SourceProject
  ModelDocument
  Worksheet
} derive(Eq, Debug)

///|
pub extend Content with Eq::{equal, not_equal}

///|
pub extend Content with @debug.Debug::{to_repr}

///|
pub let contents : Array[Content] = [
  Intent,
  ConceptualModel,
  SourceProject,
  ModelDocument,
  Worksheet,
]

///|
pub fn Content::id(self : Content) -> String {
  match self {
    Intent => "intent"
    ConceptualModel => "conceptual-model"
    SourceProject => "source-project"
    ModelDocument => "model"
    Worksheet => "worksheet"
  }
}

///|
pub fn Content::from_id(id : String) -> Content? {
  contents.iter().find_first(content => content.id() == id)
}

///|
pub fn Content::label(self : Content) -> String {
  match self {
    Intent => "Modeling intent"
    ConceptualModel => "Conceptual model"
    SourceProject => "Source project"
    ModelDocument => "Model"
    Worksheet => "Worksheet"
  }
}

///|
/// The document in the central area: the source editor (also the worksheet), the model inspector, the intent draft
/// or the conceptual model draft. Selecting a document never changes the workspace.
pub(all) enum Document {
  Source
  Model
  IntentDraft
  ConceptDraft
} derive(Eq, Debug)

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
/// The documents a workspace with `held` contents offers, in tab order. A connected host's workspace always has its
/// source and its model.
pub fn documents(held : Array[Content], connected~ : Bool) -> Array[Document] {
  let shown : Array[Document] = []
  if connected || held.contains(SourceProject) || held.contains(Worksheet) {
    shown.push(Source)
  }
  if connected || held.contains(SourceProject) || held.contains(ModelDocument) {
    shown.push(Model)
  }
  if held.contains(Intent) {
    shown.push(IntentDraft)
  }
  if held.contains(ConceptualModel) {
    shown.push(ConceptDraft)
  }
  shown
}

///|
/// The explorer views a workspace with `held` contents offers. A model-only workspace has no Files view, and only a
/// workspace that can compile source has a Generated view.
pub fn views(held : Array[Content], connected~ : Bool) -> Array[@shell.View] {
  let shown : Array[@shell.View] = []
  if !connected && held.contains(SourceProject) {
    shown.push(Files)
  }
  if connected || held.contains(SourceProject) || held.contains(ModelDocument) {
    shown.push(Models)
  }
  if held.contains(Intent) ||
    held.contains(ConceptualModel) ||
    held.contains(Worksheet) {
    shown.push(Ideas)
  }
  if connected || held.contains(SourceProject) {
    shown.push(Generated)
  }
  shown
}

///|
/// Where a workspace keeps its source projects. Projects saved before workspaces existed keep their earlier keys.
pub(all) enum Storage {
  Legacy
  Scoped
} derive(Eq, Debug)

///|
pub extend Storage with Eq::{equal, not_equal}

///|
pub extend Storage with @debug.Debug::{to_repr}

///|
/// Where a workspace's files live, as a path people can read. The Workbench keeps in-memory and browser-stored
/// workspaces at a virtual path, `memory://workspaces/<slug>`; a connected host's workspace is at the host.
pub(all) enum WorkspaceLocation {
  /// A virtual path under `memory://workspaces/`. The slug is chosen once, from the name, and stays when the
  /// workspace is renamed.
  Memory(String)
  /// The origin of the connected host that provides the workspace.
  Connected(String)
} derive(Eq, Debug)

///|
pub extend WorkspaceLocation with Eq::{equal, not_equal}

///|
pub extend WorkspaceLocation with @debug.Debug::{to_repr}

///|
/// The prefix of every in-memory workspace path.
let memory_root : String = "memory://workspaces/"

///|
/// The location as a URI, such as `memory://workspaces/pricing-model`.
pub fn WorkspaceLocation::to_uri(self : WorkspaceLocation) -> String {
  match self {
    Memory(slug) => memory_root + slug
    Connected(origin) => origin
  }
}

///|
/// The in-memory location that `uri` spells, or `None` for any other text.
pub fn WorkspaceLocation::parse_memory(uri : String) -> WorkspaceLocation? {
  guard uri.has_prefix(memory_root) else { return None }
  let slug = uri.unsafe_substring(start=memory_root.length(), end=uri.length())
  if slug != "" && slug_of(slug) == slug {
    Some(Memory(slug))
  } else {
    None
  }
}

///|
/// A path segment for `name`: lower-case letters and digits, with single dashes between words. A name without
/// either gives `workspace`.
pub fn slug_of(name : String) -> String {
  let out = StringBuilder()
  let mut dash = false
  for c in name.to_lower() {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      if dash && out.to_string() != "" {
        out.write_char('-')
      }
      out.write_char(c)
      dash = false
    } else {
      dash = true
    }
  }
  match out.to_string() {
    "" => "workspace"
    slug => slug
  }
}

///|
/// One workspace: its identity, name, starting preset, contents, project storage, layout and when it was last
/// opened. `saved` is false for a provisional workspace whose folder or model has not arrived yet, and for a
/// connected host's workspace, which this browser does not keep.
pub(all) struct Entry {
  id : WorkspaceId
  name : WorkspaceName
  preset : Preset
  contents : Array[Content]
  storage : Storage
  opened : Int32
  saved : Bool
  layout : @shell.Layout
  /// The source language the workspace had selected, so a reopened workspace shows the same project.
  language : @ids.LanguageId?
  location : WorkspaceLocation
} derive(Eq, Debug)

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
/// The key of this browser's list of workspaces.
pub let registry_key : String = "morphir-workbench.workspaces.v1"

///|
/// The key of the source project for `language`.
pub fn Entry::project_key(self : Entry, language : String) -> String {
  match self.storage {
    Legacy => "morphir-workbench.project." + language + ".v1"
    Scoped =>
      "morphir-workbench.workspace." +
      self.id.to_string() +
      ".project." +
      language +
      ".v1"
  }
}

///|
/// The key of a text draft: the intent, the conceptual model or the worksheet.
pub fn Entry::draft_key(self : Entry, content : Content) -> String {
  "morphir-workbench.workspace." +
  self.id.to_string() +
  "." +
  content.id() +
  ".v1"
}

///|
/// Every key this workspace may have written, for `languages`.
pub fn Entry::keys(self : Entry, languages : Array[String]) -> Array[String] {
  [
    ..languages.map(language => self.project_key(language)),
    self.draft_key(Intent),
    self.draft_key(ConceptualModel),
    self.draft_key(Worksheet),
  ]
}

///|
pub fn Entry::holds(self : Entry, content : Content) -> Bool {
  self.contents.contains(content)
}

///|
/// The workspaces of this page: saved ones, provisional ones and the connected host's.
pub struct Registry {
  entries : Array[Entry]
  priv next : Int32
  priv clock : Int32
} derive(Eq, Debug)

///|
pub extend Registry with Eq::{equal, not_equal}

///|
pub extend Registry with @debug.Debug::{to_repr}

///|
pub fn Registry::new() -> Registry {
  { entries: [], next: 1, clock: 0, }
}

///|
pub fn Registry::get(self : Registry, id : WorkspaceId) -> Entry? {
  self.entries.iter().find_first(entry => entry.id == id)
}

///|
fn Registry::change(
  self : Registry,
  id : WorkspaceId,
  change : (Entry) -> Entry,
) -> Registry {
  {
    ..self,
    entries: self.entries.map(e => if e.id == id { change(e) } else { e }),
  }
}

///|
/// `base` when no workspace has that name, else `base 2`, `base 3` and so on.
pub fn Registry::unique_name(self : Registry, base : String) -> WorkspaceName {
  let taken = fn(name : String) {
    self.entries.iter().any(entry => entry.name.to_string() == name)
  }
  let mut candidate = base
  let mut counter = 2
  while taken(candidate) {
    candidate = base + " " + counter.to_string()
    counter += 1
  }
  WorkspaceName::parse(candidate).unwrap_or({ text: "Workspace", })
}

///|
/// An in-memory location for `name` that no other workspace has: its slug, numbered when it is taken.
pub fn Registry::unique_location(
  self : Registry,
  name : String,
) -> WorkspaceLocation {
  let base = slug_of(name)
  let taken = self.entries.map(e => e.location)
  let mut slug = base
  let mut n = 2
  while taken.contains(Memory(slug)) {
    slug = base + "-" + n.to_string()
    n += 1
  }
  Memory(slug)
}

///|
/// Adds a workspace and opens it: it becomes the most recent one. Without `name`, it gets the preset's name,
/// numbered when that name is taken. A provisional workspace (`saved=false`) is not listed or kept until `save`.
pub fn Registry::create(
  self : Registry,
  preset : Preset,
  name? : WorkspaceName,
  contents~ : Array[Content] = [],
  saved~ : Bool = true,
  storage~ : Storage = Scoped,
  layout~ : @shell.Layout = @shell.Layout::default(),
  location? : WorkspaceLocation,
) -> (Registry, Entry) {
  let held : Array[Content] = []
  for content in contents {
    if !held.contains(content) {
      held.push(content)
    }
  }
  let name = name.unwrap_or(self.unique_name(preset.base_name()))
  let entry = {
    id: { value: self.next, },
    name,
    preset,
    contents: held,
    storage,
    opened: self.clock + 1,
    saved,
    layout,
    language: None,
    location: location.unwrap_or(self.unique_location(name.to_string())),
  }
  (
    {
      entries: [..self.entries, entry],
      next: self.next + 1,
      clock: self.clock + 1,
    },
    entry,
  )
}

///|
/// Makes the workspace the most recently opened one.
pub fn Registry::touch(self : Registry, id : WorkspaceId) -> Registry {
  guard self.get(id) is Some(_) else { return self }
  {
    ..self.change(id, e => { ..e, opened: self.clock + 1, }),
    clock: self.clock + 1,
  }
}

///|
/// Adds content to the workspace; content it already holds changes nothing.
pub fn Registry::add(
  self : Registry,
  id : WorkspaceId,
  content : Content,
) -> Registry {
  self.change(id, e => {
    if e.contents.contains(content) {
      e
    } else {
      { ..e, contents: [..e.contents, content], }
    }
  })
}

///|
/// Keeps a provisional workspace: its folder or model arrived.
pub fn Registry::save(self : Registry, id : WorkspaceId) -> Registry {
  self.change(id, e => { ..e, saved: true, })
}

///|
pub fn Registry::rename(
  self : Registry,
  id : WorkspaceId,
  name : WorkspaceName,
) -> Registry {
  self.change(id, e => { ..e, name, })
}

///|
pub fn Registry::set_layout(
  self : Registry,
  id : WorkspaceId,
  layout : @shell.Layout,
) -> Registry {
  self.change(id, e => { ..e, layout, })
}

///|
pub fn Registry::set_language(
  self : Registry,
  id : WorkspaceId,
  language : @ids.LanguageId,
) -> Registry {
  self.change(id, e => { ..e, language: Some(language), })
}

///|
/// Cached summary only: the workspace files determine these contents on opening.
pub fn Registry::set_contents(
  self : Registry,
  id : WorkspaceId,
  contents : Array[Content],
) -> Registry {
  self.change(id, entry => { ..entry, contents: contents.copy(), })
}

///|
/// Makes sure new workspaces get numbers above `number`, such as the highest number among keys this browser
/// already holds, so a new workspace never reads another workspace's saved projects.
pub fn Registry::reserve(self : Registry, number : Int32) -> Registry {
  if number >= self.next {
    { ..self, next: number + 1, }
  } else {
    self
  }
}

///|
/// The workspace numbers that `keys` (browser storage keys) belong to.
pub fn numbers_in_keys(keys : Array[String]) -> Int32 {
  let prefix = "morphir-workbench.workspace.w"
  keys.fold(init=0, (high, key) => {
    guard key.has_prefix(prefix) else { return high }
    let rest = key[prefix.length():].to_owned()
    let digits = match rest.find(".") {
      Some(dot) => rest[:dot].to_owned()
      None => rest
    }
    match WorkspaceId::parse("w" + digits) {
      Some(id) if id.value > high => id.value
      _ => high
    }
  })
}

///|
/// This page's registry combined with the one another page saved since: workspaces only the other page knows are
/// added, `removed` ones stay out, and numbering continues after both. This page's entries win for shared ids.
pub fn Registry::merge(
  self : Registry,
  stored : Registry,
  removed~ : Array[WorkspaceId] = [],
) -> Registry {
  let entries = self.entries.copy()
  for entry in stored.entries {
    if !entries.iter().any(e => e.id == entry.id) && !removed.contains(entry.id) {
      entries.push(entry)
    }
  }
  {
    entries,
    next: if stored.next > self.next {
      stored.next
    } else {
      self.next
    },
    clock: if stored.clock > self.clock {
      stored.clock
    } else {
      self.clock
    },
  }
}

///|
pub fn Registry::remove(self : Registry, id : WorkspaceId) -> Registry {
  { ..self, entries: self.entries.filter(e => e.id != id), }
}

///|
/// Saved workspaces, most recently opened first, without `except`. Only workspaces that were really opened are
/// listed; a provisional or connected workspace is not.
pub fn Registry::recents(
  self : Registry,
  except~ : WorkspaceId? = None,
) -> Array[Entry] {
  let listed = self.entries.filter(e => {
    e.saved && e.opened > 0 && Some(e.id) != except
  })
  listed.sort_by((a, b) => b.opened.compare(a.opened))
  listed
}

///|
/// Adds "My project" for source projects saved before workspaces existed, unless the registry already has it.
pub fn Registry::adopt_legacy(self : Registry) -> (Registry, Entry) {
  match self.entries.iter().find_first(e => e.storage is Legacy) {
    Some(entry) => (self, entry)
    None =>
      self.create(
        SourceProject,
        name=self.unique_name("My project"),
        contents=[SourceProject],
        storage=Legacy,
      )
  }
}

///|
/// The saved workspaces as JSON for browser storage.
pub fn Registry::to_json(self : Registry) -> Json {
  let saved = self.entries.filter(e => e.saved)
  {
    "version": Json::number(1),
    "next": Json::number(self.next.to_double()),
    "clock": Json::number(self.clock.to_double()),
    "workspaces": Json::array(
      saved.map(e => {
        (
          {
            "id": Json::string(e.id.to_string()),
            "name": Json::string(e.name.to_string()),
            "preset": Json::string(e.preset.id()),
            "contents": Json::array(e.contents.map(c => Json::string(c.id()))),
            "storage": Json::string(
              match e.storage {
                Legacy => "legacy"
                Scoped => "scoped"
              },
            ),
            "opened": Json::number(e.opened.to_double()),
            "layout": e.layout.to_json(),
            "language": match e.language {
              Some(language) => Json::string(language.to_string())
              None => Json::null()
            },
            "location": Json::string(e.location.to_uri()),
          } : Json)
      }),
    ),
  }
}

///|
fn number(value : Json?) -> Int32? {
  match value {
    Some(Number(n, ..)) if n >= 0.0 && n < 1.0e9 && n == n.floor() =>
      Some(n.to_int())
    _ => None
  }
}

///|
/// The registry that saved JSON describes, and a problem for each workspace it could not read. Unreadable
/// workspaces are left out; their stored projects stay where they are.
pub fn Registry::from_json(value : Json) -> (Registry, Array[String]) {
  guard value is Object(fields) && fields.get("version") is Some(Number(1, ..)) else {
    return (
      Registry::new(),
      if value == Json::null() {
        []
      } else {
        ["The saved workspace list has an unknown format; it was not read"]
      },
    )
  }
  let problems : Array[String] = []
  let entries : Array[Entry] = []
  let workspaces = match fields.get("workspaces") {
    Some(Array(items)) => items
    _ => []
  }
  for item in workspaces {
    let entry : Entry? = if item is Object(e) &&
      e.get("id") is Some(String(id_text)) &&
      WorkspaceId::parse(id_text) is Some(id) &&
      e.get("name") is Some(String(name_text)) &&
      WorkspaceName::parse(name_text) is Ok(name) &&
      e.get("preset") is Some(String(preset_text)) &&
      Preset::from_id(preset_text) is Some(preset) &&
      number(e.get("opened")) is Some(opened) &&
      !entries.iter().any(other => other.id == id) {
      let held : Array[Content] = []
      if e.get("contents") is Some(Array(listed)) {
        for c in listed {
          if c is String(content_id) &&
            Content::from_id(content_id) is Some(content) &&
            !held.contains(content) {
            held.push(content)
          }
        }
      }
      Some({
        id,
        name,
        preset,
        contents: held,
        storage: if e.get("storage") is Some(String("legacy")) {
          Legacy
        } else {
          Scoped
        },
        opened,
        saved: true,
        layout: @shell.Layout::from_json(
          e.get("layout").unwrap_or(Json::null()),
          @shell.Layout::default(),
        ),
        language: match e.get("language") {
          Some(String(text)) =>
            Some(@ids.LanguageId::parse(text)) catch {
              _ => None
            }
          _ => None
        },
        // Workspaces saved before locations existed get one from their name.
        location: match e.get("location") {
          Some(String(uri)) =>
            match WorkspaceLocation::parse_memory(uri) {
              Some(location) if !entries.iter().any(o => o.location == location) =>
                location
              _ =>
                ({ entries, next: 0, clock: 0, } : Registry).unique_location(
                  name_text,
                )
            }
          _ =>
            ({ entries, next: 0, clock: 0, } : Registry).unique_location(
              name_text,
            )
        },
      })
    } else {
      None
    }
    match entry {
      Some(entry) => entries.push(entry)
      None =>
        problems.push("A saved workspace could not be read and was left out")
    }
  }
  let highest = entries.fold(init=0, (high, e) => {
    if e.id.value > high {
      e.id.value
    } else {
      high
    }
  })
  let latest = entries.fold(init=0, (high, e) => {
    if e.opened > high {
      e.opened
    } else {
      high
    }
  })
  let next = number(fields.get("next")).unwrap_or(0)
  let clock = number(fields.get("clock")).unwrap_or(0)
  (
    {
      entries,
      next: if next > highest {
        next
      } else {
        highest + 1
      },
      clock: if clock > latest {
        clock
      } else {
        latest
      },
    },
    problems,
  )
}
