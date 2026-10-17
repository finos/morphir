///|
fn path(text : String) -> @ids.SourcePath {
  @ids.SourcePath::parse(text) catch {
    _ => abort(text)
  }
}

///|
let files : Array[@ids.SourcePath] = [
  path("src/Shop/Orders/Api.elm"),
  path("src/Shop/Main.elm"),
  path("src/Api/Main.elm"),
]

///|
let commands : Array[@palette.Command] = [
  {
    id: Compile,
    title: "Compile",
    category: "Build",
    enabled: true,
    reason: "",
  },
  {
    id: NewFile,
    title: "New file…",
    category: "File",
    enabled: false,
    reason: "This language holds one file",
  },
  {
    id: TogglePanel,
    title: "Toggle panel",
    category: "View",
    enabled: true,
    reason: "",
  },
  {
    id: SwitchLanguage,
    title: "Switch language…",
    category: "Project",
    enabled: true,
    reason: "",
  },
]

///|
let choices : Array[@palette.Choice] = [
  { value: "elm", label: "Elm", detail: "current", },
  { value: "moonbit", label: "MoonBit", detail: "", },
  { value: "scheme", label: "Scheme", detail: "", },
]

///|
fn shown(state : @palette.State) -> Array[@palette.Entry] {
  @palette.entries(state, files~, commands~, choices~, mac=false)
}

///|
fn labels(state : @palette.State) -> Array[String] {
  shown(state).map(entry => entry.label)
}

///|
/// Runs `actions` from a closed palette, each against the entries the palette shows at that moment.
fn run(
  actions : Array[@palette.Action],
  start~ : @palette.State = @palette.State::new(),
) -> (@palette.State, @palette.Outcome) {
  let mut state = start
  let mut outcome = @palette.Outcome::Stay
  for action in actions {
    let (next, done) = state.update(action, shown(state))
    state = next
    outcome = done
  }
  (state, outcome)
}

///|
test "no prefix lists files; > lists commands" {
  let (files_mode, _) = run([Show("")])
  let (commands_mode, _) = run([Show(""), Query(">")])
  @expect.expect_all(s => {
    s.expect(files_mode.mode(), label="files").to_equal(Files)
    s
    .expect(labels(files_mode), label="files by path")
    .to_equal(["Main.elm", "Main.elm", "Api.elm"])
    s
    .expect(shown(files_mode).map(e => e.detail), label="folders")
    .to_equal(["src/Api", "src/Shop", "src/Shop/Orders"])
    s.expect(commands_mode.mode(), label="commands").to_equal(Commands)
    s
    .expect(labels(commands_mode), label="registry order")
    .to_equal(["Compile", "New file…", "Toggle panel", "Switch language…"])
  })
}

///|
test "file queries prefer the file name and mark matches in name and folder" {
  let (state, _) = run([Show(""), Query("api")])
  let (path_query, _) = run([Show(""), Query("ordersapi")])
  let entries = shown(state)
  @expect.expect_all(s => {
    s
    .expect(entries.map(e => e.label + " " + e.detail), label="order")
    .to_equal(["Api.elm src/Shop/Orders", "Main.elm src/Api"])
    s.expect(entries[0].label_marks, label="name marks").to_equal([0, 1, 2])
    s.expect(entries[1].detail_marks, label="folder marks").to_equal([4, 5, 6])
    s
    .expect(shown(path_query).map(e => e.label), label="across folders")
    .to_equal(["Api.elm"])
    s
    .expect(shown(path_query)[0].label_marks, label="split marks")
    .to_equal([0, 1, 2])
  })
}

///|
test "recent commands come first and show their shortcut" {
  let (ran, outcome) = run([
    Show(">"),
    Query(">toggle"),
    Key(@keys.Chord::plain("Enter")),
  ])
  let (again, _) = run([Show(">")], start=ran)
  let entries = shown(again)
  @expect.expect_all(s => {
    s.expect(outcome, label="ran").to_equal(Run(TogglePanel))
    s.expect(ran.open, label="closed").to_be_false()
    s.expect(ran.recent, label="recent").to_equal([TogglePanel])
    s
    .expect(entries.map(e => e.label), label="recent first")
    .to_equal(["Toggle panel", "Compile", "New file…", "Switch language…"])
    s.expect(entries[0].recent, label="marked").to_be_true()
    s.expect(entries[1].hint, label="shortcut").to_equal("Ctrl+Enter")
    s.expect(entries[1].keys, label="aria").to_equal("Control+Enter")
  })
}

///|
test "a disabled command stays listed with its reason and does not run" {
  let (state, outcome) = run([Show(">new"), Key(@keys.Chord::plain("Enter"))])
  let entry = shown(state)[0]
  @expect.expect_all(s => {
    s.expect(outcome, label="nothing").to_equal(Stay)
    s.expect(state.open, label="open").to_be_true()
    s.expect(entry.enabled, label="disabled").to_be_false()
    s
    .expect(entry.detail, label="reason")
    .to_equal("This language holds one file")
  })
}

///|
test "arrows wrap, Escape closes and a second list answers its command" {
  let (up, _) = run([Show(">"), Key(@keys.Chord::plain("ArrowUp"))])
  let (down, _) = run([
    Show(">"),
    Key(@keys.Chord::plain("ArrowUp")),
    Key(@keys.Chord::plain("ArrowDown")),
  ])
  let (closed, escape) = run([Show(""), Key(@keys.Chord::plain("Escape"))])
  let (asked, chose) = run([
    Ask(SwitchLanguage, "Switch language"),
    Query("moon"),
    Key(@keys.Chord::plain("Enter")),
  ])
  let (opened, file) = run([Show(""), Query("ordersapi"), Pick(0)])
  @expect.expect_all(s => {
    s.expect(up.index, label="wraps up").to_equal(3)
    s.expect(down.index, label="wraps down").to_equal(0)
    s.expect(escape, label="escape").to_equal(Closed)
    s.expect(closed.open, label="closed").to_be_false()
    s.expect(chose, label="chose").to_equal(Chose(SwitchLanguage, "moonbit"))
    s.expect(asked.choosing, label="done").to_be_none()
    s
    .expect(file, label="file")
    .to_equal(Opened(path("src/Shop/Orders/Api.elm")))
    s.expect(opened.query, label="cleared").to_equal("")
  })
}

///|
/// Property: whatever keys arrive, the index stays inside the list.
test "the selection stays inside the list" {
  @expect.for_all((keys : Array[UInt32]) => {
    let names = ["ArrowUp", "ArrowDown", "PageUp", "PageDown"]
    let (state, _) = run(
      [Show(">")] +
      keys.map(k => {
        @palette.Action::Key(
          @keys.Chord::plain(names[(k % 4).reinterpret_as_int()]),
        )
      }),
    )
    @expect.expect(state.index, label="index").to_be_between(
      0,
      commands.length() - 1,
    )
  })
}
