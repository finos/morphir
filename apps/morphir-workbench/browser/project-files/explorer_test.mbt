///|
fn env(
  project : @project.Project,
  rules~ : @project.FileRules = elm_rules(),
  counts~ : Map[String, Int32] = Map([]),
  busy~ : Bool = false,
  samples~ : Array[(String, String)] = [],
  sample_reason~ : String = "",
) -> @project_files.Env {
  { project, rules, counts, busy, samples, sample_reason, }
}

///|
/// Runs `actions` from a fresh explorer, as the workbench does: each step sees the project the last one left.
fn run(
  project : @project.Project,
  actions : Array[@project_files.Action],
  rules~ : @project.FileRules = elm_rules(),
  counts~ : Map[String, Int32] = Map([]),
) -> (@project_files.State, @project.Project, Array[@project_files.Effect]) {
  let mut state = @project_files.State::new()
  let mut current = project
  let mut effects = []
  for action in actions {
    let (next, changed, done) = @project_files.apply(
      state,
      env(current, rules~, counts~),
      action,
    )
    state = next
    current = changed
    effects = done
  }
  (state, current, effects)
}

///|
fn key(name : String, shift~ : Bool = false) -> @project_files.Action {
  Key(
    @keys.Chord::from_event(
      name,
      ctrl=false,
      meta=false,
      shift~,
      alt=false,
      mac=false,
    ),
  )
}

///|
fn shop_with_util() -> @project.Project {
  shop().add_file(elm_rules(), "src/Shop/Orders/Util.elm") catch {
    _ => abort("util")
  }
}

///|
fn file_paths(project : @project.Project) -> Array[String] {
  project.files.map(f => f.path.to_string())
}

///|
test "a new file starts in its folder, opens and takes the editor focus" {
  let (state, project, effects) = run(shop(), [
    StartAdd(Some(In(path("src/Shop/Orders")))),
    Draft("Util.elm"),
    Commit,
  ])
  let (started, _, focus) = run(shop(), [StartAdd(None)])
  @expect.expect_all(s => {
    s
    .expect(file_paths(project), label="files")
    .to_equal(["src/Shop/Orders/Api.elm", "src/Shop/Orders/Util.elm"])
    s
    .expect(project.active.to_string(), label="active")
    .to_equal("src/Shop/Orders/Util.elm")
    s.expect(state.edit, label="idle").to_equal(Idle)
    s.expect(effects, label="focus").to_equal([FocusEditor])
    s
    .expect(started.edit, label="where the focus is")
    .to_equal(Creating(In(path("src/Shop/Orders")), ""))
    s.expect(focus, label="input").to_equal([FocusInput(0, 0)])
  })
}

///|
test "F2 renames inline with the name selected up to its extension" {
  let rename = run(shop_with_util(), [
    Open(path("src/Shop/Orders/Api.elm")),
    key("F2"),
  ])
  let (_, renamed, effects) = run(shop_with_util(), [
    Open(path("src/Shop/Orders/Api.elm")),
    key("F2"),
    Draft("Public.elm"),
    Commit,
  ])
  @expect.expect_all(s => {
    s
    .expect(rename.0.edit, label="draft")
    .to_equal(Renaming(File(path("src/Shop/Orders/Api.elm")), "Api.elm"))
    s.expect(rename.2, label="selection").to_equal([FocusInput(0, 3)])
    s
    .expect(file_paths(renamed), label="renamed")
    .to_equal(["src/Shop/Orders/Public.elm", "src/Shop/Orders/Util.elm"])
    s
    .expect(renamed.exposed.map(m => m.to_string()), label="exposure follows")
    .to_equal(["Public"])
    s
    .expect(effects, label="focus")
    .to_equal([FocusRow(File(path("src/Shop/Orders/Public.elm")))])
  })
}

