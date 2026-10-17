///|
/// The inline edit in progress: nothing, a new file in a folder, a new name for a row, a delete waiting for its
/// answer, or a new package name.
pub(all) enum Edit {
  Idle
  Creating(Folder, String)
  Renaming(Item, String)
  Deleting(Item)
  Naming(String)
} derive(Eq, Debug)

///|
/// What a context menu acts on: a row, or the project as a whole.
pub(all) enum MenuTarget {
  OnItem(Item)
  OnRoot
} derive(Eq, Debug)

///|
/// An open context menu: its target, its top-left corner in viewport pixels and the entry with the focus.
pub(all) struct Menu {
  target : MenuTarget
  left : Int32
  top : Int32
  index : Int32
} derive(Eq, Debug)

///|
pub(all) struct State {
  edit : Edit
  error : String
  /// Folders whose children are hidden. Folders are open unless listed, so new folders show their files.
  collapsed : Array[@ids.SourcePath]
  /// The row with the keyboard focus, if the person moved it.
  focused : Item?
  menu : Menu?
} derive(Eq, Debug)

///|
pub fn State::new() -> State {
  { edit: Idle, error: "", collapsed: [], focused: None, menu: None, }
}

///|
/// What the explorer reads from the workbench.
pub(all) struct Env {
  project : @project.Project
  rules : @project.FileRules
  /// Problems per file path from the last compile.
  counts : Map[String, Int32]
  busy : Bool
  /// The examples and samples the project menu offers, as `(id, label)`, from the workbench's one list.
  samples : Array[(String, String)]
  /// Why samples cannot open now, such as a running job; empty when they can.
  sample_reason : String
}

///|
/// Work for the workbench after an action: move the keyboard focus, or act outside the project.
pub(all) enum Effect {
  FocusRow(Item)
  /// Focus the inline input and select the characters from the first to the second index.
  FocusInput(Int32, Int32)
  FocusName
  FocusConfirm
  FocusMenu(Int32)
  FocusEditor
  Copy(String)
  ShowProblems(@ids.SourcePath)
  ImportFolder
  AskReset
  ShowPalette
  /// Open the example or sample with this id.
  LoadSample(String)
} derive(Eq, Debug)

///|
/// An entry of a context menu.
pub(all) enum MenuCommand {
  OpenItem
  NewFile
  RenameItem
  DeleteItem
  CopyPath
  Expose
  Unexpose
  ShowProblems
  ToggleFolder
  CollapseAll
  ImportFolder
  RenamePackage
  ResetProject
  CommandPalette
  OpenSample(String)
} derive(Eq, Debug)

///|
pub(all) struct MenuEntry {
  command : MenuCommand
  label : String
  /// The command whose shortcut the entry shows.
  shortcut : @keys.CommandId?
  enabled : Bool
  /// Why the entry is disabled.
  reason : String
  /// A separator comes before the entry.
  group_start : Bool
  /// The heading of the entry's section, such as `New from sample`; a heading shows where the section starts.
  section : String
} derive(Eq, Debug)

///|
pub(all) enum Action {
  Open(@ids.SourcePath)
  Toggle(@ids.SourcePath)
  Focus(Item)
  /// A key on a focused row.
  Key(@keys.Chord)
  CollapseAll
  /// `None` starts the new file where the focus is.
  StartAdd(Folder?)
  StartRename(Item)
  StartDelete(Item)
  StartNaming
  Draft(String)
  Commit
  Cancel
  ConfirmDelete
  /// Target, pointer position and viewport size, in CSS pixels.
  OpenMenu(MenuTarget, Int32, Int32, Int32, Int32)
  /// The menu of the row with the focus, from Shift+F10 or the menu key: anchor point and viewport size.
  OpenMenuHere(Int32, Int32, Int32, Int32)
  MenuKey(@keys.Chord)
  Choose(MenuCommand)
  CloseMenu
  Exposed(@ids.SourcePath, Bool)
  /// Shows a file that another part of the workbench opened.
  Reveal(@ids.SourcePath)
  Import
}

///|
let busy_reason = "Wait for the running job to finish"

///|
fn Env::tree(self : Env) -> Array[Node] {
  build_tree(self.project.files.map(f => f.path))
}

