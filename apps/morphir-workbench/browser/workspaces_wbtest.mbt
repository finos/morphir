///|
fn quiet() -> @cmd.Emit[Msg] {
  @cmd.Emit(fn(_) { @cmd.none })
}

///|
fn run_all(model : Model, msgs : Array[Msg]) -> Model {
  msgs.fold(init=model, (current, msg) => update(current, msg, quiet()).0)
}

///|
/// A page after `initialize` with no workspace open, as getting started shows it.
fn starting_model() -> Model {
  let model = scope_model()
  {
    ..model,
    registry: @workspace.Registry::new(),
    active: None,
    screen: GettingStarted,
    catalog: catalog_fixture(),
    available: true,
    language: "scheme",
  }
}

///|
fn imported_folder() -> String {
  (
    {
      "success": true,
      "project": {
        "name": "Rentals",
        "languageId": "elm",
        "exposedModules": ["Rentals"],
        "files": [
          {
            "path": "src/Rentals.elm",
            "content": "module Rentals exposing (..)\n",
          },
        ],
      },
    } : Json).stringify()
}

///|
test "a late reply changes the workspace that asked for it, not the active one" {
  let source = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "elm",
    busy: true,
    request_id: 7,
  }
  let origin = source.active.unwrap()
  let idea = run_all(source, [TryIdea(Intent), IntentText("Price orders")])
  let reply : Json = {
    "success": false,
    "operation": "compile",
    "message": "Frontend errors",
    "frontendDiagnostics": [
      { "path": "src/Workbench/Main.elm", "problems": [{}] },
    ],
  }
  let (after, _) = update(
    idea,
    Routed(
      open_visit(source, origin).unwrap(),
      Receive(7, source.revision, "compile", reply.stringify()),
    ),
    quiet(),
  )
  let parked = after.parked.get(origin).unwrap()
  @expect.expect_all(s => {
    s.expect(after.active, label="still active").to_equal(idea.active)
    s.expect(after.doc, label="still the intent").to_equal(IntentDraft)
    s.expect(after.intent, label="draft kept").to_equal("Price orders")
    s.expect(after.busy, label="shared runtime freed").to_be_false()
    s
    .expect(after.problem_counts, label="not this workspace's problems")
    .to_equal(Map([]))
    s
    .expect(parked.problem_counts.get("src/Workbench/Main.elm"), label="origin")
    .to_equal(Some(1))
  })
}

///|
test "switching workspaces keeps each workspace's source and drafts" {
  let source = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let first = source.active.unwrap()
  let edited = run_all(source, [Source("(define kept 1)")])
  let idea = run_all(edited, [
    TryIdea(ConceptualModel),
    ConceptText("Order has Lines"),
  ])
  let second = idea.active.unwrap()
  let back = run_all(idea, [OpenWorkspace(first)])
  let again = run_all(back, [OpenWorkspace(second)])
  @expect.expect_all(s => {
    s.expect(back.active, label="first").to_equal(Some(first))
    s.expect(active_text(back), label="source kept").to_equal("(define kept 1)")
    s.expect(back.concept, label="other draft parked").to_equal("")
    s
    .expect(back.parked.get(second).map(slice => slice.concept), label="parked")
    .to_equal(Some("Order has Lines"))
    s.expect(again.concept, label="draft restored").to_equal("Order has Lines")
    s.expect(again.doc, label="its document").to_equal(ConceptDraft)
    s.expect(again.parked.contains(first), label="first parked").to_be_true()
  })
}

///|
test "a cancelled model import removes its provisional workspace" {
  let started = run_all(starting_model(), [ExploreModel(false)])
  let provisional = started.active.unwrap()
  let attempt = started.document.opening().unwrap()
  let cancelled = run_all(started, [
    Routed(
      open_visit(started, provisional).unwrap(),
      Imported(attempt, ({ "kind": "cancelled" } : Json).stringify()),
    ),
  ])
  @expect.expect_all(s => {
    s
    .expect(started.screen == GettingStarted, label="still starting")
    .to_be_true()
    s.expect(started.registry.recents(), label="not listed").to_equal([])
    s.expect(cancelled.active, label="no workspace").to_equal(None)
    s.expect(cancelled.registry.entries, label="removed").to_equal([])
    s.expect(cancelled.acquiring is None, label="settled").to_be_true()
    s
    .expect(cancelled.start.message, label="reason")
    .to_equal("Model import cancelled")
    s.expect(cancelled.busy, label="free").to_be_false()
  })
}

