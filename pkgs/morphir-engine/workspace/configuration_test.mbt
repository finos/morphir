///|
test "configuration layers merge JSON5 YAML and TOML with real origins" {
  let workspace = @workspace.discover(
    tree([
      (
        "morphir.json", "// JSON5\n{workspace:{out_dir:'json'},frontend:{language:'scheme'},custom:{retained:true},}",
      ),
      ("morphir.yaml", "workspace:\n  out_dir: yaml\ncustom:\n  yaml: true\n"),
      ("morphir.toml", "[workspace]\nout_dir='toml'\n"),
    ]),
  )
  assert_eq(workspace.document.text("workspace.out_dir", ""), "toml")
  assert_eq(
    workspace.document.provenance.get("workspace.out_dir"),
    Some("morphir.toml"),
  )
  assert_eq(workspace.document.boolean("custom.retained", false), true)
  assert_eq(
    workspace.document.provenance.get("custom.retained"),
    Some("morphir.json"),
  )
  assert_eq(workspace.document.boolean("custom.yaml", false), true)
  assert_true(
    workspace.warnings.any(warning => {
      warning.contains("config.yaml_beside_toml")
    }),
  )
  assert_true(
    workspace.warnings.any(warning => {
      warning.contains("config.json_keys_below_toml")
    }),
  )
}

///|
test "same-layer ambiguity is refused at roots and members" {
  for
    files in [
      [("morphir.toml", ""), (".morphir/morphir.toml", "")],
      [("morphir.yaml", "{}"), ("morphir.yml", "{}")],
      [("morphir.json", "{}"), ("morphir.json5", "{}")],
      [
        ("morphir.toml", "workspace.members=['a']"),
        ("a/morphir.yaml", "{}"),
        ("a/morphir.yml", "{}"),
      ],
    ] {
    assert_true(failure(files).contains("Ambiguous configuration"))
  }
}

///|
test "selected files override primaries once and reject conflicting manifest keys" {
  let workspace = @workspace.discover(
    tree([
      (
        "morphir.toml", "[project]\nsource_directory='toml'\n[custom]\nretained=true",
      ),
      (
        "morphir.json", "{name:'Example',sourceDirectory:'json',exposedModules:['Main']}",
      ),
    ]),
    options=@workspace.ConfigurationOptions::new(selected="morphir.json"),
  )
  assert_eq(workspace.document.text("project.source_directory", ""), "json")
  assert_true(workspace.document.boolean("custom.retained", false))
  assert_true(
    failure([
      (
        "morphir.json", "{sourceDirectory:'x',exposedModules:[],project:{source_directory:'y'}}",
      ),
    ]).contains("sourceDirectory"),
  )
}

///|
test "profiles merge controls and load files between member primaries and user overrides" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.json", "{workspace:{members:['a']},profiles:{default:['old']}}"),
      (
        "morphir.toml", "[profiles]\ndefault=['metrics']\n[custom]\nvalue='base'",
      ),
      ("a/morphir.toml", "[project]\nname='A'\n[custom]\nvalue='member'"),
      ("morphir.profile.metrics.json", "{custom:{value:'json',retained:true}}"),
      ("morphir.profile.metrics.yaml", "custom:\n  value: yaml"),
      ("morphir.profile.metrics.toml", "[custom]\nvalue='toml'"),
      ("a/morphir.profile.metrics.toml", "[custom]\nvalue='profile'"),
      ("a/morphir.user.toml", "[custom]\nvalue='user'"),
      ("morphir.profile.old.toml", "not valid TOML!"),
    ]),
  )
  let document = workspace.projects[0].document
  assert_eq(document.text("custom.value", ""), "user")
  assert_eq(
    document.provenance.get("custom.value"),
    Some("a/morphir.user.toml"),
  )
  assert_true(document.boolean("custom.retained", false))
  assert_true(document.get("profiles") is None)
}

///|
test "disabled profile processing ignores invalid controls and environment selection" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.toml", "[profiles]\ndefault=42\n[custom]\nvalue='base'"),
      ("morphir.profile.metrics.toml", "not valid TOML!"),
    ]),
    environment=Map::from_array([("MORPHIR_PROFILES", "metrics")]),
    options=@workspace.ConfigurationOptions::new(profiles=Disabled),
  )
  assert_eq(workspace.document.text("custom.value", ""), "base")
  assert_true(workspace.document.get("profiles") is None)
}