///|
test "a rename refusal stays open with its message; an unchanged name cancels" {
  let (refused, kept, _) = run(shop_with_util(), [
    StartRename(File(path("src/Shop/Orders/Api.elm"))),
    Draft("Util.elm"),
    Commit,
  ])
  let (same, _, focus) = run(shop_with_util(), [
    StartRename(File(path("src/Shop/Orders/Api.elm"))),
    Commit,
  ])
  @expect.expect_all(s => {
    s.expect(refused.error, label="error").to_contain("A file with this path")
    s
    .expect(refused.edit, label="still open")
    .to_equal(Renaming(File(path("src/Shop/Orders/Api.elm")), "Util.elm"))
    s.expect(kept, label="kept").to_equal(shop_with_util())
    s.expect(same.edit, label="cancelled").to_equal(Idle)
    s
    .expect(focus, label="back to the row")
    .to_equal([FocusRow(File(path("src/Shop/Orders/Api.elm")))])
  })
}

///|
test "Delete asks inline; the last file is refused" {
  let (asking, _, focus) = run(shop_with_util(), [
    Open(path("src/Shop/Orders/Util.elm")),
    key("Delete"),
  ])
  let (_, deleted, after) = run(shop_with_util(), [
    Open(path("src/Shop/Orders/Util.elm")),
    key("Delete"),
    ConfirmDelete,
  ])
  let (last, kept, _) = run(shop(), [
    StartDelete(File(path("src/Shop/Orders/Api.elm"))),
    ConfirmDelete,
  ])
  @expect.expect_all(s => {
    s
    .expect(asking.edit, label="asking")
    .to_equal(Deleting(File(path("src/Shop/Orders/Util.elm"))))
    s.expect(focus, label="confirm focus").to_equal([FocusConfirm])
    s
    .expect(file_paths(deleted), label="deleted")
    .to_equal(["src/Shop/Orders/Api.elm"])
    s
    .expect(after, label="focus")
    .to_equal([FocusRow(File(path("src/Shop/Orders/Api.elm")))])
    s.expect(last.error, label="last").to_contain("at least one file")
    s.expect(last.edit, label="closed").to_equal(Idle)
    s.expect(kept, label="kept").to_equal(shop())
  })
}

///|
test "a folder renames and deletes with its files" {
  let project = shop_with_util().add_file(elm_rules(), "src/Shop/Main.elm") catch {
    _ => abort("main")
  }
  let (_, moved, _) = run(project, [
    StartRename(Dir(path("src/Shop/Orders"))),
    Draft("Sales"),
    Commit,
  ])
  let (_, deleted, _) = run(project, [
    StartDelete(Dir(path("src/Shop/Orders"))),
    Commit,
  ])
  @expect.expect_all(s => {
    s
    .expect(file_paths(moved), label="moved")
    .to_equal([
      "src/Shop/Sales/Api.elm", "src/Shop/Sales/Util.elm", "src/Shop/Main.elm",
    ])
    s
    .expect(file_paths(deleted), label="deleted")
    .to_equal(["src/Shop/Main.elm"])
  })
}

///|
test "package name and exposure edits update the project" {
  let (_, renamed, focus) = run(shop(), [
    StartNaming,
    Draft("Shop.Billing"),
    Commit,
  ])
  let (_, hidden, _) = run(shop(), [
    Exposed(path("src/Shop/Orders/Api.elm"), false),
  ])
  let (bad, kept, _) = run(shop(), [StartNaming, Draft("a b"), Commit])
  @expect.expect_all(s => {
    s.expect(renamed.name.to_string(), label="name").to_equal("Shop.Billing")
    s.expect(focus, label="focus").to_equal([FocusName])
    s.expect(hidden.exposed, label="hidden").to_be_empty()
    s.expect(kept.name.to_string(), label="kept").to_equal("Shop.Orders")
    s.expect(bad.error, label="error").not().to_be_empty()
    s.expect(bad.edit, label="open").to_equal(Naming("a b"))
  })
}

