///|
enum WorkspaceNode {
  Folder(String)
  Project(@discovery.ProjectPath)
} derive(Eq)

///|
enum ProjectField {
  Name
  Folder
  Language
  Profile
} derive(Eq)

///|
struct NewProjectDraft {
  name : String
  folder : String
  language : String
  profile : String
  problem : String
} derive(Eq)

///|
enum ProjectDialog {
  Adding(NewProjectDraft)
  Removing(@discovery.ProjectPath, Bool, String)
  FileChange(WorkspaceFileAction, String, String, String)
} derive(Eq)

///|
enum WorkspaceFileAction {
  Create
  Rename
  Delete
} derive(Eq)

///|
fn project_folder(model : Model, name : String) -> String {
  let members = model.workspace_files.discover().document.strings(
    "workspace.members",
  ) catch {
    _ => []
  }
  (if members.any(m => m.has_prefix("packages/")) { "packages/" } else { "" }) +
  @workspace.slug_of(name)
}

///|
fn update_workspace_explorer(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    WorkspaceFilter(filter) =>
      ({ ..model, files_edit: { ..model.files_edit, filter, }, }, @cmd.none)
    AskWorkspaceFile(action, path) if workspace_writable(model) && !model.busy =>
      (
        {
          ..model,
          doc: Source,
          worksheet: false,
          layout: model.layout.apply(Reveal(Files)),
          project_dialog: Some(FileChange(action, path, path, "")),
        },
        focus_after_render("workspace-file-path"),
      )
    WorkspaceFilePath(replacement) => {
      guard model.project_dialog is Some(FileChange(action, path, _, _)) else {
        return (model, @cmd.none)
      }
      (
        {
          ..model,
          project_dialog: Some(FileChange(action, path, replacement, "")),
        },
        @cmd.none,
      )
    }
    CommitWorkspaceFile if workspace_writable(model) && !model.busy => {
      guard model.project_dialog
        is Some(FileChange(action, path, replacement, _)) else {
        return (model, @cmd.none)
      }
      let files = try {
        if action is Delete {
          move_model_file_index(
            model.workspace_files,
            model.workspace_files.remove(path),
            path,
            None,
          )
        } else {
          if @discovery.normalize(replacement) != replacement ||
            replacement == "" {
            raise @config.Invalid("Use a confined relative file path")
          }
          if replacement != path || action is Create {
            if model.workspace_files.content(replacement) is Some(_) {
              raise @config.Invalid("A file already exists at " + replacement)
            }
          }
          let content = if action is Rename {
            model.workspace_files.content(path).unwrap_or(@data.Text(""))
          } else {
            @data.Text("")
          }
          let changed = if action is Rename {
            model.workspace_files.remove(path)
          } else {
            model.workspace_files
          }
          let files = changed
            .write_content(replacement, content)
            .open(replacement)
          if action is Rename {
            move_model_file_index(
              model.workspace_files,
              files,
              path,
              Some(replacement),
            )
          } else {
            files
          }
        }
      } catch {
        @config.Invalid(problem) =>
          return (
            {
              ..model,
              project_dialog: Some(
                FileChange(action, path, replacement, problem),
              ),
            },
            @cmd.none,
          )
        _ => return (model, @cmd.none)
      }
      let changed = {
        ..with_workspace_files(model, files),
        project_dialog: None,
        doc: Source,
      }
      if action is Delete &&
        original_model_files_present(model, model.workspace_files) &&
        !original_model_files_present(model, files) {
        return update_core(changed, CloseModel, emit)
      }
      (changed, @cmd.none)
    }
    FilesView(files_view) => {
      let settings = { ..model.settings, files_view, }
      ignore(storage_save(@settings.storage_key, settings.encode()))
      ({ ..model, settings, }, @cmd.none)
    }
    ToggleWorkspaceNode(node) => {
      let collapsed = if model.workspace_collapsed.contains(node) {
        model.workspace_collapsed.filter(n => n != node)
      } else {
        model.workspace_collapsed + [node]
      }
      ({ ..model, workspace_collapsed: collapsed, }, @cmd.none)
    }
    ProjectMenu(project_menu) => ({ ..model, project_menu, }, @cmd.none)
    DismissProjectDialog => ({ ..model, project_dialog: None, }, @cmd.none)
    AddWorkspaceProject if workspace_writable(model) && !model.busy => {
      let language = model.workspace_files.discover().document.text(
        "frontend.language", "scheme",
      ) catch {
        _ => "scheme"
      }
      (
        {
          ..model,
          project_dialog: Some(
            Adding({ name: "", folder: "", language, profile: "", problem: "", }),
          ),
          project_menu: None,
        },
        focus_after_render("new-project-name"),
      )
    }
    EditNewProject(field, value) => {
      guard model.project_dialog is Some(Adding(draft)) else {
        return (model, @cmd.none)
      }
      let changed = match field {
        Name =>
          {
            ..draft,
            name: value,
            folder: if draft.folder == "" ||
              draft.folder == project_folder(model, draft.name) {
              project_folder(model, value)
            } else {
              draft.folder
            },
          }
        Folder => { ..draft, folder: value, }
        Language => { ..draft, language: value, profile: "", }
        Profile => { ..draft, profile: value, }
      }
      (
        { ..model, project_dialog: Some(Adding({ ..changed, problem: "", })), },
        @cmd.none,
      )
    }
    CreateWorkspaceProject if workspace_writable(model) && !model.busy => {
      guard model.project_dialog is Some(Adding(draft)) else {
        return (model, @cmd.none)
      }
      let files = try {
        let path = @discovery.ProjectPath::parse(draft.folder)
        if draft.folder == "" {
          raise @config.Invalid(
            "Enter a project folder, or . for a root project",
          )
        }
        let files = model.workspace_files.add_project(path, {
          name: @ids.SourcePackageName::parse(draft.name.trim().to_owned()),
          language: Some(@ids.LanguageId::parse(draft.language)),
          profile: if draft.profile == "" {
            None
          } else {
            Some(@ids.ProfileId::parse(draft.profile))
          },
          source_directory: "src",
        })
        let snapshot = files.discover()
        let root = @discovery.join(snapshot.root, path.to_string())
        let source = files
          .paths()
          .iter()
          .find_first(p => {
            @discovery.within(root, p) &&
            (
              p.has_suffix(".scm") ||
              p.has_suffix(".mbt") ||
              p.has_suffix(".elm")
            )
          })
        match source {
          Some(path) => files.open(path)
          None => files
        }
      } catch {
        @config.Invalid(problem) =>
          return (
            { ..model, project_dialog: Some(Adding({ ..draft, problem, })), },
            @cmd.none,
          )
        _ => return (model, @cmd.none)
      }
      (
        {
          ..with_workspace_files(model, files),
          project_dialog: None,
          doc: Source,
          worksheet: false,
        },
        @cmd.none,
      )
    }
    AskRemoveProject(path) if workspace_writable(model) && !model.busy =>
      (
        {
          ..model,
          project_dialog: Some(Removing(path, false, "")),
          project_menu: None,
        },
        focus_after_render("remove-project-confirm"),
      )
    DeleteProjectFiles(remove) => {
      guard model.project_dialog is Some(Removing(path, _, problem)) else {
        return (model, @cmd.none)
      }
      (
        { ..model, project_dialog: Some(Removing(path, remove, problem)), },
        @cmd.none,
      )
    }
    RemoveWorkspaceProject if workspace_writable(model) && !model.busy => {
      guard model.project_dialog is Some(Removing(path, delete_files, _)) else {
        return (model, @cmd.none)
      }
      let files = model.workspace_files.remove_project(path, delete_files~) catch {
        @config.Invalid(problem) =>
          return (
            {
              ..model,
              project_dialog: Some(Removing(path, delete_files, problem)),
            },
            @cmd.none,
          )
        _ => return (model, @cmd.none)
      }
      (
        { ..with_workspace_files(model, files), project_dialog: None, },
        @cmd.none,
      )
    }
    CompileWorkspaceProject(path) => {
      let snapshot = model.workspace_files.discover() catch {
        _ => return (model, @cmd.none)
      }
      let root = @discovery.join(snapshot.root, path.to_string()) catch {
        _ => return (model, @cmd.none)
      }
      guard snapshot.projects.iter().find_first(p => p.root == root)
        is Some(project) else {
        return (model, @cmd.none)
      }
      let files = model.workspace_files.open(project.anchor) catch {
        _ => return (model, @cmd.none)
      }
      update_core(
        { ..with_workspace_files(model, files), project_menu: None, },
        Request("compile-project"),
        emit,
      )
    }
    _ => (model, @cmd.none)
  }
}

