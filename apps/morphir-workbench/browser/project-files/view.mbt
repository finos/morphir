///|
pub(all) struct Props {
  env : Env
  state : State
  /// The display name of the project's language, such as `Elm`.
  language : String
  mac : Bool
}

///|
/// True when the key went down on a tree row, not in an input or a button inside one.
extern "js" fn on_row(event : @dom.KeyboardEvent) -> Bool =
  #|(event) => event.target?.getAttribute?.('role') === 'treeitem'

///|
/// The point under the start of the focused row, and the viewport size, for a menu opened from the keyboard.
extern "js" fn key_anchor(event : @dom.KeyboardEvent) -> FixedArray[Int32] =
  #|(event) => { const r = event.target.getBoundingClientRect(); return [Math.round(r.left + 24), Math.round(r.bottom), Math.round(innerWidth), Math.round(innerHeight)]; }

///|
/// The point under the start of a clicked button, and the viewport size, so a menu opened from the keyboard or the
/// mouse drops below the button.
extern "js" fn button_anchor(event : @dom.MouseEvent) -> FixedArray[Int32] =
  #|(event) => { const r = event.currentTarget.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.bottom + 2), Math.round(innerWidth), Math.round(innerHeight)]; }

///|
extern "js" fn in_text_field(event : @dom.MouseEvent) -> Bool =
  #|(event) => event.target?.closest?.('input, textarea') != null

///|
extern "js" fn viewport() -> FixedArray[Int32] =
  #|() => [Math.round(innerWidth), Math.round(innerHeight)]

///|
/// The DOM id of a row, for focus.
pub fn row_id(item : Item) -> String {
  match item {
    Dir(path) => "explorer-dir:" + path.to_string()
    File(path) => "explorer-file:" + path.to_string()
  }
}

///|
pub let input_id : String = "explorer-input"

///|
pub let name_id : String = "explorer-name"

///|
pub let confirm_id : String = "explorer-confirm"

///|
pub fn menu_item_id(index : Int32) -> String {
  @context_menu.item_id("explorer-menu", index)
}

///|
/// The icon class of a file, by its extension.
pub fn file_icon(path : String) -> String {
  if path.has_suffix(".elm") {
    "icon-lang-elm"
  } else if path.has_suffix(".mbt") {
    "icon-lang-moonbit"
  } else if path.has_suffix(".scm") {
    "icon-lang-scheme"
  } else if path.has_suffix(".json") {
    "icon-lang-json"
  } else {
    "icon-document"
  }
}

