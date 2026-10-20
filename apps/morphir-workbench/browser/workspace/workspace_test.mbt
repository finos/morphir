///|
fn name(text : String) -> @workspace.WorkspaceName {
  @workspace.WorkspaceName::parse(text).unwrap()
}

///|
test "names are trimmed and bounded" {
  @expect.expect_all(s => {
    s
    .expect(
      @workspace.WorkspaceName::parse("  Orders  ").map(n => n.to_string()),
    )
    .to_equal(Ok("Orders"))
    s
    .expect(@workspace.WorkspaceName::parse("   ").map(n => n.to_string()))
    .to_equal(Err("Enter a name for the workspace"))
    s
    .expect(
      @workspace.WorkspaceName::parse("x".repeat(81)).map(n => n.to_string()),
    )
    .to_equal(Err("Use at most 80 characters"))
    s
    .expect(@workspace.WorkspaceName::parse("a\u{7}b").map(n => n.to_string()))
    .to_equal(Err("Remove control characters from the name"))
  })
}

///|
test "ids are spelled w and a positive number" {
  @expect.expect_all(s => {
    s
    .expect(@workspace.WorkspaceId::parse("w12").map(id => id.to_string()))
    .to_equal(Some("w12"))
    s.expect(@workspace.WorkspaceId::parse("w0")).to_equal(None)
    s.expect(@workspace.WorkspaceId::parse("w012")).to_equal(None)
    s.expect(@workspace.WorkspaceId::parse("12")).to_equal(None)
    s.expect(@workspace.WorkspaceId::parse("w1x")).to_equal(None)
  })
}

///|
test "new workspaces get unique names and distinct ids" {
  let registry = @workspace.Registry::new()
  let (registry, first) = registry.create(Sandbox)
  let (registry, second) = registry.create(Sandbox)
  let (registry, named) = registry.create(Empty, name=name("Orders"))
  @expect.expect_all(s => {
    s.expect(first.name.to_string()).to_equal("Sandbox")
    s.expect(second.name.to_string()).to_equal("Sandbox 2")
    s.expect(named.name.to_string()).to_equal("Orders")
    s.expect(first.id == second.id).to_equal(false)
    s.expect(registry.entries.length()).to_equal(3)
  })
}

///|
test "presets seed contents without limiting what a workspace holds" {
  let (registry, sandbox) = @workspace.Registry::new().create(Sandbox, contents=[
    Intent,
    Intent,
  ])
  let registry = registry
    .add(sandbox.id, SourceProject)
    .add(sandbox.id, ModelDocument)
    .add(sandbox.id, SourceProject)
  let entry = registry.get(sandbox.id).unwrap()
  @expect.expect_all(s => {
    s.expect(entry.contents).to_equal([Intent, SourceProject, ModelDocument])
    s.expect(entry.preset).to_equal(Sandbox)
  })
}

///|
test "recent workspaces are saved ones in opening order" {
  let registry = @workspace.Registry::new()
  let (registry, a) = registry.create(SourceProject)
  let (registry, b) = registry.create(Sandbox)
  let (registry, pending) = registry.create(ModelExploration, saved=false)
  let registry = registry.touch(a.id)
  @expect.expect_all(s => {
    s
    .expect(registry.recents().map(e => e.name.to_string()))
    .to_equal(["Source project", "Sandbox"])
    s
    .expect(registry.recents(except=Some(a.id)).map(e => e.id == b.id))
    .to_equal([true])
    s
    .expect(registry.save(pending.id).recents().length(), label="after save")
    .to_equal(3)
    s
    .expect(registry.remove(b.id).recents().map(e => e.id == a.id))
    .to_equal([true])
  })
}

///|
test "documents and views follow the workspace contents" {
  @expect.expect_all(s => {
    s
    .expect(@workspace.documents([ModelDocument], connected=false))
    .to_equal([Model])
    s
    .expect(@workspace.views([ModelDocument], connected=false))
    .to_equal([Models])
    s
    .expect(@workspace.documents([Intent, Worksheet], connected=false))
    .to_equal([Source, IntentDraft])
    s
    .expect(@workspace.views([SourceProject], connected=false))
    .to_equal([Files, Models, Generated])
    s
    .expect(
      @workspace.views([SourceProject], connected=true),
      label="connected",
    )
    .to_equal([Models, Generated])
    s.expect(@workspace.documents([], connected=false)).to_equal([])
  })
}

