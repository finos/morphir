///|
/// A command that a shortcut, a menu or the command palette runs.
pub(all) enum CommandId {
  Compile
  Run
  GoToFile
  ShowCommands
  SwitchLanguage
  SetTarget
  NewFile
  RenameFile
  DeleteFile
  CopyPath
  CollapseFolders
  ToggleExposed
  RenamePackage
  /// Opens the example or sample with this id.
  LoadSample(String)
  /// Decodes the selected generated binary Ion file to text.
  ViewIonText
  ImportFolder
  ResetProject
  TogglePanel
  SwitchLayout
  ShowExplorer
  ContextMenu
  /// Shows the source editor, the model inspector or a draft of the active workspace.
  ShowSource
  ShowModel
  ShowIntent
  ShowConcept
  ShowGettingStarted
  /// Chooses another open or saved workspace.
  SwitchWorkspace
  /// Saves the active workspace and closes it.
  CloseWorkspace
  CreateWorkspace
  TryIdea
  OpenWorkspace
  ExploreModel
  AddIntent
  AddConceptualModel
  AddSourceProject
  ImportModel
  TogglePrimarySidebar
  ToggleSecondarySidebar
  /// Moves an explorer view to the other sidebar.
  MoveFiles
  MoveModels
  MoveGenerated
  MoveIdeas
  ShowGeneratedFiles
  /// Chooses the source profile of the active language.
  SelectProfile
  ShowProfileDetails
  /// Shows the settings page. It has no shortcut: browsers keep Command or Control and comma for their own settings.
  OpenSettings
  UseSystemTheme
  UseLightTheme
  UseDarkTheme
  /// Moves to the next theme: System, Light, Dark, then System again.
  ToggleTheme
} derive(Eq, Debug)

///|
/// A key with its modifiers. `primary` is Command on macOS and Control elsewhere; `other` is a modifier that no
/// shortcut uses (Control on macOS, Meta elsewhere), so a chord with it matches nothing.
pub(all) struct Chord {
  key : String
  primary : Bool
  shift : Bool
  alt : Bool
  other : Bool
} derive(Eq, Debug)

///|
/// The spelling of `KeyboardEvent.key` that chords use: one letter in upper case, `Space` for the space bar, and the
/// current names of keys that old browsers spell differently.
fn normalize(key : String) -> String {
  match key {
    " " | "Spacebar" => "Space"
    "Esc" => "Escape"
    "Del" => "Delete"
    "Apps" => "ContextMenu"
    "Up" => "ArrowUp"
    "Down" => "ArrowDown"
    "Left" => "ArrowLeft"
    "Right" => "ArrowRight"
    _ => if key.length() == 1 { key.to_upper() } else { key }
  }
}

///|
/// The chord of a keyboard event. On macOS, Command is the primary modifier; elsewhere, Control is.
pub fn Chord::from_event(
  key : String,
  ctrl~ : Bool,
  meta~ : Bool,
  shift~ : Bool,
  alt~ : Bool,
  mac~ : Bool,
) -> Chord {
  {
    key: normalize(key),
    primary: if mac {
      meta
    } else {
      ctrl
    },
    shift,
    alt,
    other: if mac {
      ctrl
    } else {
      meta
    },
  }
}

///|
/// A chord without modifiers.
pub fn Chord::plain(key : String) -> Chord {
  {
    key: normalize(key),
    primary: false,
    shift: false,
    alt: false,
    other: false,
  }
}

///|
/// True when no modifier other than Shift is held, as for typing a character.
pub fn Chord::is_typing(self : Chord) -> Bool {
  !self.primary && !self.alt && !self.other
}

///|
/// True when the chord types one printable character, such as a letter or a digit.
pub fn Chord::is_character(self : Chord) -> Bool {
  self.is_typing() && self.key.length() == 1 && self.key != " "
}

///|
fn mac_key(key : String) -> String {
  match key {
    "Enter" => "↩"
    "Backspace" => "⌫"
    "Delete" => "⌦"
    "Escape" => "⎋"
    "ArrowUp" => "↑"
    "ArrowDown" => "↓"
    "ArrowLeft" => "←"
    "ArrowRight" => "→"
    "ContextMenu" => "Menu"
    _ => key
  }
}

///|
/// The chord as a person reads it: `⇧⌘P` on macOS and `Ctrl+Shift+P` elsewhere.
pub fn Chord::label(self : Chord, mac~ : Bool) -> String {
  if mac {
    (if self.alt { "⌥" } else { "" }) +
    (if self.shift { "⇧" } else { "" }) +
    (if self.primary { "⌘" } else { "" }) +
    mac_key(self.key)
  } else {
    let parts : Array[String] = []
    if self.primary {
      parts.push("Ctrl")
    }
    if self.alt {
      parts.push("Alt")
    }
    if self.shift {
      parts.push("Shift")
    }
    parts.push(if self.key == "ContextMenu" { "Menu" } else { self.key })
    parts.join("+")
  }
}

