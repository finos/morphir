///|
test "a virtual workspace is never its own glob member or a hidden config member" {
  for pattern in ["*", "**"] {
    for
      anchor in [
        "morphir.toml", ".morphir/morphir.toml", ".config/morphir/config.toml",
      ] {
      let workspace = @workspace.discover(
        tree([
          (anchor, "[workspace]\nmembers=['" + pattern + "']\n"),
          ("member/morphir.toml", "[project]\nname='Member'\n"),
        ]),
      )
      assert_eq(workspace.projects.map(p => p.root), ["member"])
    }
  }
  assert_eq(
    @workspace.discover(tree([("morphir.toml", "[workspace]\nmembers=[]\n")])).projects.length(),
    0,
  )
}

///|
test "a nameless root project with workspace.root gets a nonempty name" {
  let workspace = @workspace.discover(
    tree([("morphir.toml", "[workspace]\nroot='workspace'\n[project]\n")]),
  )
  assert_eq(workspace.projects[0].name, "user")
  assert_eq(workspace.projects[0].error, None)
}

///|
test "missing literal members warn and normalized literal members require config" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.toml", "[workspace]\nmembers=['missing','./member/']\n"),
      ("member/keep.txt", ""),
    ]),
  )
  assert_true(
    workspace.warnings.any(w => w.contains("Missing workspace member")),
  )
  assert_eq(workspace.projects.length(), 1)
  assert_true(workspace.projects[0].error is Some(_))
}

///|
test "duplicate names warn and discovery serializes its diagnostics" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.toml", "[workspace]\nmembers=['*']\n"),
      ("one/morphir.toml", "[project]\nname='Same'\n"),
      ("two/morphir.toml", "[project]\nname='Same'\n"),
    ]),
  )
  assert_true(workspace.warnings.any(w => w.contains("Duplicate project name")))
  guard workspace.to_json() is Object(fields) else { fail("Expected snapshot") }
  guard fields.get("diagnostics") is Some(Array(diagnostics)) else {
    fail("Expected diagnostics")
  }
  assert_true(!diagnostics.is_empty())
}

///|
test "selection accepts dot and normalized member paths and defaults to the workspace" {
  let workspace = @workspace.discover(
    tree([
      (
        "morphir.toml", "[workspace]\nmembers=['member']\n[project]\nname='Root'\n",
      ),
      ("member/morphir.toml", "[project]\nname='Member'\n"),
    ]),
  )
  assert_eq(workspace.select(selector=".")[0].name, "Root")
  assert_eq(workspace.select(selector="./member/")[0].name, "Member")
  assert_eq(workspace.select().length(), 2)
  assert_eq(workspace.select(invocation="member/src")[0].name, "Member")
  let defaults = @workspace.discover(
    tree([
      (
        "morphir.toml", "[workspace]\nmembers=['member']\ndefault_member='member'\n[project]\nname='Root'\n",
      ),
      ("member/morphir.toml", "[project]\nname='Member'\n"),
    ]),
  )
  assert_eq(defaults.select().map(p => p.name), ["Member"])
  assert_eq(defaults.select(all=true).length(), 2)
}

///|
test "discovery protocol accepts legacy numeric requests and emits semver snapshots" {
  let workspace = @workspace.discover_request({
    "protocolVersion": 1,
    "developmentRoot": {
      "entries": {
        "morphir.toml": { "kind": "file", "text": "[workspace]\nmembers=[]\n" },
      },
    },
  })
  guard workspace.to_json() is Object(fields) else { fail("snapshot") }
  assert_eq(fields.get("protocolVersion"), Some(Json::string("0.1.0")))
}
