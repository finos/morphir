///|
fn ready_model(language~ : String = "elm") -> Model {
  { ..scope_model(), catalog: catalog_fixture(), language, available: true, }
}

///|
fn ignore_cmds() -> @cmd.Emit[Msg] {
  @cmd.Emit(fn(_) { @cmd.none })
}

///|
/// Runs `msgs` through `update`, as the page would one after another.
fn send(model : Model, msgs : Array[Msg]) -> Model {
  msgs.fold(init=model, (current, msg) => update(current, msg, ignore_cmds()).0)
}

///|
fn enter() -> Msg {
  Palette(Key(@keys.Chord::plain("Enter")))
}

///|
/// An Elm project with `src/Workbench/Main.elm` and `src/Workbench/Extra/Util.elm`.
fn two_folders(model : Model) -> Model {
  send(model, [
    Files(StartAdd(Some(Root))),
    Files(Draft("src/Workbench/Extra/Util.elm")),
    Files(Commit),
  ])
}

///|
test "the palette opens from a shortcut and runs Compile" {
  let opened = send(ready_model(), [RunCommand(ShowCommands)])
  let ran = send(opened, [Palette(Query(">compile")), enter()])
  @expect.expect_all(s => {
    s.expect(opened.palette.open, label="open").to_be_true()
    s.expect(opened.palette.query, label="commands").to_equal(">")
    s.expect(ran.palette.open, label="closed").to_be_false()
    s.expect(ran.busy, label="compiling").to_be_true()
    s.expect(ran.request_id, label="execution").to_equal(opened.request_id + 1)
    s.expect(ran.palette.recent, label="recent").to_equal([Compile])
  })
}

///|
test "quick open shows the file in Try Morphir and opens its folders" {
  let model = two_folders(ready_model())
  let hidden = send({ ..model, explorer: true, try_collapsed: true, }, [
    Files(Toggle(literal_path("src/Workbench/Extra"))),
    Files(Open(literal_path("src/Workbench/Main.elm"))),
  ])
  let opened = send(hidden, [
    RunCommand(GoToFile),
    Palette(Query("util")),
    enter(),
  ])
  @expect.expect_all(s => {
    s
    .expect(hidden.files_edit.collapsed.map(p => p.to_string()), label="closed")
    .to_equal(["src/Workbench/Extra"])
    s
    .expect(active_project(opened).active.to_string(), label="opened")
    .to_equal("src/Workbench/Extra/Util.elm")
    s.expect(opened.explorer, label="Try Morphir").to_be_false()
    s.expect(opened.try_collapsed, label="sidebar open").to_be_false()
    s.expect(opened.files_edit.collapsed, label="revealed").to_be_empty()
    s.expect(opened.palette.open, label="closed").to_be_false()
  })
}

///|
test "a command that cannot run now does nothing" {
  let busy = { ..ready_model(), busy: true, request_id: 3, }
  let compiled = send(busy, [RunCommand(Compile)])
  let moonbit = ready_model(language="moonbit")
  let added = send(moonbit, [RunCommand(NewFile)])
  let worksheet = { ..ready_model(), worksheet: true, }
  let (from_palette, _) = run_command(
    worksheet,
    Compile,
    ignore_cmds(),
    from_palette=true,
  )
  @expect.expect_all(s => {
    s.expect(compiled.request_id, label="busy").to_equal(3)
    s.expect(added.files_edit.edit, label="one-file language").to_equal(Idle)
    s.expect(from_palette.busy, label="Compile in a worksheet").to_be_false()
    s
    .expect(
      palette_commands(moonbit)
      .iter()
      .find_first(c => c.id == NewFile)
      .map(c => c.reason),
      label="reason",
    )
    .unwrap_some()
    .to_contain("morphir-ukvn.5.22.14")
  })
}

