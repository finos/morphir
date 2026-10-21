///|
/// A source workspace with an edit, an intent draft, an open Model document and Back history.
fn settings_workspace() -> Model {
  run_all(starting_model(), [
    StartPreset(SourceProject),
    CreateWorkspace,
    Source("(define kept 1)"),
    AddContent(Intent),
    IntentText("Keep this"),
    ShowDocument(Model),
    Shell(Toggle(Secondary)),
  ])
}

///|
/// The parts of the page that settings must leave as they were.
fn workspace_view(
  model : Model,
) -> (
  Screen,
  @workspace.WorkspaceId?,
  @workspace.Document,
  @shell.Layout,
  Array[Location],
  String,
) {
  (
    model.screen,
    model.active,
    model.doc,
    model.layout,
    model.history,
    model.intent,
  )
}

///|
test "settings opens over getting started and closes back to it" {
  let restore = storage_test_environment("")
  defer restore()
  let start = starting_model()
  let open = run_all(start, [OpenSettings(Some("rail-settings"))])
  let closed = run_all(open, [CloseSettings])
  @expect.expect_all(s => {
    s
    .expect(open.page == Settings(Some("rail-settings")), label="open")
    .to_be_true()
    s.expect(open.screen == GettingStarted, label="screen kept").to_be_true()
    s.expect(closed.page == Current, label="closed").to_be_true()
    s
    .expect(closed == { ..open, page: Current, }, label="nothing else")
    .to_be_true()
  })
}

///|
test "settings keeps the workspace, document, layout and Back history" {
  let restore = storage_test_environment("")
  defer restore()
  let page = settings_workspace()
  let open = run_all(page, [OpenSettings(None)])
  let closed = run_all(open, [CloseSettings])
  @expect.expect_all(s => {
    s.expect(page.history.is_empty(), label="has history").to_be_false()
    s
    .expect(workspace_view(open) == workspace_view(page), label="while open")
    .to_be_true()
    s
    .expect(workspace_view(closed) == workspace_view(page), label="after close")
    .to_be_true()
    s.expect(open.parked == page.parked, label="nothing parked").to_be_true()
    s.expect(open.registry == page.registry, label="nothing saved").to_be_true()
  })
}

///|
test "settings does not cancel work that is running" {
  let restore = storage_test_environment("")
  defer restore()
  let page = { ..settings_workspace(), busy: true, request_id: 7, }
  let open = run_all(page, [OpenSettings(None), Theme(Dark)])
  @expect.expect_all(s => {
    s.expect(open.busy, label="still busy").to_be_true()
    s.expect(open.request_id, label="same request").to_equal(7)
    s.expect(open.busy_origin == page.busy_origin, label="origin").to_be_true()
  })
}

///|
test "navigation from the rail, the header and the palette leaves settings for its target" {
  let restore = storage_test_environment("")
  defer restore()
  let page = settings_workspace()
  let id = page.active.unwrap()
  let started = run_all(page, [OpenSettings(None), ShowStart])
  let reopened = run_all(started, [OpenSettings(None), OpenWorkspace(id)])
  let source = run_all(page, [OpenSettings(None), ShowDocument(Source)])
  let back = run_all(page, [OpenSettings(None), Back])
  let compiled = run_command(
      run_all(page, [OpenSettings(None)]),
      ShowSource,
      quiet(),
    ).0
  @expect.expect_all(s => {
    s.expect(started.page == Current, label="getting started").to_be_true()
    s.expect(started.screen == GettingStarted, label="its screen").to_be_true()
    s.expect(reopened.page == Current, label="workspace picker").to_be_true()
    s.expect(reopened.screen == Workspace, label="the workspace").to_be_true()
    s.expect(source.page == Current, label="document").to_be_true()
    s.expect(source.doc == Source, label="its document").to_be_true()
    s.expect(back.page == Current, label="Back").to_be_true()
    s.expect(compiled.page == Current, label="command").to_be_true()
  })
}