///|
extern "js" fn show_workspace_file_actions(event : @dom.Event) =
  #|event => {
  #|  const actions = event.target.closest('.workspace-file-row')?.querySelector('details');
  #|  if (actions) { actions.open = true; actions.querySelector('button')?.focus(); }
  #|}

///|
fn workspace_file_row(
  model : Model,
  path : String,
  label : String,
  level : Int32,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let active = model.workspace_files.opened() == Some(path)
  @html.div(class="workspace-file-row", [
    @html.button(
      class=if active { "tree-item active" } else { "tree-item" },
      title=path,
      attrs=@html.Attrs::build()
        .role("treeitem")
        .tabindex(if active { 0 } else { -1 })
        .aria_selected(active.to_string())
        .data_set("path", path)
        .data_set("tree-row", "item")
        .data_set("level", level.to_string())
        .on_contextmenu(event => {
          event.prevent_default()
          event.stop_propagation()
          show_workspace_file_actions(event.as_event())
          @cmd.none
        })
        .on_keydown(event => {
          if event.key() == "F2" && workspace_writable(model) && !model.busy {
            event.prevent_default()
            emit(AskWorkspaceFile(Rename, path))
          } else if event.key() == "ContextMenu" ||
            (event.key() == "F10" && event.shift_key()) {
            event.prevent_default()
            show_workspace_file_actions(event.as_event())
            @cmd.none
          } else {
            @cmd.none
          }
        })
        .style("padding-left", (10 + level * 14).to_string() + "px"),
      on_click=emit(OpenWorkspaceFile(path)),
      [icon_of("document"), @html.span(label)],
    ),
    @html.details(class="workspace-file-actions", [
      @html.summary(
        attrs=@html.Attrs::build().aria_label("File actions for " + path),
        icon_of("more"),
      ),
      @html.div(class="workspace-project-actions", [
        @html.button(
          class="ghost small",
          disabled=!workspace_writable(model) || model.busy,
          on_click=emit(AskWorkspaceFile(Rename, path)),
          "Rename or move…",
        ),
        @html.button(
          class="ghost small",
          disabled=!workspace_writable(model) || model.busy,
          on_click=emit(AskWorkspaceFile(Delete, path)),
          "Delete…",
        ),
      ]),
    ]),
  ])
}