///|
test "a stale path is refused without a crash" {
  let (opened, project, _) = run(shop(), [Open(path("src/Gone.elm"))])
  let (renaming, _, _) = run(shop(), [StartRename(Dir(path("src/Gone")))])
  let (answered, kept, effects) = run(shop(), [ConfirmDelete])
  @expect.expect_all(s => {
    s
    .expect(opened.error, label="stale open")
    .to_contain("No file has this path")
    s.expect(project, label="project kept").to_equal(shop())
    s
    .expect(renaming.error, label="stale folder")
    .to_contain("No folder has this path")
    s
    .expect(answered, label="answer without question")
    .to_equal(@project_files.State::new())
    s.expect(kept, label="unchanged").to_equal(shop())
    s.expect(effects, label="no effects").to_be_empty()
  })
}

///|
test "a one-file language refuses New file with its reason" {
  let rules : @project.FileRules = { ..elm_rules(), layout: OneFile, }
  let (state, project, _) = run(shop(), [StartAdd(None)], rules~)
  let entries = @project_files.menu_entries(
    @project_files.State::new(),
    env(shop(), rules~),
    OnRoot,
  )
  @expect.expect_all(s => {
    s.expect(state.error, label="reason").to_contain("morphir-ukvn.5.22.14")
    s.expect(state.edit, label="idle").to_equal(Idle)
    s.expect(project, label="project").to_equal(shop())
    s
    .expect(entries[0], label="menu entry")
    .to_satisfy(entry => {
      entry.command == NewFile &&
      !entry.enabled &&
      entry.reason.contains("morphir-ukvn.5.22.14")
    })
    s
    .expect(entries.map(e => e.command), label="no package entry")
    .to_contain_none_of([RenamePackage])
  })
}

///|
test "arrow keys move the focus and open folders; letters jump" {
  let project = shop_with_util()
  let (down, _, moved) = run(project, [
    Focus(Dir(path("src/Shop/Orders"))),
    key("ArrowDown"),
  ])
  let (closed, _, _) = run(project, [
    Focus(Dir(path("src/Shop/Orders"))),
    key("ArrowLeft"),
  ])
  let (_, opened, left) = run(project, [
    Focus(File(path("src/Shop/Orders/Util.elm"))),
    key("Enter"),
  ])
  let (_, previewed, stay) = run(project, [
    Focus(File(path("src/Shop/Orders/Util.elm"))),
    key(" "),
  ])
  let (jumped, _, _) = run(project, [
    Focus(Dir(path("src/Shop/Orders"))),
    key("u"),
  ])
  @expect.expect_all(s => {
    s
    .expect(down.focused, label="down")
    .to_equal(Some(File(path("src/Shop/Orders/Api.elm"))))
    s
    .expect(moved, label="focus effect")
    .to_equal([FocusRow(File(path("src/Shop/Orders/Api.elm")))])
    s
    .expect(closed.collapsed.map(p => p.to_string()), label="left closes")
    .to_equal(["src/Shop/Orders"])
    s
    .expect(opened.active.to_string(), label="enter opens")
    .to_equal("src/Shop/Orders/Util.elm")
    s.expect(left, label="enter leaves").to_equal([FocusEditor])
    s
    .expect(previewed.active.to_string(), label="space opens")
    .to_equal("src/Shop/Orders/Util.elm")
    s
    .expect(stay, label="space stays")
    .to_equal([FocusRow(File(path("src/Shop/Orders/Util.elm")))])
    s
    .expect(jumped.focused, label="typeahead")
    .to_equal(Some(File(path("src/Shop/Orders/Util.elm"))))
  })
}

///|
test "Collapse folders keeps the focus on a visible row" {
  let project = shop().add_file(elm_rules(), "src/Main.elm") catch {
    _ => abort("main")
  }
  let (state, _, _) = run(project, [
    Focus(File(path("src/Shop/Orders/Api.elm"))),
    CollapseAll,
  ])
  @expect.expect_all(s => {
    s
    .expect(state.collapsed.map(p => p.to_string()), label="collapsed")
    .to_equal(["src", "src/Shop/Orders"])
    s.expect(state.focused, label="focus").to_equal(Some(Dir(path("src"))))
  })
}