///|
test "a second list in the palette switches the language" {
  let asked = send(ready_model(), [RunCommand(SwitchLanguage)])
  let switched = send(asked, [Palette(Query("moon")), enter()])
  @expect.expect_all(s => {
    s
    .expect(asked.palette.choosing.map(c => c.0), label="asking")
    .to_equal(Some(SwitchLanguage))
    s
    .expect(
      palette_choices(asked).map(c => (c.value, c.detail)),
      label="choices",
    )
    .to_equal([("elm", "current"), ("moonbit", ""), ("scheme", "")])
    s.expect(switched.language, label="language").to_equal("moonbit")
    s.expect(switched.palette.open, label="closed").to_be_false()
  })
}

///|
test "file commands act on the open file and show it in the explorer" {
  let model = two_folders(ready_model())
  let renaming = send({ ..model, explorer: true, }, [RunCommand(RenameFile)])
  let deleting = send(model, [RunCommand(DeleteFile)])
  let hidden = send(model, [RunCommand(ToggleExposed)])
  @expect.expect_all(s => {
    s
    .expect(renaming.files_edit.edit, label="rename")
    .to_equal(
      Renaming(File(literal_path("src/Workbench/Extra/Util.elm")), "Util.elm"),
    )
    s.expect(renaming.explorer, label="shown").to_be_false()
    s
    .expect(deleting.files_edit.edit, label="delete")
    .to_equal(Deleting(File(literal_path("src/Workbench/Extra/Util.elm"))))
    s
    .expect(
      hidden.language_projects.get("elm").map(p => p.exposed.length()),
      label="exposed",
    )
    .to_equal(Some(2))
  })
}

///|
test "menu entries reach the workbench: problems, reset and the file set" {
  let model = two_folders(ready_model())
  let counted = {
    ..model,
    problem_counts: Map([("src/Workbench/Main.elm", 2)]),
  }
  let main_row = @project_files.OnItem(
    File(literal_path("src/Workbench/Main.elm")),
  )
  let problems = send(counted, [
    Files(OpenMenu(main_row, 10, 10, 800, 600)),
    Files(Choose(ShowProblems)),
  ])
  let reset = send(counted, [
    Files(OpenMenu(OnRoot, 10, 10, 800, 600)),
    Files(Choose(ResetProject)),
  ])
  let opened = send(counted, [
    Files(Open(literal_path("src/Workbench/Extra/Util.elm"))),
  ])
  let deleted = send(counted, [
    Files(StartDelete(File(literal_path("src/Workbench/Extra/Util.elm")))),
    Files(ConfirmDelete),
  ])
  @expect.expect_all(s => {
    s
    .expect(
      problems.panel.tab == @bottom_panel.Diagnostics,
      label="diagnostics",
    )
    .to_be_true()
    s
    .expect(problems.panel.size == @bottom_panel.Normal, label="panel open")
    .to_be_true()
    s.expect(problems.files_edit.menu, label="menu closed").to_be_none()
    s.expect(reset.reset_asking, label="reset asks").to_be_true()
    s
    .expect(opened.problem_counts.length(), label="open keeps counts")
    .to_equal(1)
    s
    .expect(deleted.problem_counts.length(), label="delete clears counts")
    .to_equal(0)
  })
}

///|
test "the compile chord waits for the palette and runs a worksheet" {
  let open = send(ready_model(), [RunCommand(ShowCommands)])
  let behind = send(open, [RunCommand(Compile)])
  let worksheet = send({ ..ready_model(), worksheet: true, }, [
    RunCommand(Compile),
  ])
  let from_menu = send(ready_model(), [
    Files(OpenMenu(OnRoot, 10, 10, 800, 600)),
    Files(Choose(CommandPalette)),
  ])
  @expect.expect_all(s => {
    s.expect(behind.busy, label="not behind the palette").to_be_false()
    s.expect(behind.palette.open, label="palette stays").to_be_true()
    s.expect(worksheet.busy, label="worksheet runs").to_be_true()
    s.expect(from_menu.palette.open, label="menu opens palette").to_be_true()
    s.expect(from_menu.palette.query, label="commands").to_equal(">")
  })
}