///|
fn State::visible(self : State, env : Env) -> Array[Row] {
  rows(env.tree(), self.collapsed, Map([]))
}

///|
/// The row that takes the Tab stop: the focused row, else the active file, else the first row.
pub fn State::current(self : State, env : Env) -> Item? {
  let visible = self.visible(env)
  if self.focused is Some(item) && visible.iter().any(row => row.item == item) {
    return Some(item)
  }
  let active = File(env.project.active)
  if visible.iter().any(row => row.item == active) {
    return Some(active)
  }
  visible.get(0).map(row => row.item)
}

///|
/// The folder of the focused row, for a new file: the folder itself, or the folder that holds the file.
pub fn State::focus_folder(self : State, env : Env) -> Folder {
  match self.current(env) {
    Some(Dir(path)) => In(path)
    Some(File(path)) => parent_of(path)
    None => Root
  }
}

///|
fn without(
  list : Array[@ids.SourcePath],
  gone : Array[@ids.SourcePath],
) -> Array[@ids.SourcePath] {
  list.filter(path => !gone.contains(path))
}

///|
/// Opens the folders that hold `path`, so its row is visible.
fn State::show(self : State, path : @ids.SourcePath) -> State {
  { ..self, collapsed: without(self.collapsed, ancestors(path)), }
}

///|
fn known_file(
  project : @project.Project,
  path : @ids.SourcePath,
) -> @ids.SourcePath raise @project.ProjectError {
  if !project.files.iter().any(f => f.path == path) {
    raise @project.ProjectError(
      "workbench.missing_file",
      "No file has this path: " + path.to_string(),
    )
  }
  path
}

///|
fn known_item(
  project : @project.Project,
  item : Item,
) -> Item raise @project.ProjectError {
  match item {
    File(path) => File(known_file(project, path))
    Dir(path) =>
      if project.files.iter().any(f => is_inside(f.path, path)) {
        item
      } else {
        raise @project.ProjectError(
          "workbench.missing_folder",
          "No folder has this path: " + path.to_string(),
        )
      }
  }
}

///|
/// The length of a file name before its extension, so a rename selects `Api` in `Api.elm`.
fn stem_length(name : String) -> Int32 {
  match name.rev_find(".") {
    Some(dot) if dot > 0 => dot
    _ => name.length()
  }
}

///|
/// What a key on a row means: a move in the tree, or a tree shortcut.
priv enum TreeKey {
  Navigate(Move)
  Run(@keys.CommandId)
}

///|
fn tree_key(chord : @keys.Chord) -> TreeKey? {
  let plain = chord.is_typing() && !chord.shift
  match chord.key {
    "ArrowUp" if plain => Some(Navigate(Up))
    "ArrowDown" if plain => Some(Navigate(Down))
    "ArrowLeft" if plain => Some(Navigate(Left))
    "ArrowRight" if plain => Some(Navigate(Right))
    "Home" if plain => Some(Navigate(First))
    "End" if plain => Some(Navigate(Last))
    "Enter" if plain => Some(Navigate(Activate))
    "Space" if plain => Some(Navigate(Preview))
    key if chord.is_character() => Some(Navigate(Typeahead(key)))
    _ =>
      @keys.resolve(@keys.keymap(), chord, { editing: false, in_tree: true, }).map(command => {
          Run(command)
        },
      )
  }
}

///|
/// True when a key on a row does something, so the page should not also act on it.
pub fn handles(chord : @keys.Chord) -> Bool {
  tree_key(chord) is Some(_)
}

///|
/// The tree shortcut that `chord` runs on a row, such as the context menu.
pub fn tree_command(chord : @keys.Chord) -> @keys.CommandId? {
  match tree_key(chord) {
    Some(Run(command)) => Some(command)
    _ => None
  }
}

///|
fn entry(
  command : MenuCommand,
  label : String,
  shortcut? : @keys.CommandId,
  reason~ : String = "",
  group_start~ : Bool = false,
  section~ : String = "",
) -> MenuEntry {
  {
    command,
    label,
    shortcut,
    enabled: reason == "",
    reason,
    group_start,
    section,
  }
}

