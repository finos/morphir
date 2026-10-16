///|
pub(all) struct Props {
  output : Json
  state : State
  language : String
}

///|
pub(all) struct State {
  selected : String
  collapsed : Array[String]
  files_visible : Bool
  expanded : Bool
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
pub enum Action {
  Select(String)
  ToggleFolder(String)
  ToggleFiles
  ToggleExpanded
}

///|
pub fn State::new() -> State {
  { selected: "", collapsed: [], files_visible: true, expanded: false, }
}

///|
pub fn State::update(self : State, action : Action) -> State {
  match action {
    Select(selected) => { ..self, selected, }
    ToggleFolder(path) => {
      let collapsed = if self.collapsed.contains(path) {
        self.collapsed.filter(p => p != path)
      } else {
        self.collapsed + [path]
      }
      { ..self, collapsed, }
    }
    ToggleFiles => { ..self, files_visible: !self.files_visible, }
    ToggleExpanded => { ..self, expanded: !self.expanded, }
  }
}

///|
/// New output clears file/folder selection but retains the user's layout choice.
pub fn State::reset(self : State) -> State {
  { ..self, selected: "", collapsed: [], }
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
  selected_path : String,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let path = text(file, "path")
  @html.li([
    @html.button(
      class=if path == selected_path {
        "artifact-file selected"
      } else {
        "artifact-file"
      },
      title=path,
      attrs=@html.Attrs::build()
        .aria_label(path)
        .aria_pressed((path == selected_path).to_string()),
      on_click=emit(Select(path)),
      [icon("document"), @html.span(class="artifact-name", label)],
    ),
  ])
}

///|
fn file_tree(
  files : Array[Json],
  prefix : String,
  depth : Int32,
  state : State,
  selected_path : String,
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
          file_tree(files, path, depth + 1, state, selected_path, emit),
        ]),
      ]),
    )
  }
  for (file, label) in leaves {
    rows.push(file_button(file, label, selected_path, emit))
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
  if path != "" {
    preview.push(
      @html.div(class="artifact-file-heading", [
        breadcrumb(path),
        @html.span(class="artifact-readonly", hidden=!binary, "Binary"),
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
      document_key: "generated|" + path,
      language: language(path, props.language),
      label: "Generated output",
      read_only: true,
      value: if binary {
        "Binary artifact: text preview unavailable"
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
          [file_tree(files, "", 0, props.state, path, emit)],
        ),
        @html.div(class="artifact-preview", preview),
      ],
    ),
  )
  @html.div(class="generated-output", body)
}
