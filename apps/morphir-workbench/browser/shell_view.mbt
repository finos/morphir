// The workbench shell: the header with the workspace picker, the left rail, the two sidebars with stacked explorer
// sections, the documents of the active workspace, the tool panel and the generation notification. With no active
// workspace, getting started takes the place of the sidebars and documents.

///|
fn icon_of(name : String) -> @html.Html {
  @html.span(
    class="nav-icon icon-" + name,
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
}

///|
/// The header's workspace picker: the active workspace's name, and a menu of the open and saved workspaces.
fn workspace_picker(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match (model.screen, active_entry(model)) {
    (Workspace, Some(entry)) => entry.name.to_string()
    _ => "Workspaces"
  }
  let waiting = model.acquiring.map(a => a.workspace)
  let listed = model.registry.entries.filter(e => {
    Some(e.id) != waiting &&
    (e.saved || Some(e.id) == model.active || model.parked.contains(e.id))
  })
  let menu = if model.picker {
    let rows : Array[@html.Html] = [
      @html.button(
        class="picker-item",
        attrs=@html.Attrs::build().role("menuitem").data_set("tree-row", "item"),
        on_click=emit(ShowStart),
        [icon_of("home"), @html.span("Getting started")],
      ),
    ]
    if !listed.is_empty() {
      rows.push(@html.p(class="picker-heading", "Workspaces"))
    }
    for entry in listed {
      let current = Some(entry.id) == model.active && model.screen is Workspace
      rows.push(
        @html.button(
          class=if current { "picker-item current" } else { "picker-item" },
          attrs=@html.Attrs::build()
            .role("menuitemradio")
            .data_set("tree-row", "item")
            .aria_checked(current.to_string()),
          on_click=emit(OpenWorkspace(entry.id)),
          [
            icon_of("workspace"),
            @html.span(class="picker-name", entry.name.to_string()),
            @html.span(
              class="picker-detail",
              if model.parked.contains(entry.id) ||
                Some(entry.id) == model.active {
                "open"
              } else {
                entry.preset.label()
              },
            ),
          ],
        ),
      )
    }
    if !model.connected {
      rows.push(
        @html.button(
          class="picker-item",
          attrs=@html.Attrs::build()
            .role("menuitem")
            .data_set("tree-row", "item"),
          on_click=emit(RunCommand(CreateWorkspace)),
          [icon_of("plus"), @html.span("Create a workspace…")],
        ),
      )
      match (model.screen, active_entry(model)) {
        (Workspace, Some(entry)) if Some(entry.id) != waiting =>
          rows.push(
            @html.button(
              id="picker-close",
              class="picker-item",
              title=closing_blocked(model, entry.id).unwrap_or(
                "Save this workspace and close it; it stays under Recent workspaces",
              ),
              attrs=@html.Attrs::build()
                .role("menuitem")
                .data_set("tree-row", "item")
                .aria_label("Close workspace " + entry.name.to_string()),
              on_click=emit(CloseWorkspace(entry.id)),
              [icon_of("close"), @html.span("Close workspace")],
            ),
          )
        _ => ()
      }
    }
    @html.div(
      class="picker-menu",
      attrs=@html.Attrs::build()
        .role("menu")
        .aria_label("Workspaces")
        .on_keydown(event => {
          if event.key() == "Escape" {
            event.prevent_default()
            @cmd.batch([
              emit(Picker(false)),
              focus_after_render("workspace-picker"),
            ])
          } else {
            @shell.on_tree_key(event)
          }
        }),
      rows,
    )
  } else {
    @html.nothing
  }
  @html.div(class="workspace-picker", [
    @html.button(
      id="workspace-picker",
      class="workspace-picker-button",
      title="Switch workspace",
      attrs=@html.Attrs::build()
        .aria_label("Workspace: " + name)
        .aria_haspopup("menu")
        .aria_expanded(model.picker.to_string()),
      on_click=emit(Picker(!model.picker)),
      [
        @html.span(class="workspace-name", name),
        @html.span(
          class="workspace-chevron",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "⌄",
        ),
      ],
    ),
    if model.picker {
      @html.div(
        class="picker-backdrop",
        attrs=@html.Attrs::build().aria_hidden("true"),
        on_click=emit(Picker(false)),
        "",
      )
    } else {
      @html.nothing
    },
    menu,
  ])
}

///|
/// The segmented mode picker: it applies to the source document only, so it shows only there.
fn mode_picker(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let compile_reason = if model.connected || holds(model, SourceProject) {
    ""
  } else {
    "Add a source project to compile"
  }
  @html.div(
    class="mode-switch",
    attrs=@html.Attrs::build().role("group").aria_label("Source mode"),
    [
      @html.button(
        class=if !model.worksheet { "selected" } else { "" },
        disabled=compile_reason != "",
        title=compile_reason,
        attrs=@html.Attrs::build().aria_pressed((!model.worksheet).to_string()),
        on_click=emit(Layout(false)),
        [icon_of("code"), @html.span("Compile & inspect")],
      ),
      @html.button(
        class=if model.worksheet { "selected" } else { "" },
        title="Run Scheme expressions locally",
        attrs=@html.Attrs::build().aria_pressed(model.worksheet.to_string()),
        on_click=emit(Layout(true)),
        [icon_of("document"), @html.span("Worksheet")],
      ),
    ],
  )
}

///|
fn connection(model : Model) -> @html.Html {
  @html.div(class="connection", [
    @html.span(
      class="connection-dot",
      attrs=@html.Attrs::build().aria_hidden("true"),
      "",
    ),
    @html.span(
      if model.connected {
        "Connected host"
      } else {
        local_runtime_label()
      },
    ),
    @html.a(
      href=if model.connected { "?mode=local" } else { "?mode=connected" },
      class="small",
      if model.connected {
        "Use local"
      } else {
        "Connect"
      },
      escape=true,
    ),
  ])
}

///|
fn topbar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let in_workspace = model.screen is Workspace &&
    model.active is Some(_) &&
    model.page is Current
  let secondary = model.layout.is_open(Secondary)
  @html.header(class="topbar", [
    @html.div(class="topbar-start", [
      brand(model.site_home),
      workspace_picker(model, emit),
    ]),
    @html.div(class="topbar-center", [command_center(model, emit)]),
    @html.div(class="topbar-end", [
      if in_workspace && model.doc == Source {
        mode_picker(model, emit)
      } else {
        @html.nothing
      },
      connection(model),
      @html.button(
        id="toggle-secondary",
        class="sidebar-icon-button topbar-toggle",
        hidden=!in_workspace,
        title=if secondary {
          "Hide right sidebar"
        } else {
          "Show right sidebar"
        },
        attrs=@html.Attrs::build()
          .aria_label("Toggle right sidebar")
          .aria_controls(@shell.sidebar_id(Secondary))
          .aria_expanded(secondary.to_string()),
        on_click=emit(Shell(Toggle(Secondary))),
        icon_of("sidebar-right"),
      ),
    ]),
  ])
}

