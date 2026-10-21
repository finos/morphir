// The settings page and the theme. Settings shows over the current screen, which keeps its state, so closing it
// returns to the same workspace, document and layout. The theme belongs to the whole Workbench: changing it
// touches no workspace.

///|
/// The page in the main area: the current screen, or the settings page shown over it.
enum Page {
  Current
  /// The settings page, and the id of the control that opened it.
  Settings(String?)
} derive(Eq)

///|
/// The id of the settings page heading, which takes the focus when the page opens.
let settings_heading_id : String = "settings-heading"

///|
extern "js" fn system_dark() -> Bool =
  #|() => { try { return globalThis.matchMedia?.('(prefers-color-scheme: dark)')?.matches === true; } catch { return false; } }

///|
/// The appearance the system shows now. Without `matchMedia`, as in tests, it is light.
fn system_appearance() -> @settings.Appearance {
  if system_dark() {
    Dark
  } else {
    Light
  }
}

///|
/// Reports each change of the system appearance: true when it turns dark.
extern "js" fn watch_system_appearance(receive : (Bool) -> Unit) =
  #|(receive) => { try { globalThis.matchMedia?.('(prefers-color-scheme: dark)')?.addEventListener('change', (event) => receive(event.matches)); } catch {} }

///|
/// Reports each Escape that no control handled: menus, the palette and dialogs prevent the default of their own.
/// The listener runs on the window after the page's handlers, wherever the focus is.
extern "js" fn watch_escape(receive : () -> Unit) =
  #|(receive) => { try { globalThis.addEventListener?.('keydown', (event) => { if (event.key === 'Escape' && !event.defaultPrevented && !event.isComposing) receive(); }); } catch {} }

///|
/// Sets the root element's `data-theme`; an empty value removes it, so the stylesheet follows the system.
extern "js" fn apply_data_theme(value : String) =
  #|(value) => {
  #|  try {
  #|    const root = globalThis.document?.documentElement;
  #|    if (!root) return;
  #|    if (value === '') delete root.dataset.theme; else root.dataset.theme = value;
  #|  } catch {}
  #|}

///|
/// Focuses the element with `id`, or the one with `fallback` when there is no such element.
extern "js" fn focus_or(id : String, fallback : String) =
  #|(id, fallback) => (document.getElementById(id) ?? document.getElementById(fallback))?.focus()

///|
fn apply_theme(theme : @settings.ThemePreference) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => apply_data_theme(theme.data_theme().unwrap_or("")))
}

///|
/// Watches the system appearance and Escape, and applies the saved theme, which the head script of `index.html`
/// already set before the first paint.
fn watch_theme(
  settings : @settings.Settings,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.batch([
    apply_theme(settings.theme),
    @cmd.custom_cmd(scheduler => {
      watch_system_appearance(dark => {
        scheduler.add(emit(SystemAppearance(if dark { Dark } else { Light })))
      })
    }),
    @cmd.custom_cmd(scheduler => {
      watch_escape(() => scheduler.add(emit(EscapeSettings)))
    }),
  ])
}

