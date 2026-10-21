///|
/// Browser storage held in memory for the duration of a test. Saves to keys that start with `failing` are refused;
/// an empty `failing` refuses nothing.
extern "js" fn storage_test_environment(failing : String) -> () -> Unit =
  #|(failing) => {
  #|  const workbench = globalThis.morphirWorkbench, document = globalThis.document;
  #|  const items = new Map();
  #|  const storage = {
  #|    load: key => items.has(key) ? items.get(key) : null,
  #|    save: (key, text) => { if (failing !== '' && key.startsWith(failing)) return false; items.set(key, text); return true; },
  #|    remove: key => { items.delete(key); return true; },
  #|    keys: prefix => [...items.keys()].filter(key => key.startsWith(prefix)),
  #|  };
  #|  globalThis.morphirWorkbench = { connected: false, projectIo: { storage } };
  #|  globalThis.document = { querySelector: () => null };
  #|  return () => {
  #|    if (workbench === undefined) delete globalThis.morphirWorkbench; else globalThis.morphirWorkbench = workbench;
  #|    if (document === undefined) delete globalThis.document; else globalThis.document = document;
  #|  };
  #|}

///|
/// The opening of `id` in this page: the active workspace's or a parked one's. `None` when `id` is not open.
fn open_visit(model : Model, id : @workspace.WorkspaceId) -> Visit? {
  if model.active == Some(id) {
    visit_of(model)
  } else {
    model.parked
    .get(id)
    .map(slice => { workspace: id, opening: slice.opening, })
  }
}

///|
/// `read_registry` and `adopt_legacy_projects` with one storage reader, as tests use them.
fn load_registry(model : Model, load : (String) -> String) -> Model {
  adopt_legacy_projects(read_registry(model, load, _ => []), load)
}

///|
/// A page with three saved idea workspaces, opened in order; the last one is active.
fn three_ideas() -> Model {
  run_all(starting_model(), [
    TryIdea(Intent),
    IntentText("First"),
    TryIdea(Intent),
    IntentText("Second"),
    TryIdea(Intent),
    IntentText("Third"),
  ])
}

///|
test "closing saves the workspace's source project and drafts before it leaves the page" {
  let restore = storage_test_environment("")
  defer restore()
  let source = run_all(starting_model(), [
    StartPreset(SourceProject),
    CreateWorkspace,
    Source("(define closed 1)"),
    AddContent(Intent),
    IntentText("Price orders"),
  ])
  let id = source.active.unwrap()
  let entry = active_entry(source).unwrap()
  let closed = run_all(source, [CloseWorkspace(id)])
  let reopened = run_all(closed, [OpenWorkspace(id)])
  @expect.expect_all(s => {
    s.expect(source.dirty.is_empty(), label="unsaved edit").to_be_false()
    s.expect(closed.active, label="no workspace").to_equal(None)
    s.expect(closed.parked.contains(id), label="not parked").to_be_false()
    s
    .expect(closed.screen == GettingStarted, label="getting started")
    .to_be_true()
    s.expect(closed.intent, label="page memory cleared").to_equal("")
    s
    .expect(
      saved_workspace_files(entry).read("intent.md").unwrap_or(""),
      label="draft saved",
    )
    .to_equal("Price orders")
    s
    .expect(
      saved_workspace_files(entry)
      .read("src/main.scm")
      .unwrap_or("")
      .contains("(define closed 1)"),
      label="project saved",
    )
    .to_be_true()
    s
    .expect(closed.registry.recents().map(e => e.id), label="still listed")
    .to_equal([id])
    s
    .expect(closed.start.message, label="said")
    .to_equal("Closed Source project")
    s.expect(reopened.active, label="reopened").to_equal(Some(id))
    s.expect(reopened.intent, label="draft restored").to_equal("Price orders")
    s
    .expect(active_text(reopened), label="source restored")
    .to_equal("(define closed 1)")
    s
    .expect(reopened.opening == source.opening, label="a new opening")
    .to_be_false()
  })
}

///|
test "closing the active workspace opens the most recently used open workspace" {
  let restore = storage_test_environment("")
  defer restore()
  let page = three_ideas()
  let third = page.active.unwrap()
  let ids = page.registry.entries.map(e => e.id)
  let first = ids[0]
  let second = ids[1]
  // The first workspace becomes the most recently used one that is not active.
  let page = run_all(page, [OpenWorkspace(first), OpenWorkspace(third)])
  let once = run_all(page, [CloseWorkspace(third)])
  let twice = run_all(once, [CloseWorkspace(first)])
  let all = run_all(twice, [CloseWorkspace(second)])
  @expect.expect_all(s => {
    s.expect(once.active, label="most recent").to_equal(Some(first))
    s.expect(once.intent, label="its draft").to_equal("First")
    s.expect(once.screen == Workspace, label="shown").to_be_true()
    s.expect(twice.active, label="the other").to_equal(Some(second))
    s.expect(twice.intent, label="other draft").to_equal("Second")
    s.expect(all.active, label="none open").to_equal(None)
    s.expect(all.screen == GettingStarted, label="getting started").to_be_true()
    s.expect(all.parked.length(), label="nothing parked").to_equal(0)
    s.expect(all.registry.recents().length(), label="all listed").to_equal(3)
  })
}