///|
/// The left rail stays visible when the sidebars close. Its explorer button toggles the left sidebar. The theme
/// toggle and the settings button sit at its end.
fn rail(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let settings = model.page is Settings(_)
  let in_workspace = model.screen is Workspace && model.active is Some(_)
  @html.nav(class="rail", attrs=@html.Attrs::build().aria_label("Workbench"), [
    @shell.rail_button(
      id="rail-start",
      label="Getting started",
      icon_name="home",
      active=model.screen is GettingStarted && !settings,
      on_click=emit(ShowStart),
    ),
    if model.active is Some(_) && model.acquiring is None {
      @shell.rail_button(
        id="rail-explorer",
        label="Explorer",
        icon_name="explorer",
        active=in_workspace && model.layout.is_open(Primary) && !settings,
        controls=@shell.sidebar_id(Primary),
        on_click=if in_workspace && settings {
          @cmd.batch([emit(CloseSettings), emit(Shell(SetOpen(Primary, true)))])
        } else if in_workspace {
          emit(Shell(Toggle(Primary)))
        } else {
          match model.active {
            Some(id) => emit(OpenWorkspace(id))
            None => @cmd.none
          }
        },
      )
    } else {
      @html.nothing
    },
    @html.div(class="rail-end", [
      theme_toggle(model, emit),
      settings_button(model, emit),
    ]),
  ])
}

///|
fn files_section(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let project = active_project(model)
  @shell.section(
    model.layout,
    Files,
    count=plural_files(project.files.length()),
    [
      @project_files.view(
        {
          env: explorer_env(model),
          state: model.files_edit,
          language: language_name(model, model.language),
          mac: model.mac,
        },
        emit.map(action => Files(action)),
        extra=[project_storage(model, emit)],
      ),
    ],
    emit.map(action => Shell(action)),
  )
}

///|
fn models_section(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body : Array[@html.Html] = [
    @html.input(
      class="explorer-filter",
      placeholder="Find a declaration…",
      value=model.query,
      attrs=@html.Attrs::build().aria_label("Find a declaration"),
      on_input=emit.map(value => Query(value)),
    ),
  ]
  if model.document.inspection() == Json::null() && model.projects.is_empty() {
    body.push(
      @html.p(
        class="small muted explorer-empty",
        if holds(model, SourceProject) || model.connected {
          "Compile the source to explore its model, or import a model."
        } else if holds(model, ModelDocument) {
          "This workspace's model is not loaded in this page. Import it again to explore it."
        } else {
          "Import a model to explore its declarations."
        },
      ),
    )
    body.push(
      @html.div(class="explorer-empty-actions", [
        @html.button(
          class="ghost small",
          disabled=model.busy,
          on_click=@cmd.batch([emit(ShowDocument(Model)), emit(Import)]),
          [icon_of("import"), @html.span("Import model…")],
        ),
      ]),
    )
  } else {
    body.push(
      @explorer.navigation(
        explorer_props(model),
        emit.map(id => Select(id)),
        emit.map(id => ToggleModule(id)),
      ),
    )
  }
  if !model.projects.is_empty() {
    body.push(@html.p(class="eyebrow", "WORKSPACE PROJECTS"))
    for project in model.projects {
      body.push(
        @html.button(
          class="tree-item",
          disabled=model.busy ||
            field(project, "available") == Json::boolean(false),
          title=text(project, "message"),
          on_click=emit(Project(text(project, "id"))),
          text(project, "name"),
        ),
      )
    }
  }
  let declarations = items(field(model.document.inspection(), "nodes"))
    .filter(node => text(node, "kind") != "module")
    .length()
  @shell.section(
    model.layout,
    Models,
    count=if declarations == 0 {
      ""
    } else {
      declarations.to_string() + " declarations"
    },
    body,
    emit.map(action => Shell(action)),
  )
}

///|
fn generated_section(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let files = @generated.artifacts(model.output)
  @shell.section(
    model.layout,
    Generated,
    count=if files.is_empty() { "" } else { plural_files(files.length()) },
    [
      @generated.explorer(
        {
          output: model.output,
          state: model.generated_state,
          language: model.target,
          mac: model.mac,
        },
        emit.map(action => Generated(action)),
        emit.map(project => DownloadGenerated(project)),
      ),
    ],
    emit.map(action => Shell(action)),
  )
}

///|
fn idea_row(
  model : Model,
  emit : @cmd.Emit[Msg],
  doc : @workspace.Document,
  icon_name : String,
  label : String,
) -> @html.Html {
  let current = model.doc == doc && (doc != Source || model.worksheet)
  @html.button(
    class=if current { "idea-row selected" } else { "idea-row" },
    attrs=@html.Attrs::build()
      .aria_pressed(current.to_string())
      .data_set("tree-row", "idea")
      .data_set("level", "0"),
    on_click=if doc == Source {
      @cmd.batch([emit(ShowDocument(Source)), emit(Layout(true))])
    } else {
      emit(ShowDocument(doc))
    },
    [icon_of(icon_name), @html.span(label)],
  )
}