///|
test "legacy projects keep their keys; new workspaces get their own" {
  let (registry, legacy) = @workspace.Registry::new().adopt_legacy()
  let (registry, again) = registry.adopt_legacy()
  let (_, scoped) = registry.create(SourceProject)
  @expect.expect_all(s => {
    s.expect(legacy.name.to_string()).to_equal("My project")
    s.expect(again.id == legacy.id).to_equal(true)
    s
    .expect(legacy.project_key("elm"))
    .to_equal("morphir-workbench.project.elm.v1")
    s
    .expect(scoped.project_key("elm"))
    .to_equal("morphir-workbench.workspace.w2.project.elm.v1")
    s
    .expect(scoped.draft_key(Intent))
    .to_equal("morphir-workbench.workspace.w2.intent.v1")
    s.expect(scoped.keys(["elm", "scheme"]).length()).to_equal(5)
  })
}

///|
test "the saved registry round trips and leaves out unreadable workspaces" {
  let registry = @workspace.Registry::new()
  let (registry, a) = registry.create(SourceProject, contents=[SourceProject])
  let (registry, _) = registry.create(ModelExploration, saved=false)
  let (registry, b) = registry.create(Sandbox, contents=[Intent])
  let layout = @shell.Layout::default().apply(Move(Files, Secondary))
  let registry = registry.set_layout(a.id, layout).touch(a.id)
  let (decoded, problems) = @workspace.Registry::from_json(registry.to_json())
  let (_, created) = decoded.create(Empty)
  @expect.expect_all(s => {
    s.expect(problems).to_equal([])
    s.expect(decoded.entries.length()).to_equal(2)
    s.expect(decoded.get(a.id).map(e => e.layout)).to_equal(Some(layout))
    s.expect(decoded.get(b.id).map(e => e.contents)).to_equal(Some([Intent]))
    s
    .expect(decoded.recents().map(e => e.id == a.id), label="order kept")
    .to_equal([true, false])
    s.expect(created.id.to_string(), label="ids are not reused").to_equal("w4")
  })
}

///|
test "malformed saved registries are refused" {
  let odd : Json = {
    "version": 1,
    "next": 2,
    "workspaces": [
      {
        "id": "w5",
        "name": "Kept",
        "preset": "sandbox",
        "opened": 3,
        "contents": ["intent", "bogus"],
      },
      { "id": "w5", "name": "Duplicate", "preset": "sandbox", "opened": 1 },
      { "id": "x", "name": "Bad id", "preset": "sandbox", "opened": 1 },
      { "id": "w6", "name": "", "preset": "sandbox", "opened": 1 },
      { "id": "w7", "name": "Bad preset", "preset": "kind", "opened": 1 },
    ],
  }
  let (decoded, problems) = @workspace.Registry::from_json(odd)
  let (_, next) = decoded.create(Empty)
  @expect.expect_all(s => {
    s.expect(decoded.entries.map(e => e.name.to_string())).to_equal(["Kept"])
    s.expect(decoded.entries[0].contents).to_equal([Intent])
    s.expect(problems.length()).to_equal(4)
    s.expect(next.id.to_string()).to_equal("w6")
    s
    .expect(@workspace.Registry::from_json({ "version": 2 }).1.length())
    .to_equal(1)
    s
    .expect(@workspace.Registry::from_json(Json::null()))
    .to_equal((@workspace.Registry::new(), []))
  })
}

///|
test "registries saved by two pages merge without reusing numbers" {
  let base = @workspace.Registry::new()
  let (here, mine) = base.create(Sandbox)
  let (there, theirs) = base.create(SourceProject)
  let (there, gone) = there.create(Empty)
  let merged = here.merge(there, removed=[gone.id])
  let (_, next) = merged.create(Empty)
  @expect.expect_all(s => {
    s.expect(mine.id == theirs.id, label="both picked w1").to_be_true()
    s.expect(merged.entries.length(), label="one entry per id").to_equal(1)
    s.expect(next.id.to_string(), label="after both").to_equal("w3")
    s
    .expect(
      here
      .reserve(
        @workspace.numbers_in_keys([
          "morphir-workbench.workspace.w7.intent.v1", "morphir-workbench.workspace.w12.project.elm.v1",
          "morphir-workbench.project.elm.v1", "morphir-workbench.workspace.wx.intent.v1",
        ]),
      )
      .create(Empty).1.id.to_string(),
      label="reserved",
    )
    .to_equal("w13")
  })
}

///|
test "a workspace's language is kept with it" {
  let (registry, entry) = @workspace.Registry::new().create(SourceProject)
  let elm = @ids.LanguageId::parse("elm") catch { _ => abort("elm") }
  let (decoded, _) = @workspace.Registry::from_json(
    registry.set_language(entry.id, elm).to_json(),
  )
  @expect.expect(
    decoded.get(entry.id).unwrap().language.map(l => l.to_string()),
  ).to_equal(Some("elm"))
}