///|
test "a failed acquisition returns to the workspace that was open" {
  let source = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let first = source.active.unwrap()
  let edited = run_all(source, [Source("(define kept 2)")])
  let started = run_all(edited, [OpenFolder])
  let provisional = started.active.unwrap()
  let refused = run_all(started, [
    Routed(
      open_visit(started, provisional).unwrap(),
      FolderPicked(
        ({ "ok": false, "message": "No morphir.json" } : Json).stringify(),
      ),
    ),
  ])
  @expect.expect_all(s => {
    s.expect(provisional == first, label="new workspace").to_be_false()
    s.expect(refused.active, label="first again").to_equal(Some(first))
    s
    .expect(active_text(refused), label="its source")
    .to_equal("(define kept 2)")
    s.expect(refused.registry.get(provisional), label="removed").to_equal(None)
    s
    .expect(refused.screen == GettingStarted, label="getting started")
    .to_be_true()
    s.expect(refused.start.message, label="reason").to_equal("No morphir.json")
  })
}

///|
test "an imported folder keeps its workspace, named after the project" {
  let started = run_all(starting_model(), [OpenFolder])
  let provisional = started.active.unwrap()
  let picked = ({ "ok": true, "files": [], "skipped": 0 } : Json).stringify()
  let visit = open_visit(started, provisional).unwrap()
  let busy = run_all(started, [Routed(visit, FolderPicked(picked))])
  let done = run_all(busy, [
    Routed(visit, FolderImported(busy.request_id, 0, imported_folder())),
  ])
  let entry = done.registry.get(provisional).unwrap()
  @expect.expect_all(s => {
    s.expect(done.screen == Workspace, label="opened").to_be_true()
    s.expect(done.active, label="active").to_equal(Some(provisional))
    s.expect(entry.name.to_string(), label="name").to_equal("Rentals")
    s.expect(entry.saved, label="kept").to_be_true()
    s.expect(entry.contents, label="contents").to_equal([SourceProject])
    s.expect(done.doc, label="source").to_equal(Source)
    s.expect(done.acquiring is None, label="settled").to_be_true()
  })
}

///|
test "each workspace keeps its projects under its own keys" {
  let source = { ..scope_model(), catalog: catalog_fixture(), }
  let created = run_all(source, [TryIdea(Intent)])
  let entry = active_entry(created).unwrap()
  @expect.expect_all(s => {
    s
    .expect(storage_key(source, "elm"), label="earlier keys")
    .to_equal("morphir-workbench.project.elm.v1")
    s
    .expect(storage_key(created, "elm"), label="own keys")
    .to_equal(
      "morphir-workbench.workspace." + entry.id.to_string() + ".project.elm.v1",
    )
  })
}

///|
test "projects saved before workspaces become My project" {
  let stored = Map([("morphir-workbench.project.elm.v1", "{}")])
  let loaded = load_registry(starting_model(), key => {
    stored.get(key).unwrap_or("")
  })
  let none = load_registry(starting_model(), _ => "")
  @expect.expect_all(s => {
    s
    .expect(loaded.registry.recents().map(e => (e.name.to_string(), e.storage)))
    .to_equal([("My project", Legacy)])
    s.expect(none.registry.entries, label="nothing saved").to_equal([])
    s.expect(loaded.screen == GettingStarted, label="not opened").to_be_true()
  })
}

///|
test "the saved workspace list is read back after a reload" {
  let (registry, entry) = @workspace.Registry::new().create(Sandbox, contents=[
    Intent,
  ])
  let saved = registry.to_json().stringify()
  let loaded = load_registry(starting_model(), key => {
    if key == @workspace.registry_key {
      saved
    } else {
      ""
    }
  })
  let broken = load_registry(starting_model(), key => {
    if key == @workspace.registry_key {
      "{not json"
    } else {
      ""
    }
  })
  @expect.expect_all(s => {
    s
    .expect(loaded.registry.recents().map(e => e.id == entry.id), label="kept")
    .to_equal([true])
    s.expect(broken.registry.entries, label="refused").to_equal([])
    s
    .expect(
      broken.panel.logs.any(log => log.operation == "Workspaces"),
      label="said",
    )
    .to_be_true()
  })
}

///|
test "generation completes with a notice and keeps the layout" {
  let source = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
    target: "scheme",
    busy: true,
    request_id: 7,
  }
  let reply : Json = {
    "success": true,
    "operation": "compile",
    "artifacts": [{ "path": "src/main.scm", "content": "(define a 1)" }],
  }
  let (after, _) = update(
    source,
    Receive(7, source.revision, "compile", reply.stringify()),
    quiet(),
  )
  let shown = run_all(after, [ShowGenerated])
  let dismissed = run_all(after, [DismissNotice])
  @expect.expect_all(s => {
    s
    .expect(after.notice.map(n => (n.files, n.target)), label="notice")
    .to_equal(Some((1, "scheme")))
    s.expect(after.layout, label="layout kept").to_equal(source.layout)
    s
    .expect(dismissed.layout, label="dismiss keeps layout")
    .to_equal(source.layout)
    s.expect(dismissed.notice is None, label="dismissed").to_be_true()
    s.expect(shown.layout.shows(Generated), label="revealed").to_be_true()
    s.expect(shown.generated, label="preview tab").to_be_true()
  })
}