///|
fn ideas_section(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let rows : Array[@html.Html] = []
  if holds(model, Intent) {
    rows.push(idea_row(model, emit, IntentDraft, "idea", "Modeling intent"))
  }
  if holds(model, ConceptualModel) {
    rows.push(
      idea_row(model, emit, ConceptDraft, "concept", "Conceptual model"),
    )
  }
  if holds(model, Worksheet) {
    rows.push(idea_row(model, emit, Source, "document", "Scratch worksheet"))
  }
  @shell.section(
    model.layout,
    Ideas,
    [
      @html.div(
        class="idea-list",
        attrs=@html.Attrs::build()
          .data_set("tree", "ideas")
          .on_keydown(@shell.on_tree_key),
        rows,
      ),
    ],
    emit.map(action => Shell(action)),
  )
}

///|
fn section_for(
  model : Model,
  view : @shell.View,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  match view {
    Files => files_section(model, emit)
    Models => models_section(model, emit)
    Generated => generated_section(model, emit)
    Ideas => ideas_section(model, emit)
  }
}

///|
/// What a sidebar notes at its foot: the workspace's model or draft state.
fn sidebar_footer(model : Model, side : @shell.Side) -> String {
  if side is Secondary {
    return if @generated.artifacts(model.output).is_empty() {
      ""
    } else {
      "Select a file to preview it in the editor."
    }
  }
  if model.document.inspection() != Json::null() {
    if model.output_revision >= 0 && !model.worksheet {
      "Compiled model · source revision " + model.output_revision.to_string()
    } else {
      "Model loaded"
    }
  } else if holds(model, Intent) || holds(model, ConceptualModel) {
    "Workspace drafts"
  } else {
    ""
  }
}

///|
fn sidebar_for(
  model : Model,
  side : @shell.Side,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @shell.sidebar(
    side,
    model.layout,
    model.layout
    .views_in(side, views_of(model))
    .map(view => section_for(model, view, emit)),
    sidebar_footer(model, side),
    emit.map(action => Shell(action)),
  )
}

///|
fn document_label(model : Model, doc : @workspace.Document) -> String {
  match doc {
    Source => if model.worksheet { "worksheet.scm" } else { source_name(model) }
    Model =>
      if model.selected == "" {
        "Model"
      } else {
        entry_label(model, model.selected)
      }
    IntentDraft => "Modeling intent"
    ConceptDraft => "Conceptual model"
  }
}

///|
fn document_id(doc : @workspace.Document) -> String {
  match doc {
    Source => "source"
    Model => "model"
    IntentDraft => "intent"
    ConceptDraft => "concept"
  }
}

///|
fn document_tabs(
  model : Model,
  emit : @cmd.Emit[Msg],
  actions : @html.Html,
) -> @html.Html {
  let docs = documents_of(model)
  @html.div(class="document-tabs", [
    @html.button(
      class="back-button",
      title="Back",
      attrs=@html.Attrs::build().aria_label("Back"),
      disabled=model.history.is_empty(),
      on_click=emit(Back),
      icon_of("back"),
    ),
    @html.nav(
      class="document-tab-list",
      attrs=@html.Attrs::build().aria_label("Documents"),
      docs.map(doc => {
        let current = model.doc == doc
        @html.button(
          class=if current { "document-tab selected" } else { "document-tab" },
          title=document_label(model, doc),
          attrs=@html.Attrs::build()
            .aria_pressed(current.to_string())
            .data_set("document", document_id(doc)),
          on_click=emit(ShowDocument(doc)),
          [
            icon_of(
              match doc {
                Source => "document"
                Model => "model"
                IntentDraft => "idea"
                ConceptDraft => "concept"
              },
            ),
            @html.span(class="document-tab-label", document_label(model, doc)),
          ],
        )
      }),
    ),
    actions,
  ])
}