///|
fn workspace_folder_rows(
  model : Model,
  folder : String,
  paths : Array[String],
  level : Int32,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  let children : Map[String, Bool] = Map([])
  let prefix = if folder == "" { "" } else { folder + "/" }
  for path in paths {
    guard path.strip_prefix(prefix) is Some(rest) else { continue }
    let child = rest.split("/").next().unwrap_or("").to_owned()
    children[prefix + child] = rest.contains("/")
  }
  let sorted = children.keys().collect()
  sorted.sort_by((a, b) => a.lexical_compare(b))
  let rows : Array[@html.Html] = []
  for child in sorted {
    let name = child.strip_prefix(prefix).unwrap_or(child[:]).to_owned()
    if !children[child] {
      rows.push(workspace_file_row(model, child, name, level, emit))
      continue
    }
    let node = WorkspaceNode::Folder(child)
    let expanded = !model.workspace_collapsed.contains(node)
    let badge = discovered_projects(model)
      .iter()
      .find_first(p => p.root == child)
    let label = name +
      badge
      .map(p => {
        " · " +
        p.name +
        " · " +
        (p.document.text("frontend.language", "scheme") catch { _ => "" })
      })
      .unwrap_or("")
    rows.push(
      @html.button(
        class="tree-item workspace-folder",
        attrs=@html.Attrs::build()
          .role("treeitem")
          .tabindex(-1)
          .aria_expanded(expanded.to_string())
          .data_set("path", child)
          .data_set("tree-row", "folder")
          .data_set("level", level.to_string())
          .style("padding-left", (10 + level * 14).to_string() + "px"),
        on_click=emit(ToggleWorkspaceNode(node)),
        [icon_of("folder"), @html.span(label)],
      ),
    )
    if expanded {
      rows.append(workspace_folder_rows(model, child, paths, level + 1, emit))
    }
  }
  rows
}

