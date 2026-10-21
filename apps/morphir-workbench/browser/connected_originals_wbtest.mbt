///|
extern "js" fn originals_test_mode() -> () -> Unit =
  #| () => {
  #|   const previous = globalThis.morphirWorkbench;
  #|   globalThis.morphirWorkbench = { ...previous, connected: true, mode: 'connected-originals' };
  #|   return () => { if (previous === undefined) delete globalThis.morphirWorkbench; else globalThis.morphirWorkbench = previous; };
  #| }

///|
test "originals experience offers model browsing without runtime actions" {
  let restore = originals_test_mode()
  defer restore()
  let model = {
    ..lifecycle_model(),
    mode: ConnectedOriginals,
    connected: true,
    busy: false,
  }
  assert_eq(documents_of(model), [Model])
  assert_eq(views_of(model), [Models])
  assert_false(
    palette_commands(model).any(command => {
      command.id is (Compile | Run | SwitchLayout | ShowSource)
    }),
  )
  let (worksheet, _) = update(model, Layout(true), quiet())
  assert_eq(worksheet.worksheet, model.worksheet)
  for operation in ["compile", "run", "worksheet"] {
    let (after, _) = update(model, Request(operation), quiet())
    assert_eq(after.request_id, model.request_id)
    assert_eq(after.document, model.document)
    assert_eq(after.busy, model.busy)
  }
}

///|
test "originals page cursor is bounded and stale inventory navigation is refused" {
  let inventory = @document.OriginalInventory::from_connected(
    Map([("model.yaml", b"opaque")]),
    Array::makei(204, index => "empty-" + index.to_string()),
    NotReported,
  )
  let (opening, attempt) = match @document.State::new().begin(Idle) {
    Started(state, attempt) => (state, attempt)
    _ => abort("begin")
  }
  let document = opening.finish_originals(attempt, inventory)
  let revision = document.inventory_revision().unwrap()
  let first = OriginalsPage::first()
  assert_eq(first.start(), 0)
  assert_eq(first.previous(), None)
  let second = first.next(inventory.entry_count()).unwrap()
  let last = second.next(inventory.entry_count()).unwrap()
  assert_eq(second.start(), 100)
  assert_eq(last.start(), 200)
  assert_eq(last.next(inventory.entry_count()), None)
  assert_eq(second.previous(), Some(first))
  let model = { ..lifecycle_model(), document, originals_page: first, }
  let (paged, _) = update(
    model,
    OriginalsPageChanged(revision, second),
    quiet(),
  )
  assert_eq(paged.originals_page, second)
  assert_eq(paged.document, model.document)
  assert_eq(
    paged.document.current_revision(),
    model.document.current_revision(),
  )
  let (opening, attempt) = match document.begin(Idle) {
    Started(state, attempt) => (state, attempt)
    _ => abort("replace")
  }
  let small = @document.OriginalInventory::from_connected(
    Map([("next.yaml", b"next")]),
    [],
    NotReported,
  )
  let replaced = {
    ..paged,
    document: opening.finish_originals(attempt, small),
  }
  let current = replaced.document.inventory_revision().unwrap()
  let (stale, _) = update(
    replaced,
    OriginalsPageChanged(revision, last),
    quiet(),
  )
  assert_eq(stale.originals_page, replaced.originals_page)
  let (outside, _) = update(
    replaced,
    OriginalsPageChanged(current, last),
    quiet(),
  )
  assert_eq(outside.originals_page, replaced.originals_page)
}

///|
test "originals opening preserves its owner when host authority is retained" {
  let base = { ..lifecycle_model(), mode: ConnectedOriginals, }
  let restore = originals_test_mode()
  defer restore()
  for unknown in [false, true] {
    let retained = {
      ..base,
      connected: true,
      host_submitting: !unknown,
      submission_unknown: unknown,
      busy: true,
    }
    let (after, _) = update(retained, OpenOriginals, quiet())
    assert_eq(after.document, retained.document)
    assert_true(after.originals == retained.originals)
    assert_true(after.status.contains("retained host execution"))
  }
}

///|
test "originals Started keeps its semantic owner and source pane choices" {
  let base = { ..lifecycle_model(), mode: ConnectedOriginals, }
  let restore = originals_test_mode()
  defer restore()
  let (opening, _) = update(
    { ..base, connected: true, },
    OpenOriginals,
    quiet(),
  )
  assert_true(opening.busy)
  assert_true(opening.document.opening() is Some(_))
  assert_eq(opening.document.document(), base.document.document())
  assert_eq(
    opening.document.current_revision(),
    base.document.current_revision(),
  )
  assert_eq(opening.pane, base.pane)
  assert_eq(opening.open_outputs, base.open_outputs)
}

///|
test "originals-only Close retires inventory without resetting source panes" {
  let base = lifecycle_model()
  let inventory = @document.OriginalInventory::from_connected(
    Map([("model.yaml", b"formatVersion: 4\r\n")]),
    ["empty"],
    NotReported,
  ) catch {
    _ => abort("inventory")
  }
  let (opening, attempt) = match @document.State::new().begin(Idle) {
    Started(state, attempt) => (state, attempt)
    _ => abort("begin")
  }
  let document = opening.finish_originals(attempt, inventory) catch {
    _ => abort("retain")
  }
  let retained = {
    ..base,
    document,
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
  let (closed, _) = update(retained, CloseModel, quiet())
  assert_eq(closed.document.original_inventory(), None)
  assert_eq(closed.document.document(), None)
  assert_eq(closed.pane, retained.pane)
  assert_eq(closed.open_outputs, retained.open_outputs)
  assert_eq(closed.output, retained.output)
  assert_eq(closed.language_projects, retained.language_projects)
  assert_eq(closed.worksheet_source, retained.worksheet_source)
  assert_eq(closed.status, "Model closed")
}