///|
/// The source document's compact header: the file, its language and profile, the profile details on demand and the
/// build actions. The build menu lists the other actions with the same availability as the palette.
fn source_header(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let languages = items(field(model.catalog, "frontends")).map(frontend => {
    @html.option(
      value=text(frontend, "languageId"),
      selected=text(frontend, "languageId") ==
        (if model.worksheet { "scheme" } else { model.language }),
      text(frontend, "displayName"),
    )
  })
  let commands = palette_commands(model)
  let reason_of = fn(id : @keys.CommandId) -> String? {
    commands.iter().find_first(c => c.id == id).map(c => c.reason)
  }
  let primary : (@keys.CommandId, String) = if model.worksheet {
    (Run, "Run worksheet")
  } else {
    (Compile, "Compile")
  }
  let primary_reason = reason_of(primary.0).unwrap_or("")
  let others : Array[(String, String, Msg)] = []
  if !model.worksheet {
    if runnable(model) {
      others.push(
        (
          if !model.connected && model.target != "scheme" {
            "Compile & run (Scheme)"
          } else {
            "Compile & run"
          },
          reason_of(Run).unwrap_or(""),
          Request("run"),
        ),
      )
    } else {
      others.push(
        (
          "Evaluate in Explorer",
          if model.connected {
            "This host does not advertise an evaluation method"
          } else {
            "Compile, then select a public function in the Models view to enter inputs and evaluate"
          },
          ShowDocument(Model),
        ),
      )
    }
  }
  if model.busy && model.request_id != 0 {
    others.push(("Cancel", "", Cancel))
  }
  @html.div(class="source-header", [
    @html.div(class="compact-controls", [
      @html.label(class="compact-select", hidden=model.worksheet, [
        @html.span(class="visually-hidden", "Language"),
        @html.select(
          disabled=model.busy || model.worksheet,
          on_change=emit.map(value => Language(value)),
          attrs=@html.Attrs::build()
            .aria_label("Language")
            .value_prop(model.language),
          languages,
        ),
      ]),
      @html.span(
        class="compact-select",
        hidden=!model.worksheet,
        "Scheme worksheet",
      ),
      @html.div(
        class="compact-select",
        hidden=model.connected || model.worksheet,
        [
          @source_selection.view(
            {
              frontend: frontend(model, model.language),
              profile: model.source_profile,
              busy: model.busy,
            },
            on_change=emit.map(value => SourceProfile(value)),
          ),
        ],
      ),
      @html.div(
        class="profile-details",
        hidden=model.connected || model.worksheet,
        [
          @source_selection.capabilities({
            frontend: frontend(model, model.language),
            profile: model.source_profile,
            busy: model.busy,
          }),
        ],
      ),
      @html.button(
        class="secondary small",
        hidden=!model.busy || model.request_id == 0,
        on_click=emit(Cancel),
        if host_execution_pending(model) {
          "Cancel"
        } else if model.connected && !model.worksheet {
          "Discard"
        } else {
          "Cancel"
        },
      ),
      @html.div(class="build-actions", [
        @html.button(
          class="primary small",
          disabled=primary_reason != "",
          title=primary_reason,
          on_click=emit(RunCommand(primary.0)),
          [
            @html.span(
              class="build-glyph",
              attrs=@html.Attrs::build().aria_hidden("true"),
              "▷",
            ),
            @html.span(primary.1),
          ],
        ),
        @html.button(
          id="build-menu-button",
          class="build-menu-button",
          title="More build actions",
          attrs=@html.Attrs::build()
            .aria_label("More build actions")
            .aria_haspopup("menu")
            .aria_expanded(model.build_menu.to_string()),
          on_click=emit(BuildMenu(!model.build_menu)),
          @html.span(
            class="workspace-chevron",
            attrs=@html.Attrs::build().aria_hidden("true"),
            "⌄",
          ),
        ),
        if model.build_menu {
          @html.div(
            class="picker-backdrop",
            attrs=@html.Attrs::build().aria_hidden("true"),
            on_click=emit(BuildMenu(false)),
            "",
          )
        } else {
          @html.nothing
        },
        if model.build_menu {
          @html.div(
            class="build-menu",
            attrs=@html.Attrs::build()
              .role("menu")
              .aria_label("Build actions")
              .on_keydown(event => {
                if event.key() == "Escape" {
                  event.prevent_default()
                  @cmd.batch([
                    emit(BuildMenu(false)),
                    focus_after_render("build-menu-button"),
                  ])
                } else {
                  @shell.on_tree_key(event)
                }
              }),
            others.map(entry => {
              @html.button(
                class="picker-item",
                disabled=entry.1 != "" && entry.0 != "Evaluate in Explorer",
                title=entry.1,
                attrs=@html.Attrs::build()
                  .role("menuitem")
                  .data_set("tree-row", "action")
                  .data_set("level", "0"),
                on_click=@cmd.batch([emit(BuildMenu(false)), emit(entry.2)]),
                [
                  @html.span(entry.0),
                  @html.span(
                    class="picker-detail",
                    hidden=entry.1 == "",
                    entry.1,
                  ),
                ],
              )
            }),
          )
        } else {
          @html.nothing
        },
      ]),
    ]),
  ])
}

///|
fn source_document(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(class="document source-document", [
    @html.div(
      class=if model.generated &&
        !model.worksheet &&
        model.generated_state.expanded {
        "editor-grid output-expanded"
      } else {
        "editor-grid"
      },
      [
        @html.section(class="panel source-panel", [
          @html.div(class="source-body", [
            @editor.view(
              {
                id: "source",
                document_key: if model.worksheet {
                  "worksheet-source|" +
                  model.active.map(id => id.to_string()).unwrap_or("")
                } else {
                  "compile-source|" +
                  model.active.map(id => id.to_string()).unwrap_or("") +
                  "|" +
                  model.language +
                  "|" +
                  source_name(model)
                },
                value: if model.worksheet {
                  model.worksheet_source
                } else {
                  active_text(model)
                },
                language: if model.worksheet {
                  "scheme"
                } else {
                  editor_language(model)
                },
                label: "Source editor",
                read_only: false,
                marks: if model.worksheet {
                  if model.worksheet_report is Some(report) &&
                    worksheet_matches(model, report.source()) {
                    @worksheet_view.marks(report)
                  } else {
                    ""
                  }
                } else {
                  model.problem_marks.get(source_name(model)).unwrap_or("")
                },
                reveal: if model.worksheet {
                  model.worksheet_reveal
                } else {
                  model.reveal
                },
              },
              on_change=emit.map(value => Source(value)),
            ),
          ]),
        ]),
        output_panel(model, emit),
      ],
    ),
  ])
}