///|
fn workspace_projects_rows(
  model : Model,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  if !workspace_writable(model) && !model.projects.is_empty() {
    return model.projects.map(project => {
      @html.button(
        class="tree-item",
        title=text(project, "message"),
        disabled=model.busy ||
          field(project, "available") == Json::boolean(false),
        attrs=@html.Attrs::build().role("treeitem"),
        on_click=emit(Project(text(project, "id"))),
        [
          icon_of("folder"),
          @html.span(text(project, "name")),
          @html.span(class="project-language", "Read-only"),
        ],
      )
    })
  }
  let snapshot = model.workspace_files.discover() catch {
    _ =>
      return [
        @html.p(
          class="small",
          "Fix the workspace configuration to discover projects.",
        ),
      ]
  }
  let current = current_project_path(model)
  let rows : Array[@html.Html] = [
    workspace_file_row(
      model,
      snapshot.anchor,
      "Workspace · " + snapshot.anchor,
      0,
      emit,
    ),
  ]
  for project in snapshot.projects {
    let relative = if project.root == snapshot.root {
      ""
    } else if snapshot.root == "" {
      project.root
    } else {
      project.root[snapshot.root.length() + 1:].to_owned()
    }
    let path = known(() => @discovery.ProjectPath::parse(relative))
    let node = WorkspaceNode::Project(path)
    let expanded = !model.workspace_collapsed.contains(node)
    let language = project.document.text("frontend.language", "scheme") catch {
      _ => "invalid configuration"
    }
    rows.push(
      @html.div(class="workspace-project-row", [
        @html.button(
          class=if path == current {
            "tree-item current-project"
          } else {
            "tree-item"
          },
          title=if relative == "" { "." } else { relative },
          attrs=@html.Attrs::build()
            .role("treeitem")
            .tabindex(-1)
            .aria_expanded(expanded.to_string())
            .data_set("path", relative)
            .data_set("tree-row", "folder")
            .data_set("level", "0")
            .on_contextmenu(event => {
              event.prevent_default()
              event.stop_propagation()
              @cmd.batch([
                emit(ProjectMenu(Some(path))),
                focus_after_render("project-compile-" + relative),
              ])
            })
            .on_keydown(event => {
              if event.key() == "ContextMenu" ||
                (event.key() == "F10" && event.shift_key()) {
                event.prevent_default()
                @cmd.batch([
                  emit(ProjectMenu(Some(path))),
                  focus_after_render("project-compile-" + relative),
                ])
              } else {
                @cmd.none
              }
            }),
          on_click=emit(ToggleWorkspaceNode(node)),
          [
            icon_of("folder"),
            @html.span(project.name),
            @html.span(class="project-language", language),
          ],
        ),
        @html.button(
          id="project-actions-" + relative,
          class="sidebar-icon-button",
          attrs=@html.Attrs::build()
            .aria_label("Actions for " + project.name)
            .aria_haspopup("menu")
            .aria_expanded((model.project_menu == Some(path)).to_string()),
          on_click=emit(
            ProjectMenu(
              if model.project_menu == Some(path) {
                None
              } else {
                Some(path)
              },
            ),
          ),
          icon_of("more"),
        ),
      ]),
    )
    if model.project_menu == Some(path) {
      rows.push(
        @html.div(
          class="workspace-project-actions",
          attrs=@html.Attrs::build()
            .role("menu")
            .aria_label("Actions for " + project.name)
            .data_set("tree", "project-actions")
            .on_keydown(event => {
              if event.key() == "Escape" {
                event.prevent_default()
                event.stop_propagation()
                @cmd.batch([
                  emit(ProjectMenu(None)),
                  focus_after_render("project-actions-" + relative),
                ])
              } else {
                @shell.on_tree_key(event)
              }
            }),
          [
            @html.button(
              id="project-compile-" + relative,
              class="ghost small",
              attrs=@html.Attrs::build()
                .role("menuitem")
                .data_set("tree-row", "item"),
              disabled=model.busy,
              on_click=emit(CompileWorkspaceProject(path)),
              "Compile",
            ),
            @html.button(
              class="ghost small",
              attrs=@html.Attrs::build()
                .role("menuitem")
                .data_set("tree-row", "item"),
              on_click=@cmd.batch([
                emit(OpenWorkspaceFile(project.anchor)),
                emit(OpenSettings(None)),
              ]),
              "Settings",
            ),
            @html.button(
              class="ghost small",
              attrs=@html.Attrs::build()
                .role("menuitem")
                .data_set("tree-row", "item"),
              disabled=!workspace_writable(model) || model.busy,
              title=if !workspace_writable(model) {
                "This location is read-only"
              } else {
                ""
              },
              on_click=emit(AskRemoveProject(path)),
              "Remove…",
            ),
          ],
        ),
      )
    }
    if expanded {
      let paths = model.workspace_files
        .paths()
        .filter(file => {
          file != snapshot.anchor &&
          @discovery.within(project.root, file) &&
          !snapshot.projects.any(other => {
            other.root != project.root &&
            @discovery.within(project.root, other.root) &&
            @discovery.within(other.root, file)
          })
        })
      for
        file in paths.filter(p => {
          p.to_lower().contains(model.files_edit.filter.to_lower())
        }) {
        let label = if project.root == "" {
          file
        } else {
          file[project.root.length() + 1:].to_owned()
        }
        rows.push(workspace_file_row(model, file, label, 1, emit))
      }
    }
  }
  let loose = model.workspace_files
    .paths()
    .filter(file => {
      file != snapshot.anchor &&
      !snapshot.projects.any(p => @discovery.within(p.root, file))
    })
  for
    file in loose.filter(p => {
      p.to_lower().contains(model.files_edit.filter.to_lower())
    }) {
    rows.push(workspace_file_row(model, file, file, 0, emit))
  }
  rows
}

