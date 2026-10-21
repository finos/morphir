///|
#external
type OriginalRoutingFixture

///|
extern "js" fn original_routing_fixture(
  hash : () -> OriginalsHasher,
) -> @js_async.Promise[OriginalRoutingFixture] =
  #| async hash => {
  #|   const fs = require('node:fs'), path = require('node:path');
  #|   let root = process.cwd();
  #|   while (!fs.existsSync(path.join(root, 'apps/morphir-workbench/scripts/originals-routing-fixture.ts'))) {
  #|     const parent = path.dirname(root);
  #|     if (parent === root) throw new Error('Cannot locate originals routing fixture');
  #|     root = parent;
  #|   }
  #|   const directory = await fs.promises.mkdtemp(path.join(require('node:os').tmpdir(), 'morphir-originals-routing-'));
  #|   try {
  #|     // Node's strip-only loader cannot load all production TypeScript syntax.
  #|     // Compile the exact application fixture and maintained receiver with the
  #|     // pinned Bun tool, then import that actual output into this test process.
  #|     const output = path.join(directory, 'routing.mjs');
  #|     await require('node:util').promisify(require('node:child_process').execFile)('bun', [
  #|       'build', path.join(root, 'apps/morphir-workbench/scripts/originals-routing-fixture.ts'),
  #|       '--target=node', '--format=esm', '--outfile=' + output,
  #|     ], {maxBuffer: 65536});
  #|     const module = await import(require('node:url').pathToFileURL(output).href);
  #|     const fixture = await module.routingFixture(hash, path.join(root, 'apps/morphir-workbench/scripts/originals-fixture-host.ts'));
  #|     const finish = fixture.finish;
  #|     fixture.finish = async () => { try { await finish(); } finally { await fs.promises.rm(directory, {recursive:true, force:true}); } };
  #|     return fixture;
  #|   } catch (error) { await fs.promises.rm(directory, {recursive:true, force:true}); throw error; }
  #| }

///|
extern "js" fn routing_owner(
  fixture : OriginalRoutingFixture,
) -> ConnectedOpening =
  #| fixture => fixture.owner

///|
extern "js" fn routing_event(
  fixture : OriginalRoutingFixture,
) -> ConnectedOriginalsEvent =
  #| fixture => fixture.event

///|
extern "js" fn routing_takes(fixture : OriginalRoutingFixture) -> Int32 =
  #| fixture => fixture.takes

///|
extern "js" fn routing_disposals(fixture : OriginalRoutingFixture) -> Int32 =
  #| fixture => fixture.disposals

///|
extern "js" fn corrupt_handed_originals(fixture : OriginalRoutingFixture) =
  #| fixture => fixture.corruptHandedBytes()

///|
extern "js" fn finish_routing_fixture(
  fixture : OriginalRoutingFixture,
) -> @js_async.Promise[Unit] =
  #| fixture => fixture.finish()

///|
fn routing_model() -> Model {
  let base = lifecycle_model()
  {
    ..base,
    mode: ConnectedOriginals,
    registry: base.registry.save(base.active.unwrap()),
    catalog: catalog_fixture(),
    connected: false,
    pane: OutputOnly,
    open_outputs: ["old/generated.scala"],
    output: {
      "artifacts": [
        {
          "path": "old/generated.scala",
          "content": "object Previous",
          "binary": false,
        },
      ],
    },
  }
}