///|
test "settings and theme commands keep the page; opening it again changes nothing" {
  let restore = storage_test_environment("")
  defer restore()
  let open = run_all(starting_model(), [OpenSettings(Some("rail-settings"))])
  let themed = run_command(open, ToggleTheme, quiet()).0
  let again = run_command(themed, OpenSettings, quiet()).0
  let palette = run_command(again, ShowCommands, quiet()).0
  @expect.expect_all(s => {
    s.expect(themed.page == open.page, label="theme").to_be_true()
    s.expect(themed.settings.theme, label="toggled").to_equal(Light)
    s.expect(again.page == open.page, label="opener kept").to_be_true()
    s.expect(palette.page == open.page, label="palette").to_be_true()
  })
}

///|
test "closing the active workspace while settings shows returns where closing goes" {
  let restore = storage_test_environment("")
  defer restore()
  let page = three_ideas()
  let third = page.active.unwrap()
  let open = run_all(page, [OpenSettings(None)])
  let closed = run_command(open, CloseWorkspace, quiet()).0
  let alone = run_all(starting_model(), [TryIdea(Intent), OpenSettings(None)])
  let alone_closed = run_all(alone, [CloseWorkspace(alone.active.unwrap())])
  @expect.expect_all(s => {
    s.expect(closed.page == Current, label="palette close leaves").to_be_true()
    s.expect(closed.active == Some(third), label="closed").to_be_false()
    s.expect(closed.screen == Workspace, label="another workspace").to_be_true()
    s
    .expect(alone_closed.page == Settings(None), label="still open")
    .to_be_true()
    s
    .expect(
      run_all(alone_closed, [CloseSettings]).screen == GettingStarted,
      label="returns to getting started",
    )
    .to_be_true()
  })
}

///|
test "choosing a theme saves it for the whole Workbench and touches no workspace" {
  let restore = storage_test_environment("")
  defer restore()
  let page = settings_workspace()
  let dark = run_all(page, [Theme(Dark)])
  let saved = storage_load(@settings.storage_key)
  let system = run_command(dark, UseSystemTheme, quiet()).0
  @expect.expect_all(s => {
    s.expect(dark.settings.theme, label="dark").to_equal(Dark)
    s.expect(saved, label="saved").to_equal("{\"theme\":\"dark\"}")
    s
    .expect(
      dark == { ..page, settings: dark.settings, },
      label="only the setting",
    )
    .to_be_true()
    s.expect(system.settings.theme, label="system").to_equal(System)
    s
    .expect(storage_load(@settings.storage_key), label="saved again")
    .to_equal("{\"theme\":\"system\"}")
  })
}

///|
test "a theme that is not saved still applies, with a warning" {
  let restore = storage_test_environment("morphir-workbench.settings")
  defer restore()
  let dark = run_all(starting_model(), [Theme(Dark)])
  @expect.expect_all(s => {
    s.expect(dark.settings.theme, label="applied").to_equal(Dark)
    s
    .expect(storage_load(@settings.storage_key), label="not saved")
    .to_equal("")
    s.expect(dark.panel != starting_model().panel, label="warned").to_be_true()
  })
}

///|
test "the page starts with the saved theme and follows the system appearance" {
  let restore = storage_test_environment("")
  defer restore()
  ignore(storage_save(@settings.storage_key, "{\"theme\":\"light\"}"))
  let page = initial()
  let darker = run_all(page, [SystemAppearance(Dark)])
  @expect.expect_all(s => {
    s.expect(page.settings.theme, label="saved theme").to_equal(Light)
    s.expect(page.system_appearance, label="no matchMedia").to_equal(Light)
    s.expect(page.page == Current, label="no settings").to_be_true()
    s.expect(darker.system_appearance, label="followed").to_equal(Dark)
    s.expect(darker.settings.theme, label="choice kept").to_equal(Light)
  })
}

