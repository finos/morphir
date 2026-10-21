///|
fn new_project(
  name : String,
  language~ : String? = None,
) -> @workspace.NewProject raise {
  {
    name: @ids.SourcePackageName::parse(name),
    language: language.map(@ids.LanguageId::parse),
    profile: None,
    source_directory: "src",
  }
}

///|
test "workspace initialization creates a virtual_tree root or a real root project" {
  let empty = @workspace.Tree::from_files(Map([]))
  let virtual_tree = @workspace.init_workspace(empty).apply(empty)
  assert_eq(virtual_tree.files.length(), 1)
  assert_eq(@workspace.discover(virtual_tree).projects.length(), 0)
  for language in ["scheme", "elm", "moonbit"] {
    let root = @workspace.init_workspace(
      empty,
      project=Some(new_project("Root", language=Some(language))),
    ).apply(empty)
    let workspace = @workspace.discover(root)
    assert_eq(workspace.projects.length(), 1)
    assert_eq(workspace.projects[0].name, "Root")
    assert_eq(
      workspace.projects[0].document.text("frontend.language", ""),
      language,
    )
    assert_eq(root.files.length(), 2)
    assert_true(root.directories.contains("src"))
  }
}

///|
test "add project preserves literal members and comments and inherits the workspace language" {
  let config = "# Workspace\n[workspace] # keep\nmembers = [ 'one' ] # members\n\n[frontend]\nlanguage = 'elm' # inherited\n"
  let tree = tree([
    ("morphir.toml", config),
    ("one/morphir.toml", "[project]\nname='One'\n"),
  ])
  let edit = @workspace.add_project(
    @workspace.discover(tree),
    tree,
    @workspace.ProjectPath::parse("packages/two"),
    new_project("Two"),
  )
  assert_eq(tree.files["morphir.toml"], config)
  let result = edit.apply(tree)
  let config = result.files["morphir.toml"]
  assert_true(config.has_prefix("# Workspace\n[workspace] # keep\n"))
  assert_true(
    config.has_suffix(
      " # members\n\n[frontend]\nlanguage = 'elm' # inherited\n",
    ),
  )
  let workspace = @workspace.discover(result)
  assert_eq(workspace.projects.map(p => p.name), ["One", "Two"])
  assert_eq(workspace.projects[1].document.text("frontend.language", ""), "elm")
  assert_eq(workspace.projects[1].document.strings("project.exposed_modules"), [
    "Main",
  ])
}

///|
test "glob members need no config edit and same-language projects have different paths" {
  let config = "[workspace]\nmembers = ['packages/*'] # keep\n"
  let initial = tree([("morphir.toml", config)])
  let one = @workspace.add_project(
    @workspace.discover(initial),
    initial,
    @workspace.ProjectPath::parse("packages/one"),
    new_project("Same"),
  ).apply(initial)
  let edit = @workspace.add_project(
    @workspace.discover(one),
    one,
    @workspace.ProjectPath::parse("packages/two"),
    new_project("Same"),
  )
  assert_true(!edit.writes.contains("morphir.toml"))
  assert_eq(edit.warnings.length(), 1)
  let result = edit.apply(one)
  assert_eq(result.files["morphir.toml"], config)
  assert_eq(@workspace.discover(result).projects.map(p => p.root), [
    "packages/one", "packages/two",
  ])
}

///|
test "add a root project keeps the virtual_tree workspace config and hidden anchor" {
  let config = "# Root\n[workspace]\nmembers = []\n\n[frontend]\nlanguage = 'scheme' # language\n"
  let initial = tree([(".morphir/morphir.toml", config)])
  let result = @workspace.add_project(
    @workspace.discover(initial),
    initial,
    @workspace.ProjectPath::parse("."),
    new_project("Root"),
  ).apply(initial)
  assert_true(!result.files.contains("morphir.toml"))
  assert_true(result.files[".morphir/morphir.toml"].has_prefix(config))
  assert_eq(@workspace.discover(result).projects.map(p => p.name), ["Root"])
}