///|
/// The entries of the context menu for `target`.
pub fn menu_entries(
  state : State,
  env : Env,
  target : MenuTarget,
) -> Array[MenuEntry] {
  let entries : Array[MenuEntry] = []
  let edit_reason = if env.busy { busy_reason } else { "" }
  let add_reason = match env.rules.add_reason() {
    Some(reason) => reason
    None => edit_reason
  }
  let packages = env.rules.add_reason() is None
  match target {
    OnItem(File(path)) => {
      entries.push(entry(OpenItem, "Open"))
      entries.push(entry(NewFile, "New file…", reason=add_reason))
      entries.push(
        entry(
          RenameItem,
          "Rename…",
          shortcut=RenameFile,
          reason=edit_reason,
          group_start=true,
        ),
      )
      entries.push(
        entry(DeleteItem, "Delete", shortcut=DeleteFile, reason=edit_reason),
      )
      entries.push(entry(CopyPath, "Copy path", group_start=true))
      if packages && env.project.file_module(path) is Some((_, exposed)) {
        if exposed {
          entries.push(entry(Unexpose, "Stop exposing module"))
        } else {
          entries.push(entry(Expose, "Expose module"))
        }
      }
      if env.counts.get(path.to_string()).unwrap_or(0) > 0 {
        entries.push(entry(ShowProblems, "Show problems"))
      }
    }
    OnItem(Dir(path)) => {
      entries.push(entry(NewFile, "New file…", reason=add_reason))
      entries.push(
        entry(
          ToggleFolder,
          if state.collapsed.contains(path) {
            "Expand"
          } else {
            "Collapse"
          },
        ),
      )
      entries.push(
        entry(
          RenameItem,
          "Rename…",
          shortcut=RenameFile,
          reason=edit_reason,
          group_start=true,
        ),
      )
      entries.push(
        entry(DeleteItem, "Delete", shortcut=DeleteFile, reason=edit_reason),
      )
      entries.push(entry(CopyPath, "Copy path", group_start=true))
    }
    OnRoot => {
      entries.push(entry(NewFile, "New file…", reason=add_reason))
      entries.push(entry(ImportFolder, "Import folder…", reason=edit_reason))
      entries.push(entry(CollapseAll, "Collapse folders"))
      for index, sample in env.samples {
        entries.push(
          entry(
            OpenSample(sample.0),
            sample.1,
            reason=env.sample_reason,
            group_start=index == 0,
            section=sample_section,
          ),
        )
      }
      if packages {
        entries.push(
          entry(RenamePackage, "Rename package…", group_start=true),
        )
      }
      entries.push(
        entry(
          ResetProject,
          "Reset project…",
          reason=edit_reason,
          group_start=true,
        ),
      )
      entries.push(
        entry(
          CommandPalette,
          "Command palette…",
          shortcut=ShowCommands,
          group_start=true,
        ),
      )
    }
  }
  entries
}

///|
/// The heading of the project menu's samples; the palette names the same entries "Open sample: …".
pub let sample_section : String = "New from sample"

///|
pub let menu_width : Int32 = @context_menu.width

///|
/// The entry of the shared context menu that draws `entry`.
pub fn MenuEntry::item(self : MenuEntry) -> @context_menu.Item {
  {
    label: self.label,
    shortcut: self.shortcut,
    enabled: self.enabled,
    reason: self.reason,
    group_start: self.group_start,
    section: self.section,
  }
}

///|
/// True when the entry at `index` starts a section that has a heading.
pub fn starts_section(entries : Array[MenuEntry], index : Int32) -> Bool {
  @context_menu.starts_section(entries.map(MenuEntry::item), index)
}

///|
/// The height of a menu in CSS pixels. The menu styles fix each item, separator and heading height, so this is exact.
pub fn menu_height(entries : Array[MenuEntry]) -> Int32 {
  @context_menu.height(entries.map(MenuEntry::item))
}

///|
/// The top-left corner of a menu opened at the pointer, kept inside the viewport.
pub fn place_menu(
  x : Int32,
  y : Int32,
  height : Int32,
  viewport_width : Int32,
  viewport_height : Int32,
) -> (Int32, Int32) {
  @context_menu.place(x, y, height, viewport_width, viewport_height)
}

///|
fn first_enabled(entries : Array[MenuEntry]) -> Int32 {
  @context_menu.first_enabled(entries.map(MenuEntry::item))
}