///|
test "the context menu opens at the pointer, moves with arrows and runs entries" {
  let project = shop_with_util()
  let target = @project_files.OnItem(File(path("src/Shop/Orders/Util.elm")))
  let (opened, _, focus) = run(project, [OpenMenu(target, 100, 120, 1280, 800)])
  let (moved, _, moved_focus) = run(project, [
    OpenMenu(target, 100, 120, 1280, 800),
    MenuKey(@keys.Chord::plain("ArrowUp")),
  ])
  let (renaming, _, rename_focus) = run(project, [
    OpenMenu(target, 100, 120, 1280, 800),
    MenuKey(@keys.Chord::plain("ArrowDown")),
    MenuKey(@keys.Chord::plain("ArrowDown")),
    MenuKey(@keys.Chord::plain("Enter")),
  ])
  let (closed, _, close_focus) = run(project, [
    OpenMenu(target, 100, 120, 1280, 800),
    MenuKey(@keys.Chord::plain("Escape")),
  ])
  let (here, _, _) = run(project, [
    Open(path("src/Shop/Orders/Util.elm")),
    OpenMenuHere(40, 60, 1280, 800),
  ])
  let (_, _, copied) = run(project, [
    OpenMenu(target, 100, 120, 1280, 800),
    Choose(CopyPath),
  ])
  @expect.expect_all(s => {
    s
    .expect(opened.menu, label="menu")
    .to_equal(Some({ target, left: 100, top: 120, index: 0, }))
    s.expect(focus, label="first entry").to_equal([FocusMenu(0)])
    s
    .expect(moved.menu.map(m => m.index), label="wraps")
    .to_equal(
      Some(
        @project_files.menu_entries(moved, env(project), target).length() - 1,
      ),
    )
    s.expect(moved_focus.length(), label="one focus").to_equal(1)
    s
    .expect(renaming.edit, label="rename entry")
    .to_equal(Renaming(File(path("src/Shop/Orders/Util.elm")), "Util.elm"))
    s.expect(renaming.menu, label="closed").to_be_none()
    s.expect(rename_focus, label="input").to_equal([FocusInput(0, 4)])
    s
    .expect(here.menu.map(m => m.target), label="menu of the focused row")
    .to_equal(Some(target))
    s.expect(closed.menu, label="escape").to_be_none()
    s
    .expect(close_focus, label="back to row")
    .to_equal([FocusRow(File(path("src/Shop/Orders/Util.elm")))])
    s
    .expect(copied, label="copy")
    .to_equal([
      FocusRow(File(path("src/Shop/Orders/Util.elm"))),
      Copy("src/Shop/Orders/Util.elm"),
    ])
  })
}

///|
test "file menus offer exposure and problems only where they apply" {
  let project = shop_with_util()
  let counts = Map([("src/Shop/Orders/Api.elm", 2)])
  let commands = fn(path_text : String) {
    @project_files.menu_entries(
      @project_files.State::new(),
      env(project, counts~),
      OnItem(File(path(path_text))),
    ).map(e => e.command)
  }
  let busy = @project_files.menu_entries(
    @project_files.State::new(),
    env(project, busy=true),
    OnItem(File(path("src/Shop/Orders/Api.elm"))),
  )
  let (state, _, _) = run(project, [
    OpenMenu(OnItem(File(path("src/Shop/Orders/Api.elm"))), 0, 0, 800, 600),
    Choose(RenameItem),
  ])
  @expect.expect_all(s => {
    s
    .expect(commands("src/Shop/Orders/Api.elm"), label="exposed with problems")
    .to_equal([
      OpenItem,
      NewFile,
      RenameItem,
      DeleteItem,
      CopyPath,
      Unexpose,
      ShowProblems,
    ])
    s
    .expect(commands("src/Shop/Orders/Util.elm"), label="hidden, clean")
    .to_equal([OpenItem, NewFile, RenameItem, DeleteItem, CopyPath, Expose])
    s
    .expect(
      busy.filter(e => !e.enabled).map(e => e.command),
      label="busy disables edits",
    )
    .to_equal([NewFile, RenameItem, DeleteItem])
    s
    .expect(state.edit, label="enabled entry runs")
    .to_satisfy(edit => edit is Renaming(_, _))
  })
}