///|
test "a parked workspace closes in place" {
  let restore = storage_test_environment("")
  defer restore()
  let page = three_ideas()
  let first = page.registry.entries[0].id
  let closed = run_all(page, [ShowStart, CloseWorkspace(first)])
  @expect.expect_all(s => {
    s.expect(closed.active, label="active kept").to_equal(page.active)
    s.expect(closed.intent, label="active draft").to_equal("Third")
    s.expect(closed.parked.contains(first), label="closed").to_be_false()
    s
    .expect(closed.screen == GettingStarted, label="still getting started")
    .to_be_true()
    s
    .expect(
      saved_workspace_files(closed.registry.get(first).unwrap())
      .read("intent.md")
      .unwrap_or(""),
      label="saved",
    )
    .to_equal("First")
  })
}

///|
test "closing is refused while the workspace's operation runs or the host keeps its execution" {
  let restore = storage_test_environment("")
  defer restore()
  let page = three_ideas()
  let third = page.active.unwrap()
  let first = page.registry.entries[0].id
  let running = { ..page, busy: true, busy_origin: visit_of(page), }
  let refused = run_all(running, [CloseWorkspace(third)])
  let other = run_all(running, [CloseWorkspace(first)])
  let retained = run_all({ ..page, host_execution: { "state": "running" }, }, [
    CloseWorkspace(third),
  ])
  @expect.expect_all(s => {
    s.expect(refused.active, label="still open").to_equal(Some(third))
    s.expect(refused.busy, label="never cancelled").to_be_true()
    s
    .expect(refused.status, label="reason")
    .to_equal(
      "Wait for the running operation in Sandbox 3 to finish before closing it",
    )
    s
    .expect(closing_blocked(running, third) is Some(_), label="palette reason")
    .to_be_true()
    s.expect(other.parked.contains(first), label="other closes").to_be_false()
    s.expect(retained.active, label="retained").to_equal(Some(third))
    s
    .expect(retained.status, label="retained reason")
    .to_contain("retained host execution")
  })
}

///|
test "the opening that starts an operation is remembered until the runtime is free" {
  let restore = storage_test_environment("")
  defer restore()
  let started = run_all(starting_model(), [OpenFolder])
  let visit = open_visit(started, started.active.unwrap()).unwrap()
  let picked = ({ "ok": true, "files": [], "skipped": 0 } : Json).stringify()
  let busy = run_all(started, [Routed(visit, FolderPicked(picked))])
  let done = run_all(busy, [
    Routed(visit, FolderImported(busy.request_id, 0, imported_folder())),
  ])
  @expect.expect_all(s => {
    s.expect(busy.busy, label="busy").to_be_true()
    s.expect(busy.busy_origin, label="origin").to_equal(Some(visit))
    s.expect(done.busy, label="free").to_be_false()
    s.expect(done.busy_origin, label="forgotten").to_equal(None)
  })
}

///|
test "a workspace that browser storage does not keep stays open" {
  let restore = storage_test_environment("morphir-workbench.workspace.")
  defer restore()
  let page = run_all(starting_model(), [TryIdea(Intent), IntentText("Keep")])
  let id = page.active.unwrap()
  let refused = run_all(page, [CloseWorkspace(id)])
  @expect.expect_all(s => {
    s.expect(refused.active, label="still open").to_equal(Some(id))
    s.expect(refused.intent, label="draft kept").to_equal("Keep")
    s
    .expect(refused.status, label="reason")
    .to_equal("This browser did not save Sandbox, so it stays open")
  })
}

///|
test "a late reply for a closed opening is ignored, also after the workspace opens again" {
  let restore = storage_test_environment("")
  defer restore()
  let page = run_all(starting_model(), [TryIdea(Intent), IntentText("Kept")])
  let id = page.active.unwrap()
  let old = visit_of(page).unwrap()
  let closed = run_all(page, [CloseWorkspace(id)])
  let late = run_all(closed, [Routed(old, IntentText("Late"))])
  let reopened = run_all(late, [OpenWorkspace(id)])
  let later = run_all(reopened, [
    Routed(old, IntentText("Later")),
    Routed(old, SaveDrafts(1)),
  ])
  let current = run_all(reopened, [
    Routed(visit_of(reopened).unwrap(), IntentText("Current")),
  ])
  @expect.expect_all(s => {
    s.expect(late.active, label="nothing opened").to_equal(None)
    s
    .expect(
      late.panel.logs.any(log => log.message.contains("no longer open")),
      label="noted",
    )
    .to_be_true()
    s.expect(later.intent, label="reopened draft unchanged").to_equal("Kept")
    s.expect(current.intent, label="its own replies apply").to_equal("Current")
  })
}