///|
fn update_settings(model : Model, msg : Msg) -> (Model, @cmd.Cmd) {
  match msg {
    OpenSettings(opener) =>
      match model.page {
        Settings(_) => (model, focus_after_render(settings_heading_id))
        Current =>
          (
            {
              ..model,
              page: Settings(opener),
              picker: false,
              build_menu: false,
            },
            focus_after_render(settings_heading_id),
          )
      }
    CloseSettings => close_settings(model)
    // Escape closes settings unless the palette or a header menu is open; those close first.
    EscapeSettings =>
      if model.palette.open || model.picker || model.build_menu {
        (model, @cmd.none)
      } else {
        close_settings(model)
      }
    Theme(theme) => {
      let settings = { ..model.settings, theme, }
      let model = { ..model, settings, }
      let model = if storage_save(@settings.storage_key, settings.encode()) {
        model
      } else {
        note(
          model,
          "Settings",
          @bottom_panel.Warning,
          "This browser did not keep the theme; it applies in this page until you leave",
        )
      }
      (model, apply_theme(theme))
    }
    WorkspaceSidebar(workspace_sidebar) => {
      let settings = { ..model.settings, workspace_sidebar, }
      let model = { ..model, settings, }
      let model = if storage_save(@settings.storage_key, settings.encode()) {
        model
      } else {
        note(
          model,
          "Settings",
          @bottom_panel.Warning,
          "This browser did not keep the workspace sidebar choice; it applies in this page until you leave",
        )
      }
      (model, focus_after_render(workspace_sidebar_toggle_id))
    }
    EditorLayout(editor_layout) => {
      let settings = { ..model.settings, editor_layout, }
      let model = { ..model, settings, }
      let model = if storage_save(@settings.storage_key, settings.encode()) {
        model
      } else {
        note(
          model,
          "Settings",
          @bottom_panel.Warning,
          "This browser did not keep the editor layout; it applies in this page until you leave",
        )
      }
      (model, @cmd.none)
    }
    SystemAppearance(system_appearance) =>
      ({ ..model, system_appearance, }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// Closes the settings page. The control that opened it takes the focus back; without one, the workspace picker
/// or the getting-started heading does.
fn close_settings(model : Model) -> (Model, @cmd.Cmd) {
  guard model.page is Settings(opener) else { return (model, @cmd.none) }
  let fallback = if model.screen is Workspace && model.active is Some(_) {
    "workspace-picker"
  } else {
    "start-heading"
  }
  (
    { ..model, page: Current, },
    @cmd.custom_cmd(
      _ => focus_or(opener.unwrap_or(fallback), fallback),
      kind=@cmd.after_render,
    ),
  )
}

///|
/// The page without settings, for navigation that goes somewhere else; the navigation moves the focus itself.
fn leave_settings(model : Model) -> Model {
  match model.page {
    Settings(_) => { ..model, page: Current, }
    Current => model
  }
}

///|
/// True for navigation that goes to its own target and so leaves the settings page: getting started, opening,
/// creating or switching a workspace, its contents and documents, and Back.
fn leaves_settings(msg : Msg) -> Bool {
  msg
  is (ShowStart
  | CreateWorkspace
  | TryIdea(_)
  | OpenExample(_)
  | OpenFolder
  | OpenHostFolder
  | ExploreModel(_)
  | OpenWorkspace(_)
  | AddContent(_)
  | ShowDocument(_)
  | ShowGenerated
  | Back
  | Layout(_))
}

///|
/// True for commands that keep the settings page: settings and theme commands, and those that only open the
/// palette, whose choice decides.
fn keeps_settings(command : @keys.CommandId) -> Bool {
  command
  is (OpenSettings
  | UseSystemTheme
  | UseLightTheme
  | UseDarkTheme
  | ToggleTheme
  | ToggleWorkspaceSidebar
  | UseSideBySide
  | UseTabs
  | ShowCommands
  | GoToFile
  | SwitchLanguage
  | SetTarget
  | SelectProfile
  | SwitchWorkspace
  | ContextMenu)
}

///|
/// The theme toggle in the upper-right corner of the header: an icon for the current theme, and a click moves to the
/// next.
fn theme_toggle(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let theme = model.settings.theme
  let label = "Theme: " + theme.label()
  @html.button(
    id="theme-toggle",
    class="sidebar-icon-button topbar-toggle theme-toggle",
    title=label,
    attrs=@html.Attrs::build().aria_label(label),
    on_click=emit(Theme(theme.next())),
    icon_of("theme-" + theme.id()),
  )
}

///|
/// The settings button of the left rail. It opens the settings page, or closes it when it shows.
fn settings_button(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let open = model.page is Settings(_)
  @shell.rail_button(
    id="rail-settings",
    label="Settings",
    icon_name="settings",
    active=open,
    current=open,
    on_click=if open {
      emit(CloseSettings)
    } else {
      emit(OpenSettings(Some("rail-settings")))
    },
  )
}

///|
/// The settings page: its heading, a close button and the Appearance section. Escape closes it from anywhere.
fn settings_page(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let current = model.settings.theme
  let choices = @settings.themes.map(theme => {
    let id = "theme-" + theme.id()
    @html.label(class="theme-choice", for_=id, [
      @html.input(
        input_type=Radio,
        name="theme",
        value=theme.id(),
        id~,
        checked=theme == current,
        on_change=emit.map(_ => Theme(theme)),
      ),
      @html.span(
        match theme {
          System => "System (currently " + model.system_appearance.label() + ")"
          Light | Dark => theme.label()
        },
      ),
    ])
  })
  @html.main_(
    id="settings",
    class="settings-area",
    attrs=@html.Attrs::build().aria_labelledby(settings_heading_id),
    [
      @html.div(class="settings-page", [
        @html.header(class="settings-header", [
          @html.h1(
            id=settings_heading_id,
            attrs=@html.Attrs::build().tabindex(-1),
            "Settings",
          ),
          @html.button(
            id="settings-close",
            class="sidebar-icon-button",
            title="Close settings",
            attrs=@html.Attrs::build().aria_label("Close settings"),
            on_click=emit(CloseSettings),
            icon_of("close"),
          ),
        ]),
        @html.section(
          class="settings-section",
          attrs=@html.Attrs::build().aria_labelledby("settings-appearance"),
          [
            @html.h2(id="settings-appearance", "Appearance"),
            @html.fieldset(
              class="theme-choices",
              [
                @html.legend("Theme"),
                ..choices,
                @html.p(
                  class="settings-help",
                  "System follows the appearance of your operating system or browser.",
                ),
              ],
            ),
            @html.fieldset(
              class="theme-choices",
              [
                @html.legend("Source and output"),
                ..@settings.editor_layouts.map(layout => {
                  let id = "editor-layout-" + layout.id()
                  @html.label(class="theme-choice", for_=id, [
                    @html.input(
                      input_type=Radio,
                      name="editor-layout",
                      value=layout.id(),
                      id~,
                      checked=layout == model.settings.editor_layout,
                      on_change=emit.map(_ => EditorLayout(layout)),
                    ),
                    @html.span(layout.label()),
                  ])
                }),
                @html.p(
                  class="settings-help",
                  "Side by side shows the source beside its Morphir IR or generated files; Tabs shows one at a time.",
                ),
              ],
            ),
          ],
        ),
        projects_settings(model, emit),
      ]),
    ],
  )
}

///|
/// The projects of the open workspace, each with its language, source profile and generation target. A project's
/// target is saved with it; Compile sends the current project's target.
fn projects_settings(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body : Array[@html.Html] = []
  let snapshot = model.workspace_files.discover() catch {
    _ => return @html.p("Fix morphir.toml to see project settings.")
  }
  let current = current_project_path(model).to_string()
  for i, project in snapshot.projects {
    let path = if project.root == snapshot.root {
      ""
    } else if snapshot.root == "" {
      project.root
    } else {
      project.root[snapshot.root.length() + 1:].to_owned()
    }
    let key = known(() => @discovery.ProjectPath::parse(path))
    let read_only = !workspace_writable(model) ||
      !project.anchor.has_suffix(".toml")
    let language = project.document.text("frontend.language", "scheme") catch {
      _ => "scheme"
    }
    let controls : Array[@html.Html] = [
      @html.div(class="project-setting-name", [
        @html.strong(project.name),
        @html.span(
          class="settings-help",
          (if path == "" { "." } else { path }) +
          " · " +
          language_name(model, language) +
          (if path == current { " · current" } else { "" }),
        ),
      ]),
    ]
    for
      (setting, label, offers) in [
        (
          @workspace_files.Language,
          "Language",
          items(field(model.catalog, "frontends")).map(f => {
            (text(f, "languageId"), text(f, "displayName"))
          }),
        ),
        (
          @workspace_files.SourceProfile,
          "Source profile",
          items(field(frontend(model, language), "profiles")).map(p => {
            (text(p, "id"), text(p, "id"))
          }),
        ),
        (
          @workspace_files.Generation,
          "Generation target",
          [("checkpoint", "No generation")] +
          items(field(model.catalog, "targets")).map(t => {
            (text(t, "target"), text(t, "displayName"))
          }),
        ),
      ] {
      let value = model.workspace_files.setting(key, setting) catch {
        _ =>
          @workspace_files.SettingValue::{
            effective: None,
            override_value: None,
            origin: None,
          }
      }
      let chosen = value.override_value.unwrap_or("")
      let options = [
        @html.option(value="", selected=chosen == "", "Use workspace value"),
      ]
      if chosen != "" && !offers.any(offer => offer.0 == chosen) {
        options.push(
          @html.option(value=chosen, selected=true, chosen + " (unavailable)"),
        )
      }
      for (id, name) in offers {
        options.push(@html.option(value=id, selected=chosen == id, name))
      }
      controls.push(
        @html.label(class="project-setting-field", [
          @html.span(label),
          @html.select(
            disabled=model.busy || read_only,
            attrs=@html.Attrs::build()
              .aria_label(label + " for " + project.name)
              .value_prop(chosen)
              .data_set("project-path", path)
              .data_set(
                "current-project",
                (path == current && setting is Generation).to_string(),
              )
              .data_set("effective", value.effective.unwrap_or("")),
            on_change=emit.map(value => ProjectSetting(path, setting, value)),
            options,
          ),
          @html.span(
            class="settings-help",
            if value.override_value is None {
              "Inherited: " +
              value.effective.unwrap_or("default") +
              " from " +
              value.origin.unwrap_or("defaults")
            } else {
              "Set in " + project.anchor
            },
          ),
        ]),
      )
    }
    controls.push(
      @source_selection.capabilities({
        frontend: frontend(model, language),
        profile: project.document.text(
          "frontend.profile",
          text(frontend(model, language), "defaultProfile"),
        ) catch {
          _ => ""
        },
        busy: model.busy,
      }),
    )
    if !project.anchor.has_suffix(".toml") {
      controls.push(
        @html.p(
          class="settings-help",
          "This morphir.json project is read-only until converted.",
        ),
      )
      controls.push(
        @html.button(
          disabled=!workspace_writable(model) || model.busy,
          on_click=emit(ConvertLegacyProject(path)),
          "Convert to morphir.toml",
        ),
      )
    }
    controls.push(
      @html.button(
        class="ghost small",
        on_click=emit(OpenWorkspaceFile(project.anchor)),
        "Open " + project.anchor,
      ),
    )
    body.push(
      @html.div(
        id="project-settings-" + i.to_string(),
        class="project-setting",
        controls,
      ),
    )
  }
  let members = [@html.option(value="", "Every project")]
  let selected = snapshot.document.text("workspace.default_member", "") catch {
    _ => ""
  }
  for project in snapshot.projects {
    let path = if project.root == snapshot.root {
      "."
    } else if snapshot.root == "" {
      project.root
    } else {
      project.root[snapshot.root.length() + 1:].to_owned()
    }
    members.push(
      @html.option(
        value=path,
        selected=selected == path,
        project.name + " (" + path + ")",
      ),
    )
  }
  body.push(@html.h3("Workspace defaults"))
  body.push(
    @html.label(class="project-setting-field", [
      @html.span("Compile workspace"),
      @html.select(
        disabled=!workspace_writable(model) || model.busy,
        attrs=@html.Attrs::build()
          .aria_label("Workspace default member")
          .value_prop(selected),
        on_change=emit.map(value => {
          WorkspaceSetting(@workspace_files.DefaultMember, value)
        }),
        members,
      ),
    ]),
  )
  body.push(
    @html.button(
      class="ghost small",
      on_click=emit(OpenWorkspaceFile(snapshot.anchor)),
      "Edit workspace defaults in morphir.toml",
    ),
  )
  body.push(
    @html.p(class="settings-help", "Browser builds check sources only."),
  )
  @html.section(
    class="settings-section",
    attrs=@html.Attrs::build().aria_labelledby("settings-projects"),
    [@html.h2(id="settings-projects", "Projects"), ..body],
  )
}