///|
test "one list of samples feeds the palette and the project menu" {
  let scheme = ready_model(language="scheme")
  let elm = { ..ready_model(), samples: [("tiny", "Tiny")], }
  let worksheet = { ..ready_model(language="scheme"), worksheet: true, }
  let connected = { ..ready_model(), connected: true, }
  let builtins = [
    "Pricing & arithmetic", "Elm constant", "MoonBit Boolean", "MoonBit library",
    "MoonBit Boolean library", "MoonBit String library",
  ]
  let titles = fn(model : Model) {
    palette_commands(model).filter(c => c.id is LoadSample(_)).map(c => c.title)
  }
  @expect.expect_all(s => {
    s
    .expect(sample_entries(scheme).map(e => e.1), label="every language")
    .to_equal(builtins)
    s
    .expect(sample_entries(elm).map(e => e.1), label="Elm adds its corpus")
    .to_equal(builtins + ["Tiny"])
    s
    .expect(sample_entries(worksheet).map(e => e.1), label="worksheet")
    .to_equal(["Pricing & arithmetic"])
    s
    .expect(titles(elm), label="palette entries")
    .to_equal(builtins.map(b => "Open sample: " + b) + ["Open sample: Tiny"])
    s
    .expect(explorer_env(elm).samples, label="menu reads the same list")
    .to_equal(sample_entries(elm))
    s
    .expect(
      palette_commands(connected)
      .filter(c => c.id is LoadSample(_))
      .all(c => !c.enabled && c.reason.contains("local mode")),
      label="connected",
    )
    .to_be_true()
  })
}

///|
test "samples open from the palette, the worksheet and the project menu" {
  let elm_constant = send(ready_model(language="moonbit"), [
    RunCommand(LoadSample("builtin:scheme-elm")),
  ])
  let edited = send({ ..ready_model(language="scheme"), worksheet: true, }, [
    Source("(+ 1 1)"),
  ])
  let pricing = send(edited, [RunCommand(LoadSample("builtin:scheme"))])
  let from_menu = send(ready_model(), [
    Files(OpenMenu(OnRoot, 10, 10, 800, 600)),
    Files(Choose(OpenSample("builtin:moonbit-library"))),
  ])
  let busy = send({ ..ready_model(language="scheme"), busy: true, }, [
    RunCommand(LoadSample("builtin:moonbit")),
  ])
  @expect.expect_all(s => {
    s
    .expect(elm_constant.language, label="Elm constant is Scheme")
    .to_equal("scheme")
    s.expect(elm_constant.target, label="targeting Elm").to_equal("elm")
    s
    .expect(active_text(elm_constant), label="text")
    .to_contain("(define answer 42)")
    s
    .expect(pricing.worksheet_source, label="worksheet example")
    .to_equal(worksheet_example)
    s.expect(from_menu.language, label="menu").to_equal("moonbit")
    s.expect(from_menu.files_edit.menu, label="menu closed").to_be_none()
    s.expect(busy.language, label="busy refuses").to_equal("scheme")
  })
}

///|
test "a built-in example chosen after an Elm sample drops that sample's reply" {
  let model = { ..ready_model(), samples: [("tiny", "Tiny")], }
  let asked = send(model, [Sample("tiny")])
  let builtin = send(asked, [Sample("builtin:moonbit")])
  let late = send(builtin, [
    SampleLoaded(asked.sample_request, "tiny", sample_reply()),
  ])
  @expect.expect_all(s => {
    s
    .expect(builtin.sample_request, label="new request")
    .to_equal(asked.sample_request + 1)
    s
    .expect(late.language_projects.get("elm"), label="Elm project kept")
    .to_equal(builtin.language_projects.get("elm"))
    s.expect(late.language, label="still MoonBit").to_equal("moonbit")
  })
}
