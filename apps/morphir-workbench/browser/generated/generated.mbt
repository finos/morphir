///|
pub(all) struct Props {
  output : Json
  state : State
  language : String
  mac : Bool
}

///|
extern "js" fn viewport() -> FixedArray[Int32] =
  #|() => [Math.round(innerWidth), Math.round(innerHeight)]

///|
/// The point under the start of the element an event came from, and the viewport size, for a menu that a key or a
/// button opens.
extern "js" fn anchor(event : @dom.Event) -> FixedArray[Int32] =
  #|(event) => { const r = event.currentTarget.getBoundingClientRect(); return [Math.round(r.left + 16), Math.round(r.bottom + 2), Math.round(innerWidth), Math.round(innerHeight)]; }

///|
/// What the preview shows for the selected file: its content or binary summary, its Ion text decoded by the worker,
/// or its first bytes in hex.
pub(all) enum Preview {
  Summary
  /// The path, the decoded text and the number of top-level values.
  IonText(String, String, Int32)
  Hex(String)
} derive(Eq, Debug)

///|
pub extend Preview with Eq::{equal, not_equal}

///|
pub extend Preview with @debug.Debug::{to_repr}

///|
/// An open context menu on a generated file: the file, the menu's top-left corner and the entry with the focus.
pub(all) struct Menu {
  path : String
  left : Int32
  top : Int32
  index : Int32
} derive(Eq, Debug)

///|
pub extend Menu with Eq::{equal, not_equal}

///|
pub extend Menu with @debug.Debug::{to_repr}