///|
test "project removal handles literals globs defaults and explicit deletion" {
  for members in ["['./one/', 'two']", "['*']"] {
    let initial = tree([
      (
        "morphir.toml",
        "# keep\n[workspace]\nmembers = " +
        members +
        "\ndefault_member = 'one'\n",
      ),
      ("one/morphir.toml", "[project]\nname='One'\n"),
      ("one/src/main.scm", "(define value 1)"),
      ("two/morphir.toml", "[project]\nname='Two'\n"),
    ])
    for delete_files in [false, true] {
      let edit = @workspace.remove_project(
        @workspace.discover(initial),
        initial,
        @workspace.ProjectPath::parse("one"),
        delete_files~,
      )
      let result = edit.apply(initial)
      assert_eq(@workspace.discover(result).projects.map(p => p.name), ["Two"])
      assert_eq(result.files.contains("one/src/main.scm"), !delete_files)
      assert_true(result.files["morphir.toml"].has_prefix("# keep\n"))
      assert_eq(
        @config.parse(result.files["morphir.toml"]).get(
          "workspace.default_member",
        ),
        None,
      )
    }
  }
}

///|
test "remove the root project keeps workspace files" {
  let empty = tree([])
  let initial = @workspace.init_workspace(
    empty,
    project=Some(new_project("Root")),
  ).apply(empty)
  let result = @workspace.remove_project(
    @workspace.discover(initial),
    initial,
    @workspace.ProjectPath::parse("."),
  ).apply(initial)
  assert_eq(@workspace.discover(result).projects.length(), 0)
  assert_true(result.files.contains("src/main.scm"))
}

///|
fn scaffold_refusal(action : () -> Unit raise) -> String {
  try {
    action()
    "accepted"
  } catch {
    @config.Invalid(message) => message
    error => "unexpected: " + error.to_string()
  }
}

///|
test "scaffolding refuses escapes existing configs excluded paths and source collisions" {
  let initial = tree([
    ("morphir.toml", "[workspace]\nmembers = ['*']\nexclude = ['private']\n"),
    ("existing/morphir.toml", "[project]\nname='Existing'\n"),
    ("collision/src/main.scm", "(define keep 1)"),
  ])
  for
    path in [
      "../escape", "/absolute", "C:/absolute", "private", "existing", "collision",
    ] {
    let message = scaffold_refusal(fn() raise {
      ignore(
        @workspace.add_project(
          @workspace.discover(initial),
          initial,
          @workspace.ProjectPath::parse(path),
          new_project("New"),
        ),
      )
    })
    assert_true(
      message != "accepted" && !message.has_prefix("unexpected:"),
      msg=path + ": " + message,
    )
  }
  assert_true(
    scaffold_refusal(fn() raise { ignore(@workspace.init_workspace(initial)) }).contains(
      "already exists",
    ),
  )
  let root = tree([("morphir.toml", "[workspace]\n[project]\nname='Root'\n")])
  assert_true(
    scaffold_refusal(fn() raise {
      ignore(
        @workspace.remove_project(
          @workspace.discover(root),
          root,
          @workspace.ProjectPath::parse("."),
          delete_files=true,
        ),
      )
    }).contains("Cannot delete"),
  )
}

///|
test "adding a project preserves dotted member keys and comments" {
  let config = "workspace.members = [] # untouched\n"
  let initial = tree([("morphir.toml", config)])
  let result = @workspace.add_project(
    @workspace.discover(initial),
    initial,
    @workspace.ProjectPath::parse("new"),
    new_project("New"),
  ).apply(initial)
  assert_eq(initial.files["morphir.toml"], config)
  assert_eq(
    result.files["morphir.toml"],
    "workspace.members = [\"new\"] # untouched\n",
  )
  assert_eq(@workspace.discover(result).projects.map(p => p.root), ["new"])
}