///|
fn model_document(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(class="document model-document", [
    @html.div(class="model-toolbar", [
      @html.button(
        class="secondary small",
        hidden=!model.busy,
        on_click=emit(Cancel),
        if host_execution_pending(model) {
          "Cancel"
        } else if model.connected {
          "Discard"
        } else {
          "Cancel"
        },
      ),
      @html.button(
        class="ghost small",
        hidden=!model.workspace_available,
        disabled=model.busy || host_execution_blocks_replacement(model),
        on_click=emit(Request("workspace")),
        [action_icon("folder"), @html.span("Open workspace")],
      ),
      @html.label(class="compact-select", [
        @html.span(class="small muted", "Model format"),
        @html.select(
          disabled=model.busy,
          attrs=@html.Attrs::build()
            .aria_label("Model format")
            .value_prop(model.model_format.map(f => f.codec_id()).unwrap_or("")),
          on_change=emit.map(value => ImportFormat(value)),
          [
            ("", "Automatic"),
            ("morphir-json", "JSON"),
            ("morphir-yaml", "YAML"),
            ("ion-text", "Ion text"),
            ("ion-binary", "Ion binary"),
          ].map(option => {
            @html.option(
              value=option.0,
              selected=model.model_format.map(f => f.codec_id()).unwrap_or("") ==
                option.0,
              option.1,
            )
          }),
        ),
      ]),
      @html.button(
        class="ghost small",
        disabled=model.busy,
        on_click=emit(Import),
        "Import model",
      ),
      @html.button(
        class="ghost small",
        disabled=model.busy,
        title="Import captured files from a YAML tree; browser pickers do not report empty directories",
        on_click=emit(ImportTree),
        "Import YAML tree",
      ),
      @html.button(
        class="ghost small",
        disabled=field(model.document.inspection(), "ir") == Json::null(),
        on_click=emit(Export),
        [action_icon("download"), @html.span("Export IR")],
      ),
      match (model.document.current_revision(), model.document.original()) {
        (Some(revision), Some(file)) =>
          @html.button(
            class="ghost small",
            attrs=@html.Attrs::build().aria_label("Download original file"),
            title="Download " +
              file.filename.to_string() +
              " · original IR " +
              file.format_version.to_release_string(),
            on_click=emit(DownloadOriginal(revision)),
            [action_icon("download"), @html.span("Original file")],
          )
        _ => @html.nothing
      },
      match
        (model.document.current_revision(), model.document.original_tree()) {
        (Some(revision), Some(_)) =>
          @html.button(
            class="ghost small",
            attrs=@html.Attrs::build().aria_label(
              "Download captured original files",
            ),
            title="Download captured original files as ZIP; empty directories absent from the picker are not included",
            on_click=emit(DownloadOriginal(revision)),
            "Original files",
          )
        _ => @html.nothing
      },
      @html.button(
        class="ghost artifact-icon-button close-model-button",
        hidden=model.document.document() == None &&
          model.document.opening() == None,
        disabled=host_execution_blocks_replacement(model) ||
          (model.busy && model.document.opening() == None),
        title="Close model",
        attrs=@html.Attrs::build().aria_label("Close model"),
        on_click=emit(CloseModel),
        [action_icon("close")],
      ),
    ]),
    @html.div(
      hidden=model.host_execution == Json::null(),
      class="evaluation-actions small",
      [
        @html.span(host_execution_status(model.host_execution)),
        @html.button(
          class="secondary",
          hidden=field(model.host_execution, "connected") !=
            Json::boolean(false),
          disabled=model.busy,
          on_click=emit(ResumeExecution),
          "Reconnect / resume",
        ),
      ],
    ),
    @html.div(class="model-body", [
      @explorer.details(
        explorer_props(model),
        emit.map(id => Select(id)),
        emit.map(raw => ExplorerRaw(raw)),
        @evaluation.view(
          {
            runtime: model.evaluation_runtime,
            policy: model.evaluation_policy,
            policy_available: checking_available(model),
            input_mode: model.evaluation_mode,
            result_mode: model.result_mode,
            profile: evaluation_profile(
              model.document.inspection(),
              model.selected,
              model.evaluation_runtime.is_typed(),
              capabilities=capability_descriptions(model),
            ),
            document_key: "evaluation-" +
            model.model_revision.to_string() +
            "-" +
            model.selected +
            "-" +
            model.evaluation_runtime.is_typed().to_string(),
            arguments: model.evaluation_arguments,
            result: if model.evaluation_entry == model.selected {
              model.evaluation_result
            } else {
              Json::null()
            },
            terminal: model.evaluation_terminal,
            stale: model.evaluation_result_revision != model.evaluation_revision,
            busy: model.busy,
            connected: model.connected,
            executions_available: model.executions_available,
            execution_pending: host_execution_pending(model) ||
            host_execution_disconnected(model) ||
            model.submission_unknown,
          },
          emit.map(value => EvaluationArguments(value)),
          emit(Evaluate),
          emit.map(value => EvaluationMode(value)),
          emit.map(edit => EvaluationEdit(edit)),
          emit.map(mode => ResultMode(mode)),
          emit.map(mode => EvaluationRuntime(mode)),
          emit.map(policy => EvaluationPolicy(policy)),
        ),
      ),
    ]),
  ])
}

///|
/// A draft document: modeling intent or a conceptual model. Drafts are the person's own text; nothing compiles or
/// infers them.
fn draft_document(
  model : Model,
  emit : @cmd.Emit[Msg],
  doc : @workspace.Document,
) -> @html.Html {
  let (id, title, guidance, placeholder, value, on_input) = match doc {
    ConceptDraft =>
      (
        "concept-text",
        "Conceptual model",
        "Describe the concepts, their relationships and the rules between them.",
        "Order: placed by a Customer, holds Lines, is priced before fulfilment…",
        model.concept,
        emit.map(text => ConceptText(text)),
      )
    _ =>
      (
        "intent-text",
        "Modeling intent",
        "Describe the outcome, domain meaning, rules and constraints you want to express.",
        "Express how an order is accepted, priced and fulfilled.",
        model.intent,
        emit.map(text => IntentText(text)),
      )
  }
  let saved = active_entry(model).map(e => e.saved).unwrap_or(false)
  @html.div(class="document draft-document", [
    @html.div(class="draft-body", [
      @html.h1(title),
      @html.p(class="muted", guidance),
      @html.textarea(
        id~,
        class="draft-text",
        placeholder~,
        value~,
        attrs=@html.Attrs::build().aria_label(title),
        on_input~,
        ([] : Array[@html.Html]),
      ),
      @html.p(
        class="small muted",
        if saved {
          "Saved in this browser as you type. Add source, imported models or experiments to this workspace whenever you need them."
        } else {
          "Kept in this page. Add source, imported models or experiments to this workspace whenever you need them."
        },
      ),
      add_content_actions(model, emit),
    ]),
  ])
}