///|
test "a connected host's workspace cannot close, and a waiting one closes like Stop waiting" {
  let restore = storage_test_environment("")
  defer restore()
  let connected = start_session({ ..starting_model(), connected: true, })
  let host = connected.active.unwrap()
  let kept = run_all(connected, [CloseWorkspace(host)])
  let waiting = run_all(starting_model(), [OpenFolder])
  let stopped = run_all(waiting, [CloseWorkspace(waiting.active.unwrap())])
  @expect.expect_all(s => {
    s.expect(kept.active, label="host kept").to_equal(Some(host))
    s.expect(kept.status, label="reason").to_contain("connected host")
    s.expect(stopped.acquiring is None, label="stopped").to_be_true()
    s.expect(stopped.registry.entries, label="removed").to_equal([])
    s
    .expect(stopped.start.message, label="said")
    .to_equal("Stopped waiting; nothing was opened")
  })
}

///|
test "a closed workspace can be removed from this browser" {
  let restore = storage_test_environment("")
  defer restore()
  let page = run_all(starting_model(), [TryIdea(Intent), IntentText("Gone")])
  let id = page.active.unwrap()
  let open_refused = run_all(page, [RemoveWorkspace(id)])
  let entry = active_entry(page).unwrap()
  let removed = run_all(page, [CloseWorkspace(id), RemoveWorkspace(id)])
  @expect.expect_all(s => {
    s
    .expect(open_refused.start.message, label="open refused")
    .to_equal("Close the workspace before you remove it from this browser")
    s.expect(removed.registry.get(id), label="removed").to_equal(None)
    s
    .expect(
      storage_load(
        "morphir-workbench.workspace." + entry.id.to_string() + ".tree.v1",
      ),
      label="keys gone",
    )
    .to_equal("")
    s
    .expect(removed.start.message, label="said")
    .to_equal("Removed Sandbox from this browser")
  })
}

///|
test "closing the active workspace from getting started stays on getting started" {
  let restore = storage_test_environment("")
  defer restore()
  let page = three_ideas()
  let third = page.active.unwrap()
  let second = page.registry.entries[1].id
  let closed = run_all(page, [ShowStart, CloseWorkspace(third)])
  @expect.expect_all(s => {
    s
    .expect(closed.screen == GettingStarted, label="still getting started")
    .to_be_true()
    s.expect(closed.active, label="next open workspace").to_equal(Some(second))
    s.expect(closed.intent, label="its draft").to_equal("Second")
    s.expect(closed.parked.contains(third), label="closed").to_be_false()
  })
}

///|
test "a stopped wait returns to the most recently used open workspace when the earlier one closed" {
  let restore = storage_test_environment("")
  defer restore()
  let page = three_ideas()
  let third = page.active.unwrap()
  let second = page.registry.entries[1].id
  let waiting = run_all(page, [OpenFolder])
  let closed = run_all(waiting, [CloseWorkspace(third)])
  let stopped = run_all(closed, [StopAcquiring])
  @expect.expect_all(s => {
    s.expect(closed.acquiring is Some(_), label="still waiting").to_be_true()
    s.expect(stopped.acquiring is None, label="stopped").to_be_true()
    s.expect(stopped.active, label="most recent open").to_equal(Some(second))
    s.expect(stopped.intent, label="its draft").to_equal("Second")
  })
}

///|
test "a workspace whose entry the workspace list does not keep stays open" {
  let restore = storage_test_environment(@workspace.registry_key)
  defer restore()
  let page = run_all(starting_model(), [TryIdea(Intent), IntentText("Keep")])
  let id = page.active.unwrap()
  let refused = run_all(page, [CloseWorkspace(id)])
  @expect.expect_all(s => {
    s.expect(refused.active, label="still open").to_equal(Some(id))
    s.expect(refused.intent, label="draft kept").to_equal("Keep")
    s
    .expect(refused.status, label="reason")
    .to_equal("This browser did not save Sandbox, so it stays open")
  })
}

///|
fn saved_workspace_files(entry : @workspace.Entry) -> @workspace_files.Files {
  known(() => {
    @workspace_files.load(
      "morphir-workbench.workspace." + entry.id.to_string(),
      key => if storage_stored(key) { Some(storage_load(key)) } else { None },
    ).unwrap()
  })
}