///|
async fn exercise_parked_originals() -> Unit {
  let restore_storage = storage_test_environment("")
  defer restore_storage()
  let restore_mode = originals_test_mode()
  defer restore_mode()
  let base = routing_model()
  // Begin is the real domain decision before creating the network fixture.
  let (begun, _) = update(base, OpenOriginals, quiet())
  let attempt = begun.document.opening().unwrap()
  let fixture = original_routing_fixture(make_originals_hasher).wait()
  defer finish_routing_fixture(fixture).wait()
  let owner = routing_owner(fixture)
  let source = run_all(begun, [OriginalsStarted(attempt, owner)])
  let origin = source.active.unwrap()
  let visit = open_visit(source, origin).unwrap()
  let parked = run_all(source, [
    TryIdea(Intent),
    IntentText("A different workspace"),
  ])
  assert_true(parked.active != source.active)
  assert_true(
    workspace_cards(parked).any(card => {
      card.id == origin && card.activity.contains(Working)
    }),
  )
  let after = run_all(parked, [
    Routed(visit, OriginalsChanged(attempt, routing_event(fixture))),
  ])
  assert_eq(after.active, parked.active)
  assert_eq(after.intent, "A different workspace")
  assert_eq(after.pane, parked.pane)
  assert_eq(after.open_outputs, parked.open_outputs)
  assert_false(after.busy)
  assert_eq(routing_takes(fixture), 1)
  let back = run_all(after, [OpenWorkspace(origin)])
  assert_eq(back.document.document(), base.document.document())
  assert_eq(back.document.current_revision(), base.document.current_revision())
  assert_eq(back.model_revision, base.model_revision)
  assert_eq(back.pane, base.pane)
  assert_eq(back.open_outputs, base.open_outputs)
  assert_eq(back.output, base.output)
  assert_true(back.document.inventory_revision() is Some(_))
  let inventory = back.document.original_inventory().unwrap()
  let expected = @utf8.encode("\u{FEFF}# original\r\nformatVersion: 4\r\n")
  assert_eq(inventory.copy_files().get("model.yaml"), Some(expected))
  corrupt_handed_originals(fixture)
  assert_eq(inventory.copy_files().get("model.yaml"), Some(expected))
  let duplicate = run_all(back, [
    Routed(visit, OriginalsChanged(attempt, routing_event(fixture))),
  ])
  assert_eq(duplicate.document, back.document)
  assert_eq(routing_takes(fixture), 1)
}

///|
async fn exercise_stale_original_attempt() -> Unit {
  let restore_storage = storage_test_environment("")
  defer restore_storage()
  let restore_mode = originals_test_mode()
  defer restore_mode()
  let base = routing_model()
  let (begun, _) = update(base, OpenOriginals, quiet())
  let old = begun.document.opening().unwrap()
  let fixture = original_routing_fixture(make_originals_hasher).wait()
  defer finish_routing_fixture(fixture).wait()
  let started = run_all(begun, [OriginalsStarted(old, routing_owner(fixture))])
  let next = match started.document.begin(Idle) {
    Started(document, _) => { ..started, document, }
    _ => abort("New opening must supersede the previous attempt")
  }
  let after = run_all(next, [OriginalsChanged(old, routing_event(fixture))])
  assert_eq(after.document, next.document)
  assert_eq(after.document.document(), base.document.document())
  assert_eq(after.document.original_inventory(), None)
  assert_eq(routing_takes(fixture), 0)
  assert_true(routing_disposals(fixture) > 0)
}

///|
async fn exercise_closed_original_visits() -> Unit {
  for reopen in [false, true] {
    let restore_storage = storage_test_environment("")
    defer restore_storage()
    let restore_mode = originals_test_mode()
    defer restore_mode()
    let (begun, _) = update(routing_model(), OpenOriginals, quiet())
    let attempt = begun.document.opening().unwrap()
    let fixture = original_routing_fixture(make_originals_hasher).wait()
    defer finish_routing_fixture(fixture).wait()
    let started = run_all(begun, [
      OriginalsStarted(attempt, routing_owner(fixture)),
    ])
    let id = started.active.unwrap()
    let visit = open_visit(started, id).unwrap()
    let refused = run_all(started, [CloseWorkspace(id)])
    assert_eq(open_visit(refused, id), Some(visit))
    assert_eq(routing_disposals(fixture), 0)
    // Keep the existing running-work close refusal. Cancel first, execute its
    // exact owned disposal boundary, then close/remove/reopen the workspace.
    let cancelled = run_all(refused, [Cancel])
    dispose_originals_panel(started.originals)
    let closed = run_all(cancelled, [CloseWorkspace(id)])
    assert_eq(open_visit(closed, id), None)
    assert_true(routing_disposals(fixture) > 0)
    let current = if reopen {
      run_all(closed, [OpenWorkspace(id)])
    } else {
      run_all(closed, [RemoveWorkspace(id)])
    }
    if reopen {
      assert_true(open_visit(current, id) is Some(_))
      assert_true(open_visit(current, id) != Some(visit))
    } else {
      assert_eq(current.registry.get(id), None)
    }
    let late = run_all(current, [
      Routed(visit, OriginalsChanged(attempt, routing_event(fixture))),
    ])
    assert_eq(late.document, current.document)
    assert_eq(late.document.original_inventory(), None)
    assert_eq(routing_takes(fixture), 0)
  }
}

///|
async test "actual queued originals preserve parked Both ownership and refuse stale deliveries" {
  // These fixtures own the same page boundary, so exercise them serially.
  exercise_parked_originals()
  exercise_stale_original_attempt()
  exercise_closed_original_visits()
}