///|
fn icon(class : String) -> @html.Html {
  @html.span(
    class="explorer-icon " + class,
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
}

///|
fn chord_of(event : @dom.KeyboardEvent, mac : Bool) -> @keys.Chord {
  @keys.Chord::from_event(
    event.key(),
    ctrl=event.ctrl_key(),
    meta=event.meta_key(),
    shift=event.shift_key(),
    alt=event.alt_key(),
    mac~,
  )
}

///|
fn plural(count : Int32, one : String, many : String) -> String {
  count.to_string() + " " + (if count == 1 { one } else { many })
}

///|
/// The inline input of a new file, a rename or the package name. Enter commits and Escape cancels; the keys stay
/// in the input.
fn inline_input(
  emit : @cmd.Emit[Action],
  value : String,
  label : String,
  class~ : String = "explorer-input",
) -> @html.Html {
  @html.input(
    id=input_id,
    class~,
    value~,
    auto_complete=Off,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .value_prop(value)
      .spellcheck(false)
      .on_input(event => emit(Draft(input_value(event))))
      .on_keydown(event => {
        event.stop_propagation()
        match event.key() {
          "Enter" => {
            event.prevent_default()
            emit(Commit)
          }
          "Escape" => {
            event.prevent_default()
            emit(Cancel)
          }
          _ => @cmd.none
        }
      }),
  )
}

///|
extern "js" fn input_value(event : @dom.InputEvent) -> String =
  #|(event) => event.currentTarget.value

///|
fn error_note(message : String) -> @html.Html {
  @html.p(
    class="explorer-error",
    attrs=@html.Attrs::build().role("alert"),
    message,
  )
}

///|
fn description(props : Props, row : Row) -> String {
  let parts : Array[String] = []
  if row.parent is Some(parent) {
    parts.push("in " + parent.to_string())
  }
  if row.item is File(path) &&
    props.env.rules.add_reason() is None &&
    props.env.project.file_module(path) is Some((_, true)) {
    parts.push("exposed")
  }
  if row.problems > 0 {
    parts.push(plural(row.problems, "problem", "problems"))
  }
  parts.join(", ")
}

///|
fn row_view(
  props : Props,
  emit : @cmd.Emit[Action],
  row : Row,
  tab_stop : Item?,
) -> @html.Html {
  let path = row.item.path()
  let text = path.to_string()
  let active = row.item == File(props.env.project.active)
  let folder = row.item is Dir(_)
  let base = @html.Attrs::build()
    .role("treeitem")
    .aria_level((row.depth + 1).to_string())
    .aria_setsize(row.siblings.to_string())
    .aria_posinset(row.position.to_string())
    .aria_selected(active.to_string())
    .tabindex(if tab_stop == Some(row.item) { 0 } else { -1 })
    .data_set("path", text)
  let base = if folder {
    base.aria_expanded(row.expanded.to_string())
  } else {
    base
  }
  let target = props.state.menu is Some({ target: OnItem(item), .. }) &&
    item == row.item
  let class = "explorer-row" +
    (if folder { " is-folder" } else { " is-file" }) +
    (if active { " is-active" } else { "" }) +
    (if target { " is-target" } else { "" })
  let depth = ["--depth:" + row.depth.to_string()]
  let twisty = @html.span(
    class=if folder && row.expanded {
      "explorer-twisty open"
    } else if folder {
      "explorer-twisty"
    } else {
      "explorer-twisty leaf"
    },
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
  let kind = if folder {
    icon(if row.expanded { "icon-folder-open" } else { "icon-folder" })
  } else {
    icon(file_icon(text))
  }
  match props.state.edit {
    Renaming(item, draft) if item == row.item =>
      @html.li(
        id=row_id(row.item),
        class=class + " is-editing",
        style=depth,
        attrs=base.aria_label(row.label),
        [
          @html.div(class="explorer-line", [
            twisty,
            kind,
            inline_input(emit, draft, "New name for " + row.label),
          ]),
          if props.state.error != "" {
            error_note(props.state.error)
          } else {
            @html.nothing
          },
        ],
      )
    Deleting(item) if item == row.item =>
      @html.li(
        id=row_id(row.item),
        class=class + " is-confirm",
        style=depth,
        attrs=base
          .aria_label("Delete " + row.label + "?")
          .on_keydown(event => {
            event.stop_propagation()
            if event.key() == "Escape" {
              event.prevent_default()
              emit(Cancel)
            } else {
              @cmd.none
            }
          }),
        [
          @html.span(
            class="explorer-confirm-text",
            "Delete " +
            row.label +
            (if folder { " and its files?" } else { "?" }),
          ),
          @html.button(
            id=confirm_id,
            class="danger small",
            attrs=@html.Attrs::build().aria_label("Delete " + text),
            on_click=emit(ConfirmDelete),
            "Delete",
          ),
          @html.button(
            class="secondary small",
            attrs=@html.Attrs::build().aria_label("Keep " + text),
            on_click=emit(Cancel),
            "Keep",
          ),
        ],
      )
    _ => {
      let children : Array[@html.Html] = [
        twisty,
        kind,
        @html.span(class="explorer-label", row.label),
      ]
      if row.item is File(file) &&
        props.env.rules.add_reason() is None &&
        props.env.project.file_module(file) is Some((_, true)) {
        children.push(
          @html.span(
            class="explorer-exposed",
            title="Exposed module",
            attrs=@html.Attrs::build().aria_hidden("true"),
            "",
          ),
        )
      }
      if row.problems > 0 {
        children.push(
          @html.span(
            class=if folder {
              "explorer-problems rollup"
            } else {
              "explorer-problems"
            },
            attrs=@html.Attrs::build().aria_hidden("true"),
            row.problems.to_string(),
          ),
        )
      }
      // The same menu as a right-click, for touch screens (no contextmenu on a long press) and as a visible cue.
      children.push(
        @html.button(
          class="explorer-row-more",
          title="More actions",
          attrs=@html.Attrs::build()
            .tabindex(-1)
            .aria_label("More actions for " + row.label)
            .aria_haspopup("menu")
            .on_click(event => {
              event.stop_propagation()
              let anchor = button_anchor(event)
              emit(
                OpenMenu(
                  OnItem(row.item),
                  anchor[0],
                  anchor[1],
                  anchor[2],
                  anchor[3],
                ),
              )
            }),
          @html.span(
            class="action-icon icon-more",
            attrs=@html.Attrs::build().aria_hidden("true"),
            "",
          ),
        ),
      )
      @html.li(
        id=row_id(row.item),
        class~,
        style=depth,
        title=text,
        attrs=base
          .aria_label(row.label)
          .aria_description(description(props, row))
          .on_click(_ => {
            match row.item {
              File(path) => emit(Open(path))
              Dir(path) => emit(Toggle(path))
            }
          })
          .on_focus(_ => emit(Focus(row.item)))
          .on_contextmenu(event => {
            event.prevent_default()
            event.stop_propagation()
            let size = viewport()
            emit(
              OpenMenu(
                OnItem(row.item),
                event.get_client_x().to_int(),
                event.get_client_y().to_int(),
                size[0],
                size[1],
              ),
            )
          }),
        children,
      )
    }
  }
}

///|
/// The row of a new file, at the top of its folder.
fn creating_row(
  props : Props,
  emit : @cmd.Emit[Action],
  folder : Folder,
  draft : String,
  depth : Int32,
) -> @html.Html {
  let label = match folder {
    Root => "New file path"
    In(path) => "New file name in " + path.to_string()
  }
  @html.li(
    class="explorer-row is-file is-editing",
    style=["--depth:" + depth.to_string()],
    attrs=@html.Attrs::build()
      .role("treeitem")
      .aria_level((depth + 1).to_string())
      .aria_label(label),
    [
      @html.div(class="explorer-line", [
        @html.span(
          class="explorer-twisty leaf",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
        icon(file_icon(draft)),
        inline_input(emit, draft, label),
      ]),
      if props.state.error != "" {
        error_note(props.state.error)
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn tree_view(props : Props, emit : @cmd.Emit[Action]) -> @html.Html {
  let visible = rows(props.env.tree(), props.state.collapsed, props.env.counts)
  let tab_stop = props.state.current(props.env)
  let items : Array[@html.Html] = visible.map(row => {
    row_view(props, emit, row, tab_stop)
  })
  if props.state.edit is Creating(folder, draft) {
    let (index, depth) = match folder {
      Root => (0, 0)
      In(path) =>
        match visible.search_by(row => row.item == Dir(path)) {
          Some(i) => (i + 1, visible[i].depth + 1)
          None => (0, 0)
        }
    }
    items.insert(index, creating_row(props, emit, folder, draft, depth))
  }
  @html.ul(
    class="explorer-tree",
    attrs=@html.Attrs::build()
      .role("tree")
      .aria_label("Project files")
      .on_keydown(event => {
        if !on_row(event) {
          return @cmd.none
        }
        let chord = chord_of(event, props.mac)
        if !handles(chord) {
          return @cmd.none
        }
        event.prevent_default()
        if tree_command(chord) == Some(ContextMenu) {
          let anchor = key_anchor(event)
          emit(OpenMenuHere(anchor[0], anchor[1], anchor[2], anchor[3]))
        } else {
          emit(Key(chord))
        }
      }),
    items,
  )
}

///|
fn icon_button(
  name : String,
  icon_class : String,
  on_click : @cmd.Cmd,
  disabled~ : Bool = false,
  title~ : String = name,
  attrs~ : @html.Attrs = @html.Attrs::build(),
) -> @html.Html {
  @html.button(
    class="explorer-action",
    disabled~,
    title~,
    attrs=attrs.aria_label(name),
    on_click~,
    @html.span(
      class="action-icon " + icon_class,
      attrs=@html.Attrs::build().aria_hidden("true"),
      "",
    ),
  )
}

///|
fn header(props : Props, emit : @cmd.Emit[Action]) -> @html.Html {
  let project = props.env.project
  let packages = props.env.rules.add_reason() is None
  let name = project.name.to_string()
  let title = match props.state.edit {
    Naming(draft) =>
      inline_input(
        emit,
        draft,
        "Package name",
        class="explorer-input explorer-name-input",
      )
    _ if packages =>
      @html.button(
        id=name_id,
        class="explorer-name",
        title="Rename package",
        attrs=@html.Attrs::build().aria_label("Package " + name),
        on_click=emit(StartNaming),
        name,
      )
    _ => @html.span(id=name_id, class="explorer-name", name)
  }
  let add_reason = match props.env.rules.add_reason() {
    Some(reason) => reason
    None => if props.env.busy { busy_reason } else { "" }
  }
  let menu_open = props.state.menu is Some({ target: OnRoot, .. })
  @html.div(class="explorer-header", [
    title,
    @html.div(class="explorer-subheader", [
      @html.span(
        class="explorer-meta",
        props.language +
        " · " +
        plural(project.files.length(), "file", "files"),
      ),
      @html.div(class="explorer-actions", [
        icon_button(
          "New file",
          "icon-file-new",
          emit(StartAdd(None)),
          disabled=add_reason != "",
          title=if add_reason == "" { "New file" } else { add_reason },
        ),
        icon_button(
          "Import folder",
          "icon-import",
          emit(Import),
          disabled=props.env.busy,
          title="Import folder: copy a morphir.json folder into the editor; nothing is written back",
        ),
        icon_button("Collapse folders", "icon-collapse-all", emit(CollapseAll)),
        icon_button(
          "More actions",
          "icon-more",
          @cmd.none,
          attrs=@html.Attrs::build()
            .aria_haspopup("menu")
            .aria_expanded(menu_open.to_string())
            .on_click(event => {
              let anchor = button_anchor(event)
              emit(OpenMenu(OnRoot, anchor[0], anchor[1], anchor[2], anchor[3]))
            }),
        ),
      ]),
    ]),
  ])
}

///|
fn menu_view(
  props : Props,
  emit : @cmd.Emit[Action],
  menu : Menu,
) -> @html.Html {
  let entries = menu_entries(props.state, props.env, menu.target)
  @context_menu.view(
    {
      items: entries.map(MenuEntry::item),
      left: menu.left,
      top: menu.top,
      index: menu.index,
      label: match menu.target {
        OnItem(item) => "Actions for " + base_name(item.path())
        OnRoot => "Project actions"
      },
      id_prefix: "explorer-menu",
      mac: props.mac,
    },
    on_choose=index => {
      match entries.get(index) {
        Some(entry) => emit(Choose(entry.command))
        None => @cmd.none
      }
    },
    on_key=chord => emit(MenuKey(chord)),
    on_close=emit(CloseMenu),
  )
}

///|
/// The project explorer: a header with the package name and actions, the file tree, the inline edits and the
/// context menu. `extra` follows the tree, for the workbench's storage notes.
pub fn view(
  props : Props,
  emit : @cmd.Emit[Action],
  extra~ : Array[@html.Html] = [],
) -> @html.Html {
  let children : Array[@html.Html] = [header(props, emit)]
  if props.state.edit is Naming(_) && props.state.error != "" {
    children.push(error_note(props.state.error))
  }
  children.push(tree_view(props, emit))
  let inline_error = props.state.edit
    is (Creating(_, _) | Renaming(_, _) | Naming(_))
  if props.state.error != "" && !inline_error {
    children.push(error_note(props.state.error))
  }
  children.append(extra)
  if props.state.menu is Some(menu) {
    children.push(menu_view(props, emit, menu))
  }
  @html.section(
    class="explorer",
    attrs=@html.Attrs::build()
      .aria_label("Project explorer")
      .data_set("drop", "project")
      // A right-click anywhere outside a row, such as below a short tree, opens the project menu; text fields keep
      // the browser's menu.
      .on_contextmenu(event => {
        if in_text_field(event) {
          return @cmd.none
        }
        event.prevent_default()
        let size = viewport()
        emit(
          OpenMenu(
            OnRoot,
            event.get_client_x().to_int(),
            event.get_client_y().to_int(),
            size[0],
            size[1],
          ),
        )
      }),
    children,
  )
}
