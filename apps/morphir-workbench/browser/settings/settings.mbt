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
/// The Workbench settings.
pub(all) struct Settings {
  theme : ThemePreference
} derive(Eq, Debug)

///|
pub extend Settings with Eq::{equal, not_equal}

///|
pub extend Settings with @debug.Debug::{to_repr}

///|
pub fn Settings::default() -> Settings {
  { theme: System, }
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
  { theme, }
}

///|
/// The text to save, which `decode` reads back.
pub fn Settings::encode(self : Settings) -> String {
  let value : Json = { "theme": Json::string(self.theme.id()) }
  value.stringify()
}
