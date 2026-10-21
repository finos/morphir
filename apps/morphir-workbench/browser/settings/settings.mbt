// Workbench settings: choices that belong to the person using this browser, not to a workspace. They are saved
// under one key for the whole Workbench. Decoding never fails: a missing, unreadable or unknown value is the default.

///|
/// The browser storage key of the settings. The head script of `index.html` reads the same key.
pub let storage_key : String = "morphir-workbench.settings.v1"

///|
/// The person's theme choice. System follows the operating system and browser setting.
pub(all) enum ThemePreference {
  System
  Light
  Dark
} derive(Eq, Debug)

///|
pub extend ThemePreference with Eq::{equal, not_equal}

///|
pub extend ThemePreference with @debug.Debug::{to_repr}

///|
/// What the page shows.
pub(all) enum Appearance {
  Light
  Dark
} derive(Eq, Debug)

///|
pub extend Appearance with Eq::{equal, not_equal}

///|
pub extend Appearance with @debug.Debug::{to_repr}

///|
/// The theme choices in the order that the theme toggle cycles through them.
pub let themes : Array[ThemePreference] = [System, Light, Dark]

///|
/// The appearance for this choice when the system shows `system`.
pub fn ThemePreference::resolve(
  self : ThemePreference,
  system~ : Appearance,
) -> Appearance {
  match self {
    System => system
    Light => Light
    Dark => Dark
  }
}

///|
/// The choice after this one in the theme toggle: System, Light, Dark, then System again.
pub fn ThemePreference::next(self : ThemePreference) -> ThemePreference {
  match self {
    System => Light
    Light => Dark
    Dark => System
  }
}

///|
/// The name people see, such as `System`.
pub fn ThemePreference::label(self : ThemePreference) -> String {
  match self {
    System => "System"
    Light => "Light"
    Dark => "Dark"
  }
}

///|
/// The stored spelling, such as `system`; it also names the theme's icon.
pub fn ThemePreference::id(self : ThemePreference) -> String {
  match self {
    System => "system"
    Light => "light"
    Dark => "dark"
  }
}

///|
/// The choice that `text` spells, as `id` writes it.
pub fn ThemePreference::parse(text : String) -> ThemePreference? {
  themes.iter().find_first(theme => theme.id() == text)
}

///|
/// The value of the root element's `data-theme` attribute: none for System, so the stylesheet follows the system.
pub fn ThemePreference::data_theme(self : ThemePreference) -> String? {
  match self {
    System => None
    Light => Some("light")
    Dark => Some("dark")
  }
}

///|
pub fn Appearance::label(self : Appearance) -> String {
  match self {
    Light => "light"
    Dark => "dark"
  }
}

///|
/// How the workspace sidebar at the left edge shows the open workspaces.
pub(all) enum WorkspaceSidebar {
  /// Icons, and a tile with initials per open workspace.
  Collapsed
  /// A card per open workspace with its name, kind and state.
  Expanded
} derive(Eq, Debug)

///|
pub extend WorkspaceSidebar with Eq::{equal, not_equal}

///|
pub extend WorkspaceSidebar with @debug.Debug::{to_repr}

///|
/// The other state: what the expand or collapse button changes to.
pub fn WorkspaceSidebar::toggle(self : WorkspaceSidebar) -> WorkspaceSidebar {
  match self {
    Collapsed => Expanded
    Expanded => Collapsed
  }
}

///|
/// How a source document shows its source and its output (Morphir IR or generated files).
pub(all) enum EditorLayout {
  /// Source and output side by side, each pane able to take the full width.
  SideBySide
  /// Source, Morphir IR and Generated as separate tabs, one at a time.
  Tabs
} derive(Eq, Debug)

///|
pub extend EditorLayout with Eq::{equal, not_equal}

///|
pub extend EditorLayout with @debug.Debug::{to_repr}

///|
/// The editor layouts in the order the settings page lists them.
pub let editor_layouts : Array[EditorLayout] = [SideBySide, Tabs]

///|
/// The name people see.
pub fn EditorLayout::label(self : EditorLayout) -> String {
  match self {
    SideBySide => "Side by side"
    Tabs => "Tabs"
  }
}

///|
/// The stored spelling.
pub fn EditorLayout::id(self : EditorLayout) -> String {
  match self {
    SideBySide => "side-by-side"
    Tabs => "tabs"
  }
}

///|
/// The Workbench settings.
pub(all) struct Settings {
  theme : ThemePreference
  workspace_sidebar : WorkspaceSidebar
  editor_layout : EditorLayout
} derive(Eq, Debug)

///|
pub extend Settings with Eq::{equal, not_equal}

///|
pub extend Settings with @debug.Debug::{to_repr}

///|
pub fn Settings::default() -> Settings {
  { theme: System, workspace_sidebar: Collapsed, editor_layout: SideBySide, }
}

///|
/// The settings that saved text describes. Text that is empty, not JSON or not an object gives the defaults, and a
/// field with an unknown value keeps its default.
pub fn Settings::decode(text : String) -> Settings {
  let value = @json.parse(text) catch { _ => return Settings::default() }
  guard value is Object(fields) else { return Settings::default() }
  let theme = match fields.get("theme") {
    Some(String(spelled)) => ThemePreference::parse(spelled).unwrap_or(System)
    _ => System
  }
  let workspace_sidebar : WorkspaceSidebar = match
    fields.get("workspaceSidebar") {
    Some(String("expanded")) => Expanded
    _ => Collapsed
  }
  let editor_layout : EditorLayout = match fields.get("editorLayout") {
    Some(String("tabs")) => Tabs
    _ => SideBySide
  }
  { theme, workspace_sidebar, editor_layout, }
}

///|
/// The text to save, which `decode` reads back. The workspace sidebar and the editor layout are written only when
/// they differ from the defaults, so the default settings keep the text that earlier pages wrote.
pub fn Settings::encode(self : Settings) -> String {
  let value : Map[String, Json] = { "theme": Json::string(self.theme.id()) }
  if self.workspace_sidebar is Expanded {
    value["workspaceSidebar"] = Json::string("expanded")
  }
  if self.editor_layout is Tabs {
    value["editorLayout"] = Json::string("tabs")
  }
  Json::object(value).stringify()
}