///|
/// Buttons that add content the workspace does not hold yet.
fn add_content_actions(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  if model.connected {
    return @html.nothing
  }
  let actions : Array[@html.Html] = []
  for
    entry in [
      (@workspace.Content::Intent, "Capture intent", "idea"),
      (ConceptualModel, "Sketch a conceptual model", "concept"),
      (SourceProject, "Add a source project", "code"),
      (ModelDocument, "Import a model", "model"),
      (Worksheet, "Open a worksheet", "document"),
    ] {
    if !holds(model, entry.0) {
      actions.push(
        @html.button(
          class="ghost small",
          disabled=model.busy && entry.0 == ModelDocument,
          on_click=emit(AddContent(entry.0)),
          [icon_of(entry.2), @html.span(entry.1)],
        ),
      )
    }
  }
  if actions.is_empty() {
    @html.nothing
  } else {
    @html.div(
      class="add-content",
      attrs=@html.Attrs::build()
        .role("group")
        .aria_label("Add to this workspace"),
      actions,
    )
  }
}

///|
fn empty_document(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(class="document draft-document", [
    @html.div(class="draft-body", [
      @html.h1("This workspace is empty"),
      @html.p(
        class="muted",
        "Start with intent or a conceptual model, or add source, a model or a worksheet.",
      ),
      add_content_actions(model, emit),
    ]),
  ])
}

///|
fn documents(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let docs = documents_of(model)
  let doc = if docs.contains(model.doc) { Some(model.doc) } else { docs.get(0) }
  @html.div(class="documents", [
    if docs.is_empty() {
      @html.nothing
    } else {
      document_tabs(
        model,
        emit,
        if doc == Some(Source) {
          source_header(model, emit)
        } else {
          @html.nothing
        },
      )
    },
    match doc {
      Some(Source) => source_document(model, emit)
      Some(Model) => model_document(model, emit)
      Some(IntentDraft as draft) | Some(ConceptDraft as draft) =>
        draft_document(model, emit, draft)
      None => empty_document(model, emit)
    },
  ])
}

///|
fn notification(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  match model.notice {
    Some(notice) if model.screen is Workspace =>
      @html.div(
        class="notification",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        [
          @html.div(class="notification-heading", [
            @html.strong("Generation complete"),
            @html.button(
              class="sidebar-icon-button",
              title="Dismiss",
              attrs=@html.Attrs::build().aria_label("Dismiss notification"),
              on_click=emit(DismissNotice),
              icon_of("close"),
            ),
          ]),
          @html.p(
            plural_files(notice.files) +
            (if notice.files == 1 { " is" } else { " are" }) +
            " ready to inspect" +
            (if notice.target == "" {
              "."
            } else {
              " for target " + notice.target + "."
            }),
          ),
          @html.button(
            class="secondary small",
            on_click=emit(ShowGenerated),
            "Show generated files",
          ),
        ],
      )
    _ => @html.nothing
  }
}

///|
fn view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let in_workspace = model.screen is Workspace && model.active is Some(_)
  let settings = model.page is Settings(_)
  let layout = model.layout
  let style = "--primary-width:" +
    (if in_workspace && layout.is_open(Primary) {
      layout.primary.width
    } else {
      0
    }).to_string() +
    "px;--secondary-width:" +
    (if in_workspace && layout.is_open(Secondary) {
      layout.secondary.width
    } else {
      0
    }).to_string() +
    "px"
  @html.div(
    class="workbench" +
      (if in_workspace { " has-workspace" } else { " starting" }) +
      (if model.panel.size == @bottom_panel.Collapsed {
        ""
      } else {
        " tool-open"
      }),
    attrs=@html.Attrs::build().style_attr(style),
    [
      topbar(model, emit),
      rail(model, emit),
      if in_workspace {
        @html.div(
          class="workspace-area",
          hidden=settings,
          attrs=@html.Attrs::build()
            .data_set(
              "workspace",
              model.active.map(id => id.to_string()).unwrap_or(""),
            )
            .data_set("opening", model.opening.to_string()),
          [
            sidebar_for(model, Primary, emit),
            @html.main_(class="document-area", [
              documents(model, emit),
              @bottom_panel.view(
                {
                  state: model.panel,
                  status: model.status,
                  busy: model.busy,
                  revisions: Map([
                    ("source", model.revision),
                    ("worksheet", model.worksheet_revision),
                    ("inputs", model.evaluation_revision),
                    ("model", model.model_revision),
                    ("decode", model.output_revision),
                  ]),
                },
                emit.map(action => Panel(action)),
              ),
            ]),
            sidebar_for(model, Secondary, emit),
          ],
        )
      } else {
        @html.main_(class="start-area", hidden=settings, [
          getting_started(model, emit),
        ])
      },
      if settings {
        settings_page(model, emit)
      } else {
        @html.nothing
      },
      notification(model, emit),
      @palette.view(
        {
          state: model.palette,
          entries: if model.palette.open {
            palette_entries(model)
          } else {
            []
          },
          mac: model.mac,
          no_files: if model.connected {
            "This host edits one source, so there are no project files. Type > to search commands."
          } else if model.active is None || !holds(model, SourceProject) {
            "This workspace has no project files. Type > to search commands."
          } else {
            "The project has no files."
          },
        },
        emit.map(action => Palette(action)),
      ),
    ],
  )
}

///|
fn start_action(
  id~ : String,
  icon_name~ : String,
  title~ : String,
  guidance~ : String,
  expanded? : Bool,
  disabled_reason~ : String = "",
  on_click~ : @cmd.Cmd,
) -> @html.Html {
  // The title names the action; its guidance describes it.
  let attrs = @html.Attrs::build()
    .aria_label(title)
    .aria_describedby(id + "-guidance")
  let attrs = match expanded {
    Some(open) =>
      attrs.aria_expanded(open.to_string()).aria_controls(id + "-choices")
    None => attrs
  }
  @html.button(
    id~,
    class="start-action",
    disabled=disabled_reason != "",
    title=disabled_reason,
    attrs~,
    on_click~,
    [
      icon_of(icon_name),
      @html.span(class="start-action-text", [
        @html.span(class="start-action-title", title),
        @html.span(
          id=id + "-guidance",
          class="start-action-guidance",
          if disabled_reason == "" {
            guidance
          } else {
            disabled_reason
          },
        ),
      ]),
      @html.span(
        class="start-action-chevron",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "›",
      ),
    ],
  )
}