///|
test "menus stay inside the viewport" {
  @expect.expect_all(s => {
    s
    .expect(@project_files.place_menu(10, 10, 200, 1000, 800), label="fits")
    .to_equal((10, 10))
    s
    .expect(@project_files.place_menu(990, 10, 200, 1000, 800), label="right")
    .to_equal((1000 - @project_files.menu_width - 4, 10))
    s
    .expect(@project_files.place_menu(10, 700, 200, 1000, 800), label="flips")
    .to_equal((10, 500))
    s
    .expect(
      @project_files.place_menu(10, 150, 300, 1000, 320),
      label="squeezed",
    )
    .to_equal((10, 16))
  })
}

///|
/// Property: a menu that fits the viewport is placed entirely inside it, wherever the pointer is.
test "a menu that fits is always inside the viewport" {
  @expect.for_all((point : (UInt32, UInt32)) => {
    let width = 1000
    let height = 700
    let menu = 300
    let x = (point.0 % 1200).reinterpret_as_int()
    let y = (point.1 % 900).reinterpret_as_int()
    let (left, top) = @project_files.place_menu(x, y, menu, width, height)
    @expect.expect(
      left >= 4 && left + @project_files.menu_width <= width - 4,
      label="x",
    ).to_be_true()
    @expect.expect(top >= 4 && top + menu <= height - 4, label="y").to_be_true()
  })
}

///|
/// Property: Cancel always returns to Idle without changing the project.
test "cancel never changes the project" {
  @expect.for_all((step : UInt32) => {
    let start = match step % 4 {
      0 => @project_files.Action::StartAdd(None)
      1 => StartRename(File(path("src/Shop/Orders/Api.elm")))
      2 => StartDelete(File(path("src/Shop/Orders/Api.elm")))
      _ => StartNaming
    }
    let (state, project, _) = run(shop(), [start, Draft("src/X.elm"), Cancel])
    @expect.expect_all(s => {
      s.expect(project, label="project").to_equal(shop())
      s.expect(state.edit, label="idle").to_equal(Idle)
    })
  })
}

///|
/// Property: a key on a row never changes which files the project has.
test "tree keys never change the files" {
  @expect.for_all((keys : Array[UInt32]) => {
    let names = [
      "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "Enter",
      " ", "u", "a",
    ]
    let actions = keys.map(k => {
      key(
        names[(k % names.length().reinterpret_as_uint()).reinterpret_as_int()],
      )
    })
    let (_, project, _) = run(shop_with_util(), actions)
    @expect.expect(file_paths(project), label="files").to_equal(
      file_paths(shop_with_util()),
    )
  })
}

///|
test "edits wait while an operation runs, from keys as from menus" {
  let busy_env = env(shop_with_util(), busy=true)
  let (renaming, _, _) = @project_files.apply(
    {
      ..@project_files.State::new(),
      focused: Some(File(path("src/Shop/Orders/Util.elm"))),
    },
    busy_env,
    key("F2"),
  )
  let (adding, _, _) = @project_files.apply(
    @project_files.State::new(),
    busy_env,
    StartAdd(None),
  )
  @expect.expect_all(s => {
    s.expect(renaming.edit, label="no rename").to_equal(Idle)
    s.expect(renaming.error, label="reason").to_contain("running operation")
    s.expect(adding.edit, label="no new file").to_equal(Idle)
  })
}