///|
test "selected base controls retain authority while non-base controls fail" {
  let files = tree([
    ("morphir.toml", "[profiles]\ndefault=['metrics']"),
    ("morphir.profile.metrics.toml", "enabled=true"),
    ("custom.toml", "[profiles]\nactive=['other']"),
  ])
  let selected = @workspace.discover(
    files,
    options=@workspace.ConfigurationOptions::new(selected="morphir.toml"),
  )
  assert_true(selected.document.boolean("enabled", false))
  assert_eq(
    selected.document
    .framework()
    .reports()
    .filter(report => {
      report.status is Loaded &&
      report.path == Some("/__morphir_workspace/morphir.toml")
    })
    .length(),
    1,
  )
  let refused = try {
    ignore(
      @workspace.discover(
        files,
        options=@workspace.ConfigurationOptions::new(selected="custom.toml"),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "adding to lower-format workspaces writes complete TOML member lists" {
  for
    (name, content) in [
      ("morphir.json", "{workspace:{members:['ledger']}}"),
      ("morphir.yml", "workspace:\n  members: [ledger]"),
    ] {
    let original = tree([
      (name, content),
      ("ledger/morphir.toml", "[project]\nname='Ledger'"),
    ])
    let workspace = @workspace.discover(original)
    let edit = @workspace.add_project(
      workspace,
      original,
      @workspace.ProjectPath::parse("billing"),
      {
        name: @ids.SourcePackageName::parse("Billing"),
        language: None,
        profile: None,
        source_directory: "src",
      },
    )
    let result = edit.apply(original)
    assert_eq(result.files[name], content)
    assert_eq(
      @config.parse(result.files["morphir.toml"]).strings("workspace.members"),
      ["ledger", "billing"],
    )
    let projects = @workspace.discover(result).projects
    assert_eq(projects.length(), 2)
    assert_true(
      projects.any(project => {
        project.root == "billing" && project.name == "Billing"
      }),
    )
    assert_true(
      projects.any(project => {
        project.root == "ledger" && project.name == "Ledger"
      }),
    )
  }
}

///|
test "profile includes and groups preserve last occurrence order and reject inactive cycles" {
  let workspace = @workspace.discover(
    tree([
      (
        "morphir.toml", "[profiles]\ninclude=['metrics']\nactive=['production','postgres']\n[profiles.groups]\nproduction=['postgres','metrics']\n",
      ),
      ("morphir.profile.metrics.toml", "custom.winner='metrics'"),
      ("morphir.profile.production.toml", "custom.winner='production'"),
      ("morphir.profile.postgres.toml", "custom.winner='postgres'"),
    ]),
  )
  guard workspace.document.framework().profiles() is Resolved(resolution) else {
    fail("profile resolution")
  }
  assert_eq(resolution.active().names().map(name => name.to_string()), [
    "production", "metrics", "postgres",
  ])
  assert_eq(workspace.document.text("custom.winner", ""), "postgres")
  let cycle = failure([("morphir.toml", "[profiles.groups]\na=['b']\nb=['a']")])
  assert_true(cycle.contains("morphir.toml"), msg=cycle)
  assert_true(cycle.contains("Cycle"), msg=cycle)
}

///|
test "profile ordering is by name before workspace and member and ambiguity stays visible" {
  let workspace = @workspace.discover(
    tree([
      (
        "morphir.toml", "workspace.members=['a']\nprofiles.active=['postgres','metrics']",
      ),
      ("a/morphir.toml", "project.name='A'"),
      ("a/morphir.profile.postgres.toml", "custom.winner='member-postgres'"),
      (
        "morphir.profile.metrics.toml", "custom.winner='workspace-metrics'\nworkspace.members=['missing']",
      ),
    ]),
  )
  assert_eq(workspace.projects.length(), 1)
  assert_eq(workspace.projects[0].name, "A")
  assert_eq(
    workspace.projects[0].document.text("custom.winner", ""),
    "workspace-metrics",
  )
  let ambiguous = failure([
    ("morphir.toml", "profiles.active=['metrics']"),
    ("morphir.profile.metrics.yaml", "{}"),
    ("morphir.profile.metrics.yml", "{}"),
  ])
  assert_true(ambiguous.contains("morphir.profile.metrics.yaml"), msg=ambiguous)
  assert_true(ambiguous.contains("morphir.profile.metrics.yml"), msg=ambiguous)
}

///|
test "profile controls fail before member filters and user or environment merging" {
  for
    extra in [
      [("a/morphir.toml", "project.name='A'\nprofiles.active=['metrics']")],
      [
        ("a/morphir.toml", "project.name='A'"),
        ("a/morphir.user.toml", "profiles.active=['metrics']"),
      ],
      [("morphir.user.toml", "profiles.active=['metrics']")],
      [("morphir.profile.metrics.toml", "profiles.active=['other']")],
    ] {
    let message = failure(
      [
        ("morphir.toml", "workspace.members=['a']\nprofiles.active=['metrics']"),
        ..extra,
      ],
    )
    assert_true(message != "accepted", msg=message)
    assert_true(message.contains("profiles"), msg=message)
  }
  let environment = try {
    ignore(
      @workspace.discover(
        tree([("morphir.toml", "")]),
        environment=Map::from_array([("MORPHIR_PROFILES__ACTIVE", "metrics")]),
      ),
    )
    "accepted"
  } catch {
    @config.Invalid(message) => message
    error => error.to_string()
  }
  assert_true(environment != "accepted", msg=environment)
}

///|
test "empty profile environment disables includes and missing marker files stay active" {
  let files = tree([
    ("morphir.toml", "profiles.default=['metrics']\nprofiles.include=['audit']"),
  ])
  let disabled = @workspace.discover(
    files,
    environment=Map::from_array([("MORPHIR_PROFILES", " ")]),
  )
  guard disabled.document.framework().profiles() is Resolved(off) else {
    fail("disabled resolution")
  }
  assert_true(off.disabled())
  assert_eq(off.active().names().map(name => name.to_string()), [])
  let marker = @workspace.discover(
    files,
    options=@workspace.ConfigurationOptions::new(isolated=true),
  )
  guard marker.document.framework().profiles() is Resolved(active) else {
    fail("marker resolution")
  }
  assert_eq(active.active().names().map(name => name.to_string()), [
    "audit", "metrics",
  ])
  assert_true(
    marker.document
    .framework()
    .reports()
    .any(report => report.status is NotFound),
  )
}

///|
test "profile controls retain format origins and reject invalid literal controls and graph bounds" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.json", "{profiles:{default:['old']}}"),
      ("morphir.toml", "profiles.default=['metrics']"),
    ]),
  )
  guard workspace.document.framework().profiles() is Resolved(resolution) else {
    fail("resolution")
  }
  assert_eq(resolution.active().names().map(name => name.to_string()), [
    "metrics",
  ])
  assert_true(
    resolution
    .controls()
    .any(origin => {
      match origin {
        Control(source, _) =>
          source.location == Some("/__morphir_workspace/morphir.toml")
        _ => false
      }
    }),
  )
  for
    control in [
      "profiles.default=42", "profiles.unknown=[]", "profiles.active={env='ACTIVE'}",
    ] {
    let message = failure([("morphir.toml", control)])
    assert_true(
      message != "accepted" && message.contains("morphir.toml"),
      msg=message,
    )
  }
  let names = Array::makei(1025, index => "p" + index.to_string())
  let excessive = failure([
    ("morphir.toml", "profiles.active=" + Json(names).stringify()),
  ])
  assert_true(
    excessive != "accepted" && excessive.contains("morphir.toml"),
    msg=excessive,
  )
}