///|
/// Moves `state` and `project` by one action. A refused edit keeps the project and reports the refusal in
/// `error`; the effects tell the workbench where the keyboard focus goes and what to do outside the project.
pub fn apply(
  state : State,
  env : Env,
  action : Action,
) -> (State, @project.Project, Array[Effect]) {
  let project = env.project
  try {
    match (action, state.edit) {
      (Open(path), _) => {
        let opened = project.set_active(known_file(project, path))
        (
          { ..state, edit: Idle, error: "", focused: Some(File(path)), },
          opened,
          [],
        )
      }
      (Toggle(path), _) => {
        let collapsed = if state.collapsed.contains(path) {
          without(state.collapsed, [path])
        } else {
          state.collapsed + [path]
        }
        ({ ..state, collapsed, focused: Some(Dir(path)), }, project, [])
      }
      (Focus(item), _) => ({ ..state, focused: Some(item), }, project, [])
      (Key(_), _) if state.menu is Some(_) => (state, project, [])
      (Key(chord), _) =>
        match tree_key(chord) {
          None => (state, project, [])
          Some(Run(RenameFile)) =>
            match state.current(env) {
              Some(item) => apply(state, env, StartRename(item))
              None => (state, project, [])
            }
          Some(Run(DeleteFile)) =>
            match state.current(env) {
              Some(item) => apply(state, env, StartDelete(item))
              None => (state, project, [])
            }
          Some(Run(_)) => (state, project, [])
          Some(Navigate(motion)) =>
            match step(state.visible(env), state.current(env), motion) {
              Stay => (state, project, [])
              FocusOn(item) =>
                ({ ..state, focused: Some(item), }, project, [FocusRow(item)])
              Expand(path) =>
                (
                  {
                    ..state,
                    collapsed: without(state.collapsed, [path]),
                    focused: Some(Dir(path)),
                  },
                  project,
                  [FocusRow(Dir(path))],
                )
              Collapse(path) =>
                (
                  {
                    ..state,
                    collapsed: state.collapsed + [path],
                    focused: Some(Dir(path)),
                  },
                  project,
                  [FocusRow(Dir(path))],
                )
              OpenFile(path) =>
                (
                  { ..state, focused: Some(File(path)), },
                  project.set_active(path),
                  [
                    if motion == Activate {
                      FocusEditor
                    } else {
                      FocusRow(File(path))
                    },
                  ],
                )
            }
        }
      (CollapseAll, _) => {
        let tree = env.tree()
        let collapsed = folders_of(tree)
        let top = rows(tree, collapsed, Map([]))
        let focused = match state.current(env) {
          Some(item) =>
            top
            .iter()
            .find_first(row => {
              row.item == item ||
              (row.item is Dir(dir) && is_inside(item.path(), dir))
            })
            .map(row => row.item)
          None => None
        }
        ({ ..state, collapsed, focused, }, project, [])
      }
      (StartAdd(folder), _) => {
        if env.busy {
          raise @project.ProjectError("workbench.busy", busy_reason)
        }
        if env.rules.add_reason() is Some(reason) {
          raise @project.ProjectError("workbench.one_file_language", reason)
        }
        let folder = folder.unwrap_or(state.focus_folder(env))
        let shown = match folder {
          In(path) => without(state.collapsed, ancestors(path) + [path])
          Root => state.collapsed
        }
        (
          {
            ..state,
            edit: Creating(folder, ""),
            error: "",
            collapsed: shown,
            menu: None,
          },
          project,
          [FocusInput(0, 0)],
        )
      }
      (StartRename(item), _) => {
        if env.busy {
          raise @project.ProjectError("workbench.busy", busy_reason)
        }
        let item = known_item(project, item)
        let name = base_name(item.path())
        let selected = match item {
          File(_) => stem_length(name)
          Dir(_) => name.length()
        }
        (
          {
            ..state.show(item.path()),
            edit: Renaming(item, name),
            error: "",
            focused: Some(item),
            menu: None,
          },
          project,
          [FocusInput(0, selected)],
        )
      }
      (StartDelete(item), _) => {
        if env.busy {
          raise @project.ProjectError("workbench.busy", busy_reason)
        }
        let item = known_item(project, item)
        (
          {
            ..state.show(item.path()),
            edit: Deleting(item),
            error: "",
            focused: Some(item),
            menu: None,
          },
          project,
          [FocusConfirm],
        )
      }
      (StartNaming, _) => {
        let name = project.name.to_string()
        (
          { ..state, edit: Naming(name), error: "", menu: None, },
          project,
          [FocusInput(0, name.length())],
        )
      }
      (Draft(text), Creating(folder, _)) =>
        ({ ..state, edit: Creating(folder, text), error: "", }, project, [])
      (Draft(text), Renaming(item, _)) =>
        ({ ..state, edit: Renaming(item, text), error: "", }, project, [])
      (Draft(text), Naming(_)) =>
        ({ ..state, edit: Naming(text), error: "", }, project, [])
      (Commit, Creating(folder, draft)) => {
        let name = draft.trim().to_owned()
        if name == "" {
          return apply(state, env, Cancel)
        }
        let added = project.add_file(env.rules, folder.join(name))
        (
          {
            ..state.show(added.active),
            edit: Idle,
            error: "",
            focused: Some(File(added.active)),
          },
          added,
          [FocusEditor],
        )
      }
      (Commit, Renaming(item, draft)) => {
        let name = draft.trim().to_owned()
        let path = item.path()
        if name == "" || name == base_name(path) {
          return apply(state, env, Cancel)
        }
        let target = parent_of(path).join(name)
        let (renamed, moved) = match item {
          File(_) => (project.rename_file(env.rules, path, target), true)
          Dir(_) => (project.rename_folder(env.rules, path, target), false)
        }
        // The rename succeeded, so `target` names a valid path.
        let moved_path = @ids.SourcePath::parse(target) catch { _ => path }
        let moved_item = if moved { File(moved_path) } else { Dir(moved_path) }
        (
          {
            ..state.show(moved_path),
            edit: Idle,
            error: "",
            focused: Some(moved_item),
          },
          renamed,
          [FocusRow(moved_item)],
        )
      }
      (Commit, Naming(draft)) =>
        (
          { ..state, edit: Idle, error: "", },
          project.set_name(draft.trim().to_owned()),
          [FocusName],
        )
      (Commit, Deleting(_)) => apply(state, env, ConfirmDelete)
      (ConfirmDelete, Deleting(item)) => {
        let remaining = match item {
          File(path) => project.delete_file(path)
          Dir(path) => project.delete_folder(path)
        }
        let active = File(remaining.active)
        (
          { ..state, edit: Idle, error: "", focused: Some(active), },
          remaining,
          [FocusRow(active)],
        )
      }
      (Cancel, edit) => {
        let effects = match edit {
          Renaming(item, _) | Deleting(item) => [FocusRow(item)]
          Naming(_) => [FocusName]
          Creating(_, _) =>
            match state.current(env) {
              Some(item) => [FocusRow(item)]
              None => []
            }
          Idle => []
        }
        ({ ..state, edit: Idle, error: "", }, project, effects)
      }
      (OpenMenu(target, x, y, width, height), _) => {
        let entries = menu_entries(state, env, target)
        let (left, top) = place_menu(x, y, menu_height(entries), width, height)
        let index = first_enabled(entries)
        let focused = match target {
          OnItem(item) => Some(item)
          OnRoot => state.focused
        }
        (
          { ..state, focused, menu: Some({ target, left, top, index, }), },
          project,
          [FocusMenu(index)],
        )
      }
      (OpenMenuHere(x, y, width, height), _) => {
        let target = match state.current(env) {
          Some(item) => OnItem(item)
          None => OnRoot
        }
        apply(state, env, OpenMenu(target, x, y, width, height))
      }
      (MenuKey(chord), _) => {
        guard state.menu is Some(menu) else { return (state, project, []) }
        let entries = menu_entries(state, env, menu.target)
        match @context_menu.key_result(entries.length(), menu.index, chord) {
          MoveTo(index) =>
            (
              { ..state, menu: Some({ ..menu, index, }), },
              project,
              [FocusMenu(index)],
            )
          Choose(index) =>
            match entries.get(index) {
              Some(entry) => apply(state, env, Choose(entry.command))
              None => (state, project, [])
            }
          Close => apply(state, env, CloseMenu)
          Ignore => (state, project, [])
        }
      }
      (CloseMenu, _) => {
        let closed = { ..state, menu: None, }
        (
          closed,
          project,
          match closed.current(env) {
            Some(item) => [FocusRow(item)]
            None => []
          },
        )
      }
      (Choose(command), _) => {
        guard state.menu is Some(menu) else { return (state, project, []) }
        guard menu_entries(state, env, menu.target)
          .iter()
          .find_first(entry => entry.command == command)
          is Some({ enabled: true, .. }) else {
          return (state, project, [])
        }
        let closed = { ..state, menu: None, }
        match (command, menu.target) {
          (OpenItem, OnItem(File(path))) => {
            let (next, opened, _) = apply(closed, env, Open(path))
            (next, opened, [FocusEditor])
          }
          (NewFile, OnItem(File(path))) =>
            apply(closed, env, StartAdd(Some(parent_of(path))))
          (NewFile, OnItem(Dir(path))) =>
            apply(closed, env, StartAdd(Some(In(path))))
          (NewFile, _) => apply(closed, env, StartAdd(None))
          (RenameItem, OnItem(item)) => apply(closed, env, StartRename(item))
          (DeleteItem, OnItem(item)) => apply(closed, env, StartDelete(item))
          (CopyPath, OnItem(item)) => {
            let (next, same, focus) = apply(closed, env, CloseMenu)
            (next, same, focus + [Copy(item.path().to_string())])
          }
          (Expose, OnItem(File(path))) =>
            apply(closed, env, Exposed(path, true))
          (Unexpose, OnItem(File(path))) =>
            apply(closed, env, Exposed(path, false))
          (ShowProblems, OnItem(File(path))) => {
            let (next, same, _) = apply(closed, env, CloseMenu)
            (next, same, [ShowProblems(path)])
          }
          (ToggleFolder, OnItem(Dir(path))) => {
            let (next, same, _) = apply(closed, env, Toggle(path))
            (next, same, [FocusRow(Dir(path))])
          }
          (CollapseAll, _) => apply(closed, env, CollapseAll)
          (ImportFolder, _) => (closed, project, [ImportFolder])
          (RenamePackage, _) => apply(closed, env, StartNaming)
          (ResetProject, _) => (closed, project, [AskReset])
          (CommandPalette, _) => (closed, project, [ShowPalette])
          (OpenSample(id), _) => (closed, project, [LoadSample(id)])
          _ => apply(closed, env, CloseMenu)
        }
      }
      (Exposed(path, exposed), _) => {
        guard project.file_module(known_file(project, path))
          is Some((module_name, _)) else {
          raise @project.ProjectError(
            "workbench.invalid_module",
            "Not a module: " + path.to_string(),
          )
        }
        (
          { ..state, error: "", },
          project.set_exposed(module_name, exposed),
          [FocusRow(File(path))],
        )
      }
      (Reveal(path), _) =>
        ({ ..state.show(path), focused: Some(File(path)), }, project, [])
      (Import, _) => (state, project, [ImportFolder])
      // A draft, commit or answer with no inline edit open, such as a double click: nothing to do.
      _ => (state, project, [])
    }
  } catch {
    @project.ProjectError(_, message) => {
      // A refused delete closes its question; a refused add or rename stays open so the name can be corrected.
      let (edit, effects) = match state.edit {
        Deleting(item) => (Idle, [FocusRow(item)])
        other => (other, [])
      }
      ({ ..state, edit, error: message, menu: None, }, project, effects)
    }
  }
}

///|
pub extend Edit with Eq::{not_equal, equal}

///|
pub extend Edit with @debug.Debug::{to_repr}

///|
pub extend MenuTarget with Eq::{not_equal, equal}

///|
pub extend MenuTarget with @debug.Debug::{to_repr}

///|
pub extend Menu with Eq::{not_equal, equal}

///|
pub extend Menu with @debug.Debug::{to_repr}

///|
pub extend State with Eq::{not_equal, equal}

///|
pub extend State with @debug.Debug::{to_repr}

///|
pub extend Effect with Eq::{not_equal, equal}

///|
pub extend Effect with @debug.Debug::{to_repr}

///|
pub extend MenuCommand with Eq::{not_equal, equal}

///|
pub extend MenuCommand with @debug.Debug::{to_repr}

///|
pub extend MenuEntry with Eq::{not_equal, equal}

///|
pub extend MenuEntry with @debug.Debug::{to_repr}