///|
fn start_choice(
  label : String,
  detail : String,
  icon_name : String,
  on_click : @cmd.Cmd,
  disabled~ : Bool = false,
) -> @html.Html {
  @html.button(
    class="start-choice",
    disabled~,
    attrs=@html.Attrs::build().aria_label(label).aria_description(detail),
    on_click~,
    [
      icon_of(icon_name),
      @html.span(class="start-action-text", [
        @html.span(class="start-choice-title", label),
        @html.span(class="start-action-guidance", detail),
      ]),
    ],
  )
}

///|
/// Getting started: four ways in, the workspaces opened before, and examples kept apart from that history.
fn getting_started(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let connected_reason = if model.connected {
    "A connected host provides one workspace"
  } else {
    ""
  }
  let busy = if model.busy && model.acquiring is None {
    busy_reason
  } else {
    ""
  }
  let panel = model.start.panel
  let actions : Array[@html.Html] = [
    start_action(
      id="start-idea",
      icon_name="idea",
      title="Try an idea",
      guidance="Start with intent, a conceptual model, or scratch work.",
      expanded=panel == Idea,
      disabled_reason=connected_reason,
      on_click=emit(StartPanel(Idea)),
    ),
  ]
  if panel == Idea {
    actions.push(
      @html.div(id="start-idea-choices", class="start-choices", [
        start_choice(
          "Capture intent",
          "Describe the outcome, meaning and rules you want to express.",
          "idea",
          emit(TryIdea(Intent)),
        ),
        start_choice(
          "Sketch a conceptual model",
          "Name the concepts, their relationships and rules.",
          "concept",
          emit(TryIdea(ConceptualModel)),
        ),
        start_choice(
          "Scratch worksheet",
          "Evaluate Scheme expressions locally.",
          "document",
          emit(TryIdea(Worksheet)),
        ),
      ]),
    )
  }
  actions.push(
    start_action(
      id="start-open",
      icon_name="folder",
      title="Open a workspace",
      guidance="Continue from a source folder or saved workspace.",
      expanded=panel == OpenChoices,
      on_click=if model.connected {
        match model.registry.entries.get(0) {
          Some(entry) => emit(OpenWorkspace(entry.id))
          None => @cmd.none
        }
      } else {
        emit(StartPanel(OpenChoices))
      },
    ),
  )
  if panel == OpenChoices && !model.connected {
    let choices : Array[@html.Html] = [
      start_choice(
        "Import a source folder…",
        "Copy a morphir.json folder into a new workspace in this browser; nothing is written back.",
        "import",
        emit(OpenFolder),
        disabled=busy != "",
      ),
    ]
    if model.workspace_available {
      choices.push(
        start_choice(
          "Open a folder with read-only access…",
          "Grant this desktop page read-only access to a folder of Morphir projects.",
          "folder-open",
          emit(OpenHostFolder),
          disabled=busy != "",
        ),
      )
    }
    choices.push(
      @html.p(
        class="small muted start-choice-note",
        if model.registry.recents(except=None).is_empty() {
          "Saved workspaces appear under Recent workspaces."
        } else {
          "Or choose a saved workspace under Recent workspaces."
        },
      ),
    )
    actions.push(
      @html.div(id="start-open-choices", class="start-choices", choices),
    )
  }
  actions.push(
    start_action(
      id="start-create",
      icon_name="plus",
      title="Create a workspace",
      guidance="Choose a starting point and make it your own.",
      expanded=panel == CreateChoices,
      disabled_reason=connected_reason,
      on_click=emit(StartPanel(CreateChoices)),
    ),
  )
  if panel == CreateChoices {
    actions.push(
      @html.div(id="start-create-choices", class="start-choices start-form", [
        @html.label(class="start-field", [
          @html.span("Name"),
          @html.input(
            id="create-name",
            value=model.start.name,
            placeholder=model.registry
              .unique_name(model.start.preset.base_name())
              .to_string(),
            attrs=@html.Attrs::build()
              .aria_invalid((model.start.name_error != "").to_string())
              .aria_describedby("create-name-error")
              .on_keydown(event => {
                if event.key() == "Enter" {
                  event.prevent_default()
                  emit(CreateWorkspace)
                } else {
                  @cmd.none
                }
              }),
            on_input=emit.map(text => StartName(text)),
          ),
        ]),
        @html.p(
          id="create-name-error",
          class="small file-error",
          hidden=model.start.name_error == "",
          model.start.name_error,
        ),
        @html.fieldset(
          class="start-presets",
          [
            @html.legend("Start with"),
            ..[
              (
                @workspace.Preset::Empty,
                "Nothing yet; add content when you need it.",
              ),
              (SourceProject, "A source project in the default language."),
              (Sandbox, "Modeling intent, ready for ideas and experiments."),
            ].map(entry => {
              @html.label(class="start-preset", [
                @html.input(
                  input_type=Radio,
                  name="create-preset",
                  checked=model.start.preset == entry.0,
                  on_change=emit.map(_ => StartPreset(entry.0)),
                ),
                @html.span(class="start-action-text", [
                  @html.span(class="start-choice-title", entry.0.label()),
                  @html.span(class="start-action-guidance", entry.1),
                ]),
              ])
            }),
          ],
        ),
        @html.p(
          class="small muted",
          "Location: this browser. Source projects and drafts are saved here as you work.",
        ),
        @html.button(
          class="primary small",
          on_click=emit(CreateWorkspace),
          "Create workspace",
        ),
      ]),
    )
  }
  actions.push(
    start_action(
      id="start-explore",
      icon_name="model",
      title="Explore a model",
      guidance="Inspect the types, values and functions in a Morphir model.",
      expanded=panel == ExploreChoices,
      disabled_reason=connected_reason,
      on_click=emit(StartPanel(ExploreChoices)),
    ),
  )
  if panel == ExploreChoices {
    actions.push(
      @html.div(id="start-explore-choices", class="start-choices", [
        start_choice(
          "Import a model file…",
          "JSON, YAML, Ion text or Ion binary. The original bytes are kept.",
          "import",
          emit(ExploreModel(false)),
          disabled=busy != "",
        ),
        start_choice(
          "Import a YAML model tree…",
          "A folder of YAML files and sidecars, as captured by the browser.",
          "folder-open",
          emit(ExploreModel(true)),
          disabled=busy != "",
        ),
      ]),
    )
  }
  let recents = model.registry.recents()
  let recent_rows : Array[@html.Html] = if recents.is_empty() {
    [@html.p(class="small muted", "Workspaces you open will appear here.")]
  } else {
    recents.map(entry => {
      let removing = model.start.removing == Some(entry.id)
      @html.li(class="recent-row", [
        @html.button(
          id="recent-open-" + entry.id.to_string(),
          class="recent-open",
          attrs=@html.Attrs::build().aria_label(
            "Open " + entry.name.to_string(),
          ),
          on_click=emit(OpenWorkspace(entry.id)),
          [
            @html.span(class="recent-name", entry.name.to_string()),
            @html.span(
              class="start-action-guidance",
              {
                let listed = entry.contents.map(c => c.label()).join(" · ")
                if listed == "" {
                  entry.preset.label()
                } else {
                  listed
                }
              },
            ),
          ],
        ),
        if removing {
          @html.span(
            class="recent-confirm",
            attrs=@html.Attrs::build()
              .role("group")
              .aria_label("Remove " + entry.name.to_string() + "?"),
            [
              @html.span(class="small", "Remove from this browser?"),
              @html.button(
                id="recent-remove-confirm",
                class="danger small",
                on_click=emit(RemoveWorkspace(entry.id)),
                "Remove",
              ),
              @html.button(
                class="secondary small",
                on_click=emit(AskRemove(None)),
                "Keep",
              ),
            ],
          )
        } else if model.parked.contains(entry.id) ||
          model.active == Some(entry.id) {
          // A workspace open in this page closes before it can be removed.
          @html.button(
            id="recent-close-" + entry.id.to_string(),
            class="secondary small recent-close",
            title=closing_blocked(model, entry.id).unwrap_or(
              "Save this workspace and close it in this page",
            ),
            attrs=@html.Attrs::build().aria_label(
              "Close " + entry.name.to_string(),
            ),
            hidden=model.connected,
            on_click=emit(CloseWorkspace(entry.id)),
            "Close",
          )
        } else {
          @html.button(
            class="sidebar-icon-button recent-remove",
            title="Remove from this browser",
            attrs=@html.Attrs::build().aria_label(
              "Remove " + entry.name.to_string() + " from this browser",
            ),
            hidden=model.connected,
            on_click=emit(AskRemove(Some(entry.id))),
            icon_of("close"),
          )
        },
      ])
    })
  }
  let examples = [
    (
      "builtin:scheme", "Pricing & arithmetic", "Scheme source compiled to a portable model",
    ),
    (
      "builtin:moonbit-supported", "MoonBit library", "MoonBit source, its model and generated code",
    ),
    (
      "builtin:scheme-elm", "Elm constant", "Scheme source that generates an Elm library",
    ),
  ]
  @html.div(class="getting-started", [
    @html.div(class="start-intro", [
      @html.img(class="start-logo", src="./morphir-logo.svg", alt="Morphir"),
      @html.h1(
        id="start-heading",
        attrs=@html.Attrs::build().tabindex(-1),
        "Start with an idea.",
      ),
      @html.p(
        class="muted",
        "Capture intent, shape a conceptual model, or work with source.",
      ),
    ]),
    @html.div(
      class="start-message",
      attrs=@html.Attrs::build().role("status"),
      hidden=model.start.message == "" && model.acquiring is None,
      [
        @html.span(
          if model.acquiring is Some(_) {
            if model.status == "" {
              "Waiting for your selection…"
            } else {
              model.status
            }
          } else {
            model.start.message
          },
        ),
        if model.acquiring is Some(_) {
          @html.button(
            class="secondary small",
            on_click=emit(StopAcquiring),
            "Stop waiting",
          )
        } else {
          @html.nothing
        },
      ],
    ),
    @html.div(class="start-columns", [
      @html.div(
        class="start-actions",
        attrs=@html.Attrs::build().role("group").aria_label("Get started"),
        actions,
      ),
      @html.div(class="start-side", [
        @html.section(
          attrs=@html.Attrs::build().aria_labelledby("recent-heading"),
          [
            @html.h2(
              id="recent-heading",
              attrs=@html.Attrs::build().tabindex(-1),
              "Recent workspaces",
            ),
            @html.ul(class="recent-list", recent_rows),
          ],
        ),
        @html.section(
          attrs=@html.Attrs::build().aria_labelledby("examples-heading"),
          [
            @html.h2(id="examples-heading", "Explore an example"),
            @html.ul(
              class="example-list",
              examples.map(example => {
                @html.li([
                  @html.button(
                    class="example-link",
                    disabled=model.connected || busy != "",
                    on_click=emit(OpenExample(example.0)),
                    example.1,
                  ),
                  @html.span(class="start-action-guidance", example.2),
                ])
              }),
            ),
          ],
        ),
      ]),
    ]),
    @html.p(
      class="small muted start-foot",
      "One workspace can bring together intent, conceptual models, source and experiments.",
    ),
  ])
}