///|
test "no implicit profile requests or inactive file parsing occurs" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.toml", "project.name='Example'"),
      ("morphir.profile.metrics.toml", "not valid TOML!"),
    ]),
  )
  guard workspace.document.framework().profiles() is Resolved(resolution) else {
    fail("resolution")
  }
  assert_true(resolution.active().names().is_empty())
  assert_true(
    !workspace.document
    .framework()
    .reports()
    .any(report => {
      report.path == Some("/__morphir_workspace/morphir.profile.metrics.toml")
    }),
  )
}

///|
test "machine document controls cannot acquire base authority through a protocol mount" {
  let message = try {
    ignore(
      @workspace.discover_request({
        "protocolVersion": "0.1.0",
        "developmentRoot": {
          "entries": { "morphir.toml": { "kind": "file", "text": "" } },
        },
        "systemConfig": {
          "entries": {
            "morphir.toml": {
              "kind": "file",
              "text": "profiles.active=['metrics']",
            },
          },
        },
      }),
    )
    "accepted"
  } catch {
    @config.Invalid(message) => message
    error => error.to_string()
  }
  assert_true(message != "accepted", msg=message)
  assert_true(message.contains("profiles"), msg=message)
}

///|
test "preparsed host documents preserve leaf origins and cannot suppress through workspace files" {
  let workspace = @workspace.discover(
    tree([
      ("morphir.yaml", "workspace:\n  out_dir: yaml"),
      (
        "morphir.toml", "[workspace]\nout_dir='toml'\n[diagnostics]\nsuppress=['config.yaml_beside_toml']",
      ),
    ]),
    global=@config.parse(
      "[custom]\nvalue='host'",
      origin="/home/user/config.toml",
    ),
  )
  assert_eq(
    workspace.document.provenance.get("custom.value"),
    Some("/home/user/config.toml"),
  )
  assert_true(
    workspace.warnings.any(warning => {
      warning.contains("config.yaml_beside_toml")
    }),
  )
}