///|
fn workspace_project_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  guard model.project_dialog is Some(dialog) else { return @html.nothing }
  let body : Array[@html.Html] = []
  match dialog {
    Adding(draft) => {
      body.push(@html.h3("Add project"))
      for
        (field, label, value, id) in [
          (ProjectField::Name, "Name", draft.name, "new-project-name"),
          (Folder, "Folder", draft.folder, "new-project-folder"),
        ] {
        body.push(
          @html.label([
            @html.span(label),
            @html.input(
              id~,
              value~,
              attrs=@html.Attrs::build().aria_label(
                "Project " + label.to_lower(),
              ),
              on_input=emit.map(v => EditNewProject(field, v)),
            ),
          ]),
        )
      }
      let options = items(field(model.catalog, "frontends")).map(f => {
        @html.option(
          value=text(f, "languageId"),
          selected=draft.language == text(f, "languageId"),
          text(f, "displayName"),
        )
      })
      body.push(
        @html.label([
          @html.span("Language"),
          @html.select(
            attrs=@html.Attrs::build()
              .aria_label("Project language")
              .value_prop(draft.language),
            on_change=emit.map(v => EditNewProject(Language, v)),
            options,
          ),
        ]),
      )
      let profiles = [
        @html.option(
          value="",
          selected=draft.profile == "",
          "Default source profile",
        ),
      ]
      for profile in items(field(frontend(model, draft.language), "profiles")) {
        profiles.push(
          @html.option(
            value=text(profile, "id"),
            selected=draft.profile == text(profile, "id"),
            text(profile, "id"),
          ),
        )
      }
      body.push(
        @html.label([
          @html.span("Source profile"),
          @html.select(
            attrs=@html.Attrs::build()
              .aria_label("New project source profile")
              .value_prop(draft.profile),
            on_change=emit.map(v => EditNewProject(Profile, v)),
            profiles,
          ),
        ]),
      )
      body.push(@html.p(class="small error", draft.problem))
      body.push(
        @html.button(on_click=emit(CreateWorkspaceProject), "Create project"),
      )
    }
    Removing(path, delete_files, problem) => {
      body.push(@html.h3("Remove project?"))
      body.push(
        @html.p(
          if path.to_string() == "" {
            "Remove the root project from this workspace."
          } else {
            "Remove " + path.to_string() + " from this workspace."
          },
        ),
      )
      if path.to_string() != "" {
        body.push(
          @html.label([
            @html.input(
              input_type=Checkbox,
              checked=delete_files,
              on_change=emit.map(_ => DeleteProjectFiles(!delete_files)),
            ),
            @html.span("Delete the project's files too"),
          ]),
        )
      }
      body.push(@html.p(class="small error", problem))
      body.push(
        @html.button(
          id="remove-project-confirm",
          on_click=emit(RemoveWorkspaceProject),
          "Remove project",
        ),
      )
    }
    FileChange(action, path, replacement, problem) => {
      body.push(
        @html.h3(
          match action {
            Create => "New file"
            Rename => "Rename or move file"
            Delete => "Delete file?"
          },
        ),
      )
      if action is Delete {
        body.push(@html.p(path))
      } else {
        body.push(
          @html.label([
            @html.span("Workspace-relative path"),
            @html.input(
              id="workspace-file-path",
              value=replacement,
              attrs=@html.Attrs::build().aria_label("File path"),
              on_input=emit.map(v => WorkspaceFilePath(v)),
            ),
          ]),
        )
      }
      body.push(@html.p(class="small error", problem))
      body.push(
        @html.button(
          on_click=emit(CommitWorkspaceFile),
          match action {
            Create => "Create file"
            Rename => "Move file"
            Delete => "Delete file"
          },
        ),
      )
    }
  }
  body.push(
    @html.button(class="ghost", on_click=emit(DismissProjectDialog), "Cancel"),
  )
  @html.div(
    class="workspace-project-dialog",
    attrs=@html.Attrs::build()
      .role("dialog")
      .aria_label("Project changes")
      .on_keydown(event => {
        if event.key() == "Escape" {
          event.prevent_default()
          emit(DismissProjectDialog)
        } else {
          @cmd.none
        }
      }),
    body,
  )
}