///|
test "sidebar changes follow the workspace into its saved entry" {
  let source = { ..scope_model(), catalog: catalog_fixture(), }
  let id = source.active.unwrap()
  let moved = run_all(source, [
    Shell(Move(Files, Secondary)),
    Shell(SetOpen(Primary, false)),
  ])
  @expect.expect_all(s => {
    s.expect(moved.layout.side_of(Files), label="moved").to_equal(Secondary)
    s.expect(moved.layout.is_open(Primary), label="closed").to_be_false()
    s
    .expect(moved.registry.get(id).map(e => e.layout), label="entry")
    .to_equal(Some(moved.layout))
  })
}

///|
test "selecting a declaration changes the document, never the workspace" {
  let source = { ..scope_model(), catalog: catalog_fixture(), }
  let selected = run_all(source, [Select("value|other")])
  @expect.expect_all(s => {
    s.expect(selected.doc, label="model").to_equal(Model)
    s.expect(selected.active, label="same workspace").to_equal(source.active)
  })
}

///|
test "a connected host's page opens its one workspace and keeps nothing" {
  let model = { ..starting_model(), connected: true, }
  let opened = start_session({
    ..model,
    projects: [{ "id": "p1", "name": "demo" }],
  })
  @expect.expect_all(s => {
    s.expect(opened.screen == Workspace, label="opened").to_be_true()
    s
    .expect(active_entry(opened).map(e => (e.name.to_string(), e.saved)))
    .to_equal(Some(("Connected host", false)))
    s.expect(opened.projects.length(), label="host projects").to_equal(1)
    s.expect(opened.registry.recents(), label="not listed").to_equal([])
    s
    .expect(
      run_all(opened, [TryIdea(Intent)]).active,
      label="no more workspaces",
    )
    .to_equal(opened.active)
  })
}

///|
test "stopping a wait removes the provisional workspace" {
  let started = run_all(starting_model(), [OpenFolder])
  let stopped = run_all(started, [StopAcquiring])
  @expect.expect_all(s => {
    s.expect(started.acquiring is Some(_), label="waiting").to_be_true()
    s.expect(stopped.acquiring is None, label="stopped").to_be_true()
    s.expect(stopped.active, label="no workspace").to_equal(None)
    s.expect(stopped.registry.entries, label="removed").to_equal([])
    s
    .expect(stopped.start.message, label="said")
    .to_equal("Stopped waiting; nothing was opened")
  })
}

///|
test "opening another workspace while one is pending keeps the earlier workspaces" {
  let source = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let first = source.active.unwrap()
  let edited = run_all(source, [Source("(define kept 3)")])
  let idea = run_all(edited, [TryIdea(Intent), IntentText("Keep me")])
  let second = idea.active.unwrap()
  let waiting = run_all(idea, [OpenFolder])
  let switched = run_all(waiting, [OpenWorkspace(first)])
  let back = run_all(switched, [OpenWorkspace(second)])
  @expect.expect_all(s => {
    s.expect(switched.acquiring is None, label="gave up").to_be_true()
    s.expect(switched.active, label="first").to_equal(Some(first))
    s
    .expect(active_text(switched), label="first source")
    .to_equal("(define kept 3)")
    s
    .expect(switched.registry.entries.length(), label="no provisional")
    .to_equal(2)
    s.expect(back.intent, label="second draft").to_equal("Keep me")
  })
}

///|
test "nothing opens before the session starts" {
  let starting = { ..starting_model(), catalog: Json::null(), busy: true, }
  let refused = run_all(starting, [TryIdea(Intent)])
  @expect.expect_all(s => {
    s.expect(refused.active, label="no workspace").to_equal(None)
    s.expect(refused.registry.entries, label="nothing saved").to_equal([])
    s
    .expect(refused.start.message, label="said")
    .to_equal("The Workbench is still starting; try again in a moment")
  })
}

///|
test "an example is saved under its own workspace and reopens on its language" {
  let opened = run_all(starting_model(), [OpenExample("builtin:moonbit")])
  let entry = active_entry(opened).unwrap()
  @expect.expect_all(s => {
    s.expect(opened.language, label="language").to_equal("moonbit")
    s.expect(opened.dirty.contains("moonbit"), label="to save").to_be_true()
    s
    .expect(entry.language.map(l => l.to_string()), label="kept")
    .to_equal(Some("moonbit"))
  })
}

///|
test "a saved list of another version is kept aside, not read as empty without a note" {
  let other = ({ "version": 2, "workspaces": [] } : Json).stringify()
  let loaded = read_registry(
    starting_model(),
    key => if key == @workspace.registry_key { other } else { "" },
    _ => [],
  )
  @expect.expect_all(s => {
    s.expect(loaded.registry.entries, label="nothing read").to_equal([])
    s
    .expect(
      loaded.panel.logs.any(log => log.message.contains(".unreadable")),
      label="backup named",
    )
    .to_be_true()
  })
}