///|
test "the project menu opens the command palette" {
  let (state, _, effects) = run(shop(), [
    OpenMenu(OnRoot, 10, 10, 800, 600),
    Choose(CommandPalette),
  ])
  let entry = @project_files.menu_entries(
    @project_files.State::new(),
    env(shop()),
    OnRoot,
  ).last()
  @expect.expect_all(s => {
    s.expect(effects, label="effect").to_equal([ShowPalette])
    s.expect(state.menu, label="closed").to_be_none()
    s
    .expect(entry.map(e => (e.label, e.shortcut)), label="entry")
    .to_equal(Some(("Command palette…", Some(ShowCommands))))
  })
}

///|
test "the project menu lists the samples in one section and opens them" {
  let samples = [
    ("builtin:scheme", "Pricing & arithmetic"),
    ("examples-tutorial", "Rentals tutorial"),
  ]
  let entries = @project_files.menu_entries(
    @project_files.State::new(),
    env(shop(), samples~),
    OnRoot,
  )
  let busy = @project_files.menu_entries(
    @project_files.State::new(),
    env(
      shop(),
      samples~,
      sample_reason="Wait for the running operation to finish",
    ),
    OnRoot,
  )
  let plain = @project_files.menu_entries(
    @project_files.State::new(),
    env(shop()),
    OnRoot,
  )
  let with_samples = env(shop(), samples~)
  let (opened, _, _) = @project_files.apply(
    @project_files.State::new(),
    with_samples,
    OpenMenu(OnRoot, 10, 10, 800, 600),
  )
  let (_, _, effects) = @project_files.apply(
    opened,
    with_samples,
    Choose(OpenSample("examples-tutorial")),
  )
  let in_section = entries.filter(e => {
    e.section == @project_files.sample_section
  })
  @expect.expect_all(s => {
    s
    .expect(in_section.map(e => (e.command, e.label)), label="entries")
    .to_equal([
      (OpenSample("builtin:scheme"), "Pricing & arithmetic"),
      (OpenSample("examples-tutorial"), "Rentals tutorial"),
    ])
    s
    .expect(in_section.map(e => e.group_start), label="one group")
    .to_equal([true, false])
    s
    .expect(
      entries
      .mapi((i, _) => @project_files.starts_section(entries, i))
      .filter(starts => starts)
      .length(),
      label="one heading",
    )
    .to_equal(1)
    s
    .expect(
      @project_files.menu_height(entries) - @project_files.menu_height(plain),
      label="two items, a separator and a heading",
    )
    .to_equal(2 * 28 + 9 + 24)
    s
    .expect(
      busy.filter(e => e.section != "").all(e => !e.enabled),
      label="busy",
    )
    .to_be_true()
    s.expect(effects, label="opens").to_equal([LoadSample("examples-tutorial")])
  })
}

///|
test "a filter shows matching files inside open folders and keeps the project" {
  let env = env(shop_with_util())
  let collapsed = {
    ..@project_files.State::new(),
    collapsed: env.project.files.map(f => f.path),
  }
  let (filtered, project, effects) = @project_files.apply(
    collapsed,
    env,
    Filter("API"),
  )
  let paths = filtered
    .rows(env, Map([]))
    .map(row => row.item.path().to_string())
  @expect.expect_all(s => {
    s.expect(project).to_equal(env.project)
    s.expect(effects).to_equal([])
    s
    .expect(
      paths
      .iter()
      .all(p => !p.has_suffix(".elm") || p.to_lower().contains("api")),
    )
    .to_equal(true)
    s.expect(paths.iter().any(p => p.has_suffix("Api.elm"))).to_equal(true)
    s
    .expect(
      @project_files.apply(filtered, env, Filter("")).0
      .rows(env, Map([]))
      .length() >
      0,
    )
    .to_equal(true)
  })
}