///|
fn workspace_files_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let view = model.settings.files_view
  let filtered = model.workspace_files
    .paths()
    .filter(path => path.to_lower().contains(model.files_edit.filter.to_lower()))
  let rows = if !workspace_writable(model) && !model.projects.is_empty() {
    workspace_projects_rows(model, emit)
  } else if view is Folders {
    workspace_folder_rows(model, "", filtered, 0, emit)
  } else {
    workspace_projects_rows(model, emit)
  }
  @html.div(class="workspace-files", [
    @html.div(class="workspace-file-views", [
      @html.button(
        class="ghost small",
        attrs=@html.Attrs::build().aria_pressed((view is Folders).to_string()),
        on_click=emit(FilesView(Folders)),
        "Folders",
      ),
      @html.button(
        class="ghost small",
        attrs=@html.Attrs::build().aria_pressed((view is Projects).to_string()),
        on_click=emit(FilesView(Projects)),
        "Projects",
      ),
    ]),
    @html.input(
      class="explorer-filter",
      placeholder="Find a file…",
      value=model.files_edit.filter,
      attrs=@html.Attrs::build().aria_label("Find a file"),
      on_input=emit.map(value => WorkspaceFilter(value)),
    ),
    @html.div(
      attrs=@html.Attrs::build()
        .role("tree")
        .data_set("tree", "workspace-files")
        .aria_label("Workspace files")
        .on_keydown(@shell.on_tree_key),
      rows,
    ),
    @html.button(
      class="ghost small",
      disabled=!workspace_writable(model) || model.busy,
      title=if !workspace_writable(model) {
        "This location is read-only"
      } else {
        ""
      },
      on_click=emit(AddWorkspaceProject),
      [icon_of("plus"), @html.span("Add project…")],
    ),
    @html.button(
      class="ghost small",
      disabled=!workspace_writable(model) || model.busy,
      on_click=emit(AskWorkspaceFile(Create, "")),
      "New file…",
    ),
    if !workspace_writable(model) {
      @html.p(
        class="small muted",
        match model.file_access {
          ReadOnly(reason) => reason
          _ => "This location is read-only."
        },
      )
    } else {
      @html.nothing
    },
    workspace_project_dialog(model, emit),
    project_storage(model, emit),
  ])
}