///|
/// The chord in the syntax of `aria-keyshortcuts`, such as `Control+Shift+P` or `Meta+Enter`.
pub fn Chord::aria(self : Chord, mac~ : Bool) -> String {
  let parts : Array[String] = []
  if self.primary {
    parts.push(if mac { "Meta" } else { "Control" })
  }
  if self.alt {
    parts.push("Alt")
  }
  if self.shift {
    parts.push("Shift")
  }
  parts.push(self.key)
  parts.join("+")
}

///|
/// Where a shortcut works. `Anywhere` shortcuts also work while a person types in the editor or a text field, as
/// editors allow for the palette and quick open. `Tree` shortcuts work only on a focused row of the project tree.
pub(all) enum Scope {
  Anywhere
  Tree
} derive(Eq, Debug)

///|
/// On which systems menus and the palette show a binding. Every binding works everywhere; this only picks the
/// chord people on that system expect to see, such as ⌘⌫ rather than ⌦ on a Mac keyboard.
pub(all) enum Shown {
  Everywhere
  OnMac
  OffMac
} derive(Eq, Debug)

///|
pub(all) struct Binding {
  chord : Chord
  command : CommandId
  scope : Scope
  shown : Shown
} derive(Eq, Debug)

///|
/// Where the keyboard focus is when a key goes down.
pub(all) struct Context {
  /// Focus is in a text field or the code editor.
  editing : Bool
  /// Focus is on a row of the project tree.
  in_tree : Bool
} derive(Eq, Debug)

///|
fn bind(
  key : String,
  command : CommandId,
  primary~ : Bool = false,
  shift~ : Bool = false,
  scope~ : Scope = Anywhere,
  shown~ : Shown = Everywhere,
) -> Binding {
  {
    chord: { key, primary, shift, alt: false, other: false, },
    command,
    scope,
    shown,
  }
}

///|
/// The workbench shortcuts. Menus and the palette show these chords, so a shortcut is shown where it works.
pub fn keymap() -> Array[Binding] {
  [
    bind("P", GoToFile, primary=true),
    bind("P", ShowCommands, primary=true, shift=true),
    bind("F1", ShowCommands),
    bind("Enter", Compile, primary=true),
    bind("B", TogglePrimarySidebar, primary=true),
    bind("F2", RenameFile, scope=Tree),
    bind("Delete", DeleteFile, scope=Tree, shown=OffMac),
    bind("Backspace", DeleteFile, primary=true, scope=Tree, shown=OnMac),
    bind("F10", ContextMenu, shift=true, scope=Tree),
    bind("ContextMenu", ContextMenu, scope=Tree),
  ]
}

///|
/// The command that `chord` runs where the focus is, if any. Tree shortcuts never run while a person types.
pub fn resolve(
  bindings : Array[Binding],
  chord : Chord,
  context : Context,
) -> CommandId? {
  bindings
  .iter()
  .find_first(binding => {
    binding.chord == chord &&
    (match binding.scope {
      Anywhere => true
      Tree => context.in_tree && !context.editing
    })
  })
  .map(binding => binding.command)
}

///|
/// The chord to show next to `command` on this system: the first binding shown there.
pub fn shortcut(
  bindings : Array[Binding],
  command : CommandId,
  mac~ : Bool,
) -> Chord? {
  bindings
  .iter()
  .find_first(binding => {
    binding.command == command &&
    (match binding.shown {
      Everywhere => true
      OnMac => mac
      OffMac => !mac
    })
  })
  .map(binding => binding.chord)
}

///|
pub extend CommandId with Eq::{not_equal, equal}

///|
pub extend CommandId with @debug.Debug::{to_repr}

///|
pub extend Chord with Eq::{not_equal, equal}

///|
pub extend Chord with @debug.Debug::{to_repr}

///|
pub extend Scope with Eq::{not_equal, equal}

///|
pub extend Scope with @debug.Debug::{to_repr}

///|
pub extend Shown with Eq::{not_equal, equal}

///|
pub extend Shown with @debug.Debug::{to_repr}

///|
pub extend Binding with Eq::{not_equal, equal}

///|
pub extend Binding with @debug.Debug::{to_repr}

///|
pub extend Context with Eq::{not_equal, equal}

///|
pub extend Context with @debug.Debug::{to_repr}