///|
test "Escape closes settings from anywhere unless the palette or a header menu is open" {
  let restore = storage_test_environment("")
  defer restore()
  let open = run_all(settings_workspace(), [OpenSettings(None)])
  let picker = run_all(open, [Picker(true), EscapeSettings])
  let escaped = run_all(open, [EscapeSettings])
  let start = starting_model()
  let page = run_all(start, [EscapeSettings])
  @expect.expect_all(s => {
    s.expect(picker.page == open.page, label="picker open").to_be_true()
    s.expect(escaped.page == Current, label="closed").to_be_true()
    s.expect(page == start, label="nothing without settings").to_be_true()
  })
}

///|
test "side by side, each pane expands; as tabs, an output tab shows the output alone" {
  let restore = storage_test_environment("")
  defer restore()
  let model = settings_workspace()
  let source_wide = run_command(model, ToggleSourceWidth, quiet()).0
  let restored = run_command(source_wide, ToggleSourceWidth, quiet()).0
  let output_wide = run_all(model, [Generated(ToggleExpanded)])
  let ir_from_source = run_all(source_wide, [OutputTab(false)])
  let tabs = run_command(model, UseTabs, quiet()).0
  let generated_tab = run_all(tabs, [OutputTab(true)])
  let source_tab = run_all(generated_tab, [Pane(Both)])
  @expect.expect_all(s => {
    s.expect(source_wide.pane, label="source").to_equal(SourceOnly)
    s.expect(restored.pane, label="restored").to_equal(Both)
    s.expect(output_wide.pane, label="output").to_equal(OutputOnly)
    s
    .expect(ir_from_source.pane, label="an output tab shows both again")
    .to_equal(Both)
    s
    .expect(tabs.settings.editor_layout, label="tabs")
    .to_equal(@settings.EditorLayout::Tabs)
    s
    .expect(storage_load(@settings.storage_key), label="saved")
    .to_equal("{\"theme\":\"system\",\"editorLayout\":\"tabs\"}")
    s.expect(generated_tab.pane, label="generated tab").to_equal(OutputOnly)
    s.expect(generated_tab.generated, label="generated").to_be_true()
    s.expect(source_tab.pane, label="source tab").to_equal(Both)
    // A worksheet's Results tab shows its results alone as tabs; side by side they stay beside the worksheet.
    let worksheet_results = run_all(tabs, [Layout(true), OutputTab(false)])
    s
    .expect(output_expanded(worksheet_results), label="worksheet results tab")
    .to_be_true()
    s
    .expect(
      output_expanded({
        ..worksheet_results,
        settings: { ..worksheet_results.settings, editor_layout: SideBySide, },
      }),
      label="side by side",
    )
    .to_be_false()
  })
}

///|
test "generated files open as their own tabs, close, and follow a new generation" {
  let restore = storage_test_environment("")
  defer restore()
  let output : Json = {
    "artifacts": [
      { "path": "src/A.elm", "content": "a" },
      { "path": "elm.json", "content": "{}" },
    ],
  }
  let tabs = run_command(settings_workspace(), UseTabs, quiet()).0
  let generated = follow_outputs(tabs, { ..tabs, output, })
  let both = run_all(generated, [Generated(Select("elm.json"))])
  let again = run_all(both, [Generated(Select("elm.json"))])
  let closed = run_all(both, [CloseOutput("elm.json")])
  let last = run_all(closed, [CloseOutput("src/A.elm")])
  let regenerated = follow_outputs(both, {
    ..both,
    output: { "artifacts": [{ "path": "src/A.elm", "content": "b" }] },
  })
  @expect.expect_all(s => {
    s
    .expect(generated.open_outputs, label="the selected file opens")
    .to_equal(["src/A.elm"])
    s
    .expect(both.open_outputs, label="opened")
    .to_equal(["src/A.elm", "elm.json"])
    s.expect(both.pane, label="shown").to_equal(OutputOnly)
    s.expect(again.open_outputs, label="once").to_equal(both.open_outputs)
    s.expect(closed.open_outputs, label="closed").to_equal(["src/A.elm"])
    s
    .expect(closed.generated_state.selected, label="the tab beside shows")
    .to_equal("src/A.elm")
    s.expect(last.pane, label="then the source").to_equal(Both)
    s
    .expect(regenerated.open_outputs, label="gone files close")
    .to_equal(["src/A.elm"])
  })
}