///|
pub(all) struct State {
  selected : String
  collapsed : Array[String]
  files_visible : Bool
  expanded : Bool
  preview : Preview
  menu : Menu?
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
/// An entry of a generated file's context menu.
pub(all) enum FileCommand {
  ViewIonText
  ViewHex
  CopyPath
  Download
} derive(Eq, Debug)

///|
pub extend FileCommand with Eq::{equal, not_equal}

///|
pub extend FileCommand with @debug.Debug::{to_repr}

///|
pub(all) enum Action {
  Select(String)
  ToggleFolder(String)
  ToggleFiles
  ToggleExpanded
  /// File, point and viewport size, in CSS pixels.
  OpenMenu(String, Int32, Int32, Int32, Int32)
  MenuKey(@keys.Chord)
  Choose(FileCommand)
  CloseMenu
  /// Back from a decoded or hex view to the file's own preview.
  ShowSummary
  /// The heading's View as Ion text button.
  ViewIonTextOf(String)
  /// The worker's Ion text for a file: path, text and value count.
  ShowIonText(String, String, Int32)
}

///|
/// Work for the workbench after an action.
pub(all) enum Effect {
  /// Decode this file's binary Ion to text, as a job.
  RequestIonText(String)
  Copy(String)
  DownloadFile(String)
  FocusMenu(Int32)
  FocusFile(String)
} derive(Eq, Debug)

///|
pub extend Effect with Eq::{equal, not_equal}

///|
pub extend Effect with @debug.Debug::{to_repr}

///|
pub fn State::new() -> State {
  {
    selected: "",
    collapsed: [],
    files_visible: true,
    expanded: false,
    preview: Summary,
    menu: None,
  }
}

///|
pub fn State::update(self : State, action : Action) -> State {
  self.apply([], action).0
}

///|
/// The DOM id of a file's row button, for focus.
pub fn file_id(path : String) -> String {
  "generated-file:" + path
}

///|
pub let menu_id_prefix : String = "generated-menu"

///|
/// Moves the state by one action. `files` are the generated files; the effects tell the workbench what to do.
pub fn State::apply(
  self : State,
  files : Array[Json],
  action : Action,
) -> (State, Array[Effect]) {
  match action {
    Select(selected) => ({ ..self, selected, preview: Summary, }, [])
    ToggleFolder(path) => {
      let collapsed = if self.collapsed.contains(path) {
        self.collapsed.filter(p => p != path)
      } else {
        self.collapsed + [path]
      }
      ({ ..self, collapsed, }, [])
    }
    ToggleFiles => ({ ..self, files_visible: !self.files_visible, }, [])
    ToggleExpanded => ({ ..self, expanded: !self.expanded, }, [])
    OpenMenu(path, x, y, width, height) => {
      let items = menu_items(file_of(files, path)).map(entry => entry.1)
      let (left, top) = @context_menu.place(
        x,
        y,
        @context_menu.height(items),
        width,
        height,
      )
      let index = @context_menu.first_enabled(items)
      ({ ..self, menu: Some({ path, left, top, index, }), }, [FocusMenu(index)])
    }
    MenuKey(chord) => {
      guard self.menu is Some(menu) else { return (self, []) }
      let entries = menu_items(file_of(files, menu.path))
      match @context_menu.key_result(entries.length(), menu.index, chord) {
        MoveTo(index) =>
          ({ ..self, menu: Some({ ..menu, index, }), }, [FocusMenu(index)])
        Choose(index) =>
          match entries.get(index) {
            Some(entry) => self.apply(files, Choose(entry.0))
            None => (self, [])
          }
        Close => self.apply(files, CloseMenu)
        Ignore => (self, [])
      }
    }
    CloseMenu =>
      match self.menu {
        Some(menu) => ({ ..self, menu: None, }, [FocusFile(menu.path)])
        None => (self, [])
      }
    Choose(command) => {
      guard self.menu is Some(menu) else { return (self, []) }
      guard menu_items(file_of(files, menu.path))
        .iter()
        .find_first(entry => entry.0 == command)
        is Some((_, { enabled: true, .. })) else {
        return (self, [])
      }
      let closed = { ..self, menu: None, }
      match command {
        ViewIonText =>
          (
            { ..closed, selected: menu.path, },
            [RequestIonText(menu.path), FocusFile(menu.path)],
          )
        ViewHex =>
          (
            { ..closed, selected: menu.path, preview: Hex(menu.path), },
            [FocusFile(menu.path)],
          )
        CopyPath => (closed, [FocusFile(menu.path), Copy(menu.path)])
        Download => (closed, [FocusFile(menu.path), DownloadFile(menu.path)])
      }
    }
    ShowSummary => ({ ..self, preview: Summary, }, [])
    ViewIonTextOf(path) =>
      if is_binary_ion(file_of(files, path)) {
        ({ ..self, selected: path, }, [RequestIonText(path)])
      } else {
        (self, [])
      }
    ShowIonText(path, text, values) =>
      if file_of(files, path) == Json::null() {
        (self, [])
      } else {
        ({ ..self, selected: path, preview: IonText(path, text, values), }, [])
      }
  }
}

///|
/// New output clears file/folder selection, previews and menus but retains the user's layout choice.
pub fn State::reset(self : State) -> State {
  { ..self, selected: "", collapsed: [], preview: Summary, menu: None, }
}

///|
fn file_of(files : Array[Json], path : String) -> Json {
  files
  .iter()
  .find_first(file => text(file, "path") == path)
  .unwrap_or(Json::null())
}

///|
/// The base64 content of a binary file; `None` for a text file or one without a declared encoding.
fn base64_content(file : Json) -> String? {
  if field(file, "binary") == Json::boolean(true) &&
    text(file, "encoding") == "base64" {
    Some(text(file, "content"))
  } else {
    None
  }
}

///|
/// The size in bytes of a binary file with base64 content, from the base64 length and its padding, without
/// decoding it; `None` for a text file, one without a declared encoding, or a length that is not base64.
pub fn binary_size(file : Json) -> Int32? {
  guard base64_content(file) is Some(content) && content.length() % 4 == 0 else {
    return None
  }
  let padding = if content.has_suffix("==") {
    2
  } else if content.has_suffix("=") {
    1
  } else {
    0
  }
  Some(content.length() / 4 * 3 - padding)
}

///|
/// The first `count` bytes (or fewer) of a binary file with base64 content; only that part is decoded.
fn binary_head(file : Json, count : Int32) -> Bytes? {
  guard base64_content(file) is Some(content) else { return None }
  let chars = (count + 2) / 3 * 4
  let head = if content.length() <= chars {
    content
  } else {
    content.unsafe_substring(start=0, end=chars)
  }
  Some(@base64.decode(head[:])) catch {
    _ => None
  }
}

///|
/// True when a file is binary Ion: its bytes start with the Ion binary version marker `E0 01 00 EA`, whatever its
/// name. Only the first bytes are decoded.
pub fn is_binary_ion(file : Json) -> Bool {
  guard field(file, "binary") == Json::boolean(true) &&
    text(file, "encoding") == "base64" else {
    return false
  }
  let content = text(file, "content")
  let head = content.unsafe_substring(
    start=0,
    end=if content.length() < 8 { content.length() } else { 8 },
  )
  let bytes = @base64.decode(head[:]) catch { _ => return false }
  bytes.length() >= 4 &&
  bytes[0] == b'\xE0' &&
  bytes[1] == b'\x01' &&
  bytes[2] == b'\x00' &&
  bytes[3] == b'\xEA'
}

///|
/// The entries of a file's context menu, with the command each runs.
pub fn menu_items(file : Json) -> Array[(FileCommand, @context_menu.Item)] {
  let item = fn(label : String, reason : String, group_start : Bool) {
    @context_menu.Item::{
      label,
      shortcut: None,
      enabled: reason == "",
      reason,
      group_start,
      section: "",
    }
  }
  let entries : Array[(FileCommand, @context_menu.Item)] = []
  if field(file, "binary") == Json::boolean(true) {
    let undeclared = if text(file, "encoding") == "base64" {
      ""
    } else {
      "This host does not declare the file's encoding"
    }
    entries.push(
      (
        ViewIonText,
        item(
          "View as Ion text",
          if undeclared != "" {
            undeclared
          } else if is_binary_ion(file) {
            ""
          } else {
            "Not binary Ion: the file does not start with E0 01 00 EA"
          },
          false,
        ),
      ),
    )
    entries.push((ViewHex, item("View raw (hex)", undeclared, false)))
  }
  entries.push((CopyPath, item("Copy path", "", !entries.is_empty())))
  entries.push(
    (
      Download,
      item(
        "Download",
        if downloadable(file) {
          ""
        } else {
          "This host does not declare the file's encoding"
        },
        false,
      ),
    ),
  )
  entries
}

///|
pub let hex_limit : Int32 = 64 * 1024

///|
/// The first 64 KiB of `bytes` as hex rows of 16 bytes: offset, bytes and printable ASCII.
pub fn hex_dump(bytes : Bytes, total~ : Int32 = bytes.length()) -> String {
  let shown = if bytes.length() < hex_limit {
    bytes.length()
  } else {
    hex_limit
  }
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  let hex = fn(value : Int32, width : Int32) {
    let text = StringBuilder()
    for shift = (width - 1) * 4; shift >= 0; shift = shift - 4 {
      text.write_char(digits[(value >> shift) & 15].unsafe_to_char())
    }
    text.to_string()
  }
  for row = 0; row < shown; row = row + 16 {
    out.write_string(hex(row, 8))
    out.write_string("  ")
    let ascii = StringBuilder()
    for column in 0..<16 {
      if row + column < shown {
        let byte = bytes[row + column].to_int()
        out.write_string(hex(byte, 2))
        out.write_char(' ')
        ascii.write_char(
          if byte >= 32 && byte < 127 {
            byte.unsafe_to_char()
          } else {
            '.'
          },
        )
      } else {
        out.write_string("   ")
      }
      if column == 7 {
        out.write_char(' ')
      }
    }
    out.write_string(" |" + ascii.to_string() + "|\n")
  }
  if total > shown {
    out.write_string(
      "… " + (total - shown).to_string() + " more bytes not shown\n",
    )
  }
  out.to_string()
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
pub fn artifacts(output : Json) -> Array[Json] {
  match field(output, "artifacts") {
    Array(values) => values
    _ => []
  }
}

///|
pub fn selected(output : Json, path : String) -> Json {
  let files = artifacts(output)
  files
  .filter(file => text(file, "path") == path)
  .get(0)
  .unwrap_or(files.get(0).unwrap_or(Json::null()))
}

///|
fn language(path : String, fallback : String) -> String {
  for
    (extension, mode) in [
      (".elm", "elm"),
      (".mbt", "moonbit"),
      (".pkg", "moonbit"),
      (".mod", "moonbit"),
      (".json", "json"),
      (".scala", "scala"),
      (".scm", "scheme"),
      (".ss", "scheme"),
      (".sld", "scheme"),
      (".js", "javascript"),
      (".mjs", "javascript"),
      (".cjs", "javascript"),
      (".ts", "typescript"),
      (".java", "java"),
      (".py", "python"),
    ] {
    if path.has_suffix(extension) {
      return mode
    }
  }
  fallback
}

///|
fn downloadable(file : Json) -> Bool {
  field(file, "binary") != Json::boolean(true) ||
  text(file, "encoding") == "base64"
}

///|
fn icon(name : String) -> @html.Html {
  @html.span(
    class="artifact-icon icon-" + name,
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
}

///|
fn file_button(
  file : Json,
  label : String,
  state : State,
  selected_path : String,
  mac : Bool,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let path = text(file, "path")
  let target = state.menu is Some(menu) && menu.path == path
  let open_at = fn(position : FixedArray[Int32]) {
    emit(OpenMenu(path, position[0], position[1], position[2], position[3]))
  }
  @html.li(
    class=if target { "artifact-row is-target" } else { "artifact-row" },
    [
      @html.button(
        id=file_id(path),
        class=if path == selected_path {
          "artifact-file selected"
        } else {
          "artifact-file"
        },
        title=path,
        attrs=@html.Attrs::build()
          .aria_label(path)
          .aria_pressed((path == selected_path).to_string())
          .aria_haspopup("menu")
          .on_contextmenu(event => {
            event.prevent_default()
            event.stop_propagation()
            let size = viewport()
            open_at([
              event.get_client_x().to_int(),
              event.get_client_y().to_int(),
              size[0],
              size[1],
            ])
          })
          .on_keydown(event => {
            let chord = @keys.Chord::from_event(
              event.key(),
              ctrl=event.ctrl_key(),
              meta=event.meta_key(),
              shift=event.shift_key(),
              alt=event.alt_key(),
              mac~,
            )
            // The same keymap as the project tree: Shift+F10 or the menu key opens the file's menu.
            if @keys.resolve(@keys.keymap(), chord, {
                editing: false,
                in_tree: true,
              }) ==
              Some(ContextMenu) {
              event.prevent_default()
              open_at(anchor(event.as_event()))
            } else {
              @cmd.none
            }
          }),
        on_click=emit(Select(path)),
        [icon("document"), @html.span(class="artifact-name", label)],
      ),
      // The menu for touch screens and as a visible cue, as in the project explorer.
      @html.button(
        class="artifact-more",
        title="More actions",
        attrs=@html.Attrs::build()
          .tabindex(-1)
          .aria_label("More actions for " + path)
          .aria_haspopup("menu")
          .on_click(event => {
            event.stop_propagation()
            open_at(anchor(event.as_event()))
          }),
        @html.span(
          class="action-icon icon-more",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
      ),
    ],
  )
}

///|
fn file_tree(
  files : Array[Json],
  prefix : String,
  depth : Int32,
  state : State,
  selected_path : String,
  mac : Bool,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let folders : Array[String] = []
  let leaves : Array[(Json, String)] = []
  for file in files {
    let path = text(file, "path")
    if !path.has_prefix(prefix) {
      continue
    }
    let remaining = path[prefix.length():].to_owned()
    let parts = remaining.split("/").collect()
    // Deep or unusual host paths remain selectable without unbounded recursion.
    if parts.length() > 1 && parts[0] != "" && depth < 8 {
      let name = parts[0].to_owned()
      if !folders.contains(name) {
        folders.push(name)
      }
    } else {
      leaves.push(
        (
          file,
          if depth >= 8 && parts.length() > 1 {
            "…/" + parts[parts.length() - 1].to_owned()
          } else {
            remaining
          },
        ),
      )
    }
  }
  let rows : Array[@html.Html] = []
  for name in folders {
    let path = prefix + name + "/"
    let open = !state.collapsed.contains(path)
    rows.push(
      @html.li([
        @html.button(
          class="artifact-folder",
          title=path,
          attrs=@html.Attrs::build()
            .aria_label(
              if open {
                "Collapse " + path
              } else {
                "Expand " + path
              },
            )
            .aria_expanded(open.to_string()),
          on_click=emit(ToggleFolder(path)),
          [
            @html.span(
              class=if open {
                "artifact-chevron open"
              } else {
                "artifact-chevron"
              },
              "›",
            ),
            icon("folder"),
            @html.span(class="artifact-name", name),
          ],
        ),
        @html.div(hidden=!open, [
          file_tree(files, path, depth + 1, state, selected_path, mac, emit),
        ]),
      ]),
    )
  }
  for (file, label) in leaves {
    rows.push(file_button(file, label, state, selected_path, mac, emit))
  }
  @html.ul(class="artifact-tree", rows)
}

///|
fn breadcrumb(path : String) -> @html.Html {
  let parts = path.split("/").collect()
  let items : Array[@html.Html] = []
  for index, part in parts {
    if index > 0 {
      items.push(@html.span(class="artifact-path-separator", "/"))
    }
    items.push(
      @html.span(
        class=if index == parts.length() - 1 {
          "artifact-path-file"
        } else {
          ""
        },
        part.to_owned(),
      ),
    )
  }
  @html.div(class="artifact-breadcrumb", title=path, items)
}

///|
/// Generated source remains a set of files; the editor is a read-only projection.
pub fn view(
  props : Props,
  emit : @cmd.Emit[Action],
  on_download : @cmd.Emit[Bool],
) -> @html.Html {
  let files = artifacts(props.output)
  let file = selected(props.output, props.state.selected)
  let path = text(file, "path")
  let binary = field(file, "binary") == Json::boolean(true)
  let body : Array[@html.Html] = []
  body.push(
    @html.div(class="artifact-toolbar", [
      @html.div(class="artifact-toolbar-title", [
        @html.button(
          class="artifact-icon-button",
          disabled=files.is_empty(),
          title=if props.state.files_visible {
            "Hide generated files"
          } else {
            "Show generated files"
          },
          attrs=@html.Attrs::build()
            .aria_label(
              if props.state.files_visible {
                "Hide generated files"
              } else {
                "Show generated files"
              },
            )
            .aria_expanded(props.state.files_visible.to_string()),
          on_click=emit(ToggleFiles),
          icon("files"),
        ),
        @html.span(
          class="artifact-title",
          if files.is_empty() {
            "Generated output"
          } else {
            "Generated files"
          },
        ),
        @html.span(class="artifact-count", files.length().to_string()),
      ]),
      @html.div(class="artifact-toolbar-actions", [
        @html.button(
          class="ghost",
          hidden=files.is_empty(),
          disabled=files.any(f => !downloadable(f)),
          on_click=on_download(true),
          [icon("download"), @html.span("Download project")],
        ),
        @html.button(
          class="artifact-icon-button",
          title=if props.state.expanded {
            "Restore split view"
          } else {
            "Expand generated files"
          },
          attrs=@html.Attrs::build()
            .aria_label(
              if props.state.expanded {
                "Restore split view"
              } else {
                "Expand generated files"
              },
            )
            .aria_pressed(props.state.expanded.to_string()),
          on_click=emit(ToggleExpanded),
          icon(if props.state.expanded { "restore" } else { "expand" }),
        ),
      ]),
    ]),
  )
  if !files.is_empty() {
    if files.any(f => !downloadable(f)) {
      body.push(
        @html.p(
          class="small muted",
          "Binary files remain opaque; this host does not declare their download encoding.",
        ),
      )
    }
  }
  let message = text(props.output, "generationMessage")
  if message != "" {
    body.push(@html.p(class="generation-message", message))
  }
  match field(props.output, "generationWarnings") {
    Array(warnings) =>
      for warning in warnings {
        match warning {
          String(value) => body.push(@html.p(class="small muted", value))
          _ => ()
        }
      }
    _ => ()
  }
  let preview : Array[@html.Html] = []
  let decoded = match props.state.preview {
    IonText(at, text, values) if at == path => Some((text, values))
    _ => None
  }
  let hex = props.state.preview is Hex(at) && at == path
  if path != "" {
    preview.push(
      @html.div(class="artifact-file-heading", [
        breadcrumb(path),
        @html.span(
          class=if decoded is Some(_) || hex {
            "artifact-readonly artifact-view"
          } else {
            "artifact-readonly"
          },
          hidden=!binary,
          match decoded {
            Some((_, values)) =>
              "Decoded Ion text · " +
              values.to_string() +
              (if values == 1 { " value" } else { " values" })
            None => if hex { "Raw bytes (hex)" } else { "Binary" }
          },
        ),
        if decoded is Some(_) || hex {
          @html.button(
            class="ghost artifact-back",
            on_click=emit(ShowSummary),
            "Show binary summary",
          )
        } else if is_binary_ion(file) {
          @html.button(
            class="ghost artifact-back",
            on_click=emit(ViewIonTextOf(path)),
            "View as Ion text",
          )
        } else {
          @html.nothing
        },
        @html.button(
          class="artifact-icon-button",
          disabled=!downloadable(file),
          title="Download file",
          attrs=@html.Attrs::build().aria_label("Download file"),
          on_click=on_download(false),
          icon("download"),
        ),
      ]),
    )
  }
  preview.push(
    @editor.view({
      id: "output",
      document_key: "generated|" +
      path +
      (if decoded is Some(_) { "|ion-text" } else if hex { "|hex" } else { "" }),
      language: if decoded is Some(_) {
        "ion"
      } else if hex {
        "text"
      } else {
        language(path, props.language)
      },
      label: if decoded is Some(_) {
        "Decoded Ion text: " + path
      } else if hex {
        "Raw bytes (hex): " + path
      } else {
        "Generated output"
      },
      read_only: true,
      marks: "",
      reveal: "",
      value: if decoded is Some((text, _)) {
        text
      } else if hex {
        binary_head(file, hex_limit)
        .map(head => {
          hex_dump(head, total=binary_size(file).unwrap_or(head.length()))
        })
        .unwrap_or("")
      } else if binary {
        binary_summary(file)
      } else if file != Json::null() {
        text(file, "content")
      } else if text(props.output, "generated") != "" {
        text(props.output, "generated")
      } else if message != "" {
        "No files were generated. The compiled model remains available in Morphir IR."
      } else {
        "Select a generation target and recompile."
      },
    }),
  )
  body.push(
    @html.div(
      class=if files.is_empty() || !props.state.files_visible {
        "artifact-workspace files-hidden"
      } else {
        "artifact-workspace"
      },
      [
        @html.nav(
          class="artifact-files",
          hidden=files.is_empty() || !props.state.files_visible,
          attrs=@html.Attrs::build().aria_label("Generated files"),
          [file_tree(files, "", 0, props.state, path, props.mac, emit)],
        ),
        @html.div(class="artifact-preview", preview),
      ],
    ),
  )
  match props.state.menu {
    Some(menu) => {
      let entries = menu_items(file_of(files, menu.path))
      body.push(
        @context_menu.view(
          {
            items: entries.map(entry => entry.1),
            left: menu.left,
            top: menu.top,
            index: menu.index,
            label: "Actions for " + menu.path,
            id_prefix: menu_id_prefix,
            mac: props.mac,
          },
          on_choose=index => {
            match entries.get(index) {
              Some(entry) => emit(Choose(entry.0))
              None => @cmd.none
            }
          },
          on_key=chord => emit(MenuKey(chord)),
          on_close=emit(CloseMenu),
        ),
      )
    }
    None => ()
  }
  @html.div(class="generated-output", body)
}

///|
/// What the preview says about a binary file it cannot show as text.
fn binary_summary(file : Json) -> String {
  let size = match binary_size(file) {
    Some(bytes) => " (" + bytes.to_string() + " bytes)"
    None => ""
  }
  if is_binary_ion(file) {
    "Binary artifact: text preview unavailable.\n\nThis file is binary Ion" +
    size +
    ". Choose View as Ion text above or in the file's menu (right-click, or Shift+F10) to decode it."
  } else if binary_size(file) is Some(_) {
    "Binary artifact: text preview unavailable" +
    size +
    ".\n\nChoose View raw (hex) in the file's menu to see its bytes."
  } else {
    "Binary artifact: text preview unavailable"
  }
}
