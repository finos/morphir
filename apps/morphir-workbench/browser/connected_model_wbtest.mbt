///|
fn connected_model_inventory() -> @document.OriginalInventory {
  @document.OriginalInventory::from_connected(
    Map::from_array([("original.yaml", b"\xef\xbb\xbf# source\r\n")]),
    ["empty"],
    Reported(@document.OriginalRelease::new(99U, 2U, 7U)),
  ) catch {
    _ => abort("bounded originals fixture")
  }
}

///|
fn pending_connected_model() -> (Model, @document.OpenAttempt) {
  let base = lifecycle_model()
  match base.document.begin(Idle) {
    Started(document, attempt) => ({ ..base, document, busy: true, }, attempt)
    _ => abort("genuine domain opening")
  }
}

///|
test "connected inspection stores both owners atomically and resets model selections" {
  let (before, attempt) = pending_connected_model()
  let inventory = connected_model_inventory()
  let reply : Json = {
    "success": true,
    "ir": { "formatVersion": 4, "module": "inspected projection" },
    "sourceFormatVersion": "4.0.0",
    "modelSource": {
      "kind": "semantic-projection",
      "reason": "originals-not-provided",
    },
  }
  let after = finish_connected_model(before, attempt, inventory, reply)
  assert_eq(field(after.document.inspection(), "ir"), field(reply, "ir"))
  assert_eq(text(after.document.inspection(), "sourceFormatVersion"), "4.0.0")
  assert_eq(after.document.original_inventory(), Some(inventory))
  assert_eq(
    after.document.original_inventory().unwrap().source_header,
    Reported(@document.OriginalRelease::new(99U, 2U, 7U)),
  )
  assert_eq(after.document.opening(), None)
  assert_eq(after.model_revision, before.model_revision + 1)
  assert_eq(after.query, "")
  assert_eq(after.selected, "")
  assert_eq(after.collapsed_modules, [])
  assert_false(after.busy)
  assert_true(after.originals is OriginalsReady(ProjectionInspected))
}

///|
test "connected typed refusal keeps previous model and discloses different originals" {
  let (before, attempt) = pending_connected_model()
  let inventory = connected_model_inventory()
  let after = finish_connected_model(before, attempt, inventory, {
    "success": false,
    "message": "Unsupported format version",
  })
  assert_eq(after.document.document(), before.document.document())
  assert_eq(
    after.document.current_revision(),
    before.document.current_revision(),
  )
  assert_eq(after.document.original_inventory(), Some(inventory))
  assert_eq(after.document.opening(), None)
  assert_eq(after.model_revision, before.model_revision)
  assert_eq(after.query, before.query)
  assert_true(after.originals is OriginalsReady(OriginalsOnly(_)))
  assert_true(after.status.contains("previous model"))
}

///|
test "stale connected result and retained host cannot replace model owners" {
  let (pending, attempt) = pending_connected_model()
  let (closed, _) = update(pending, CloseModel, quiet())
  assert_eq(
    finish_connected_model(
      closed,
      attempt,
      connected_model_inventory(),
      Json::null(),
    ).document,
    closed.document,
  )
  let blocked = { ..pending, host_submitting: true, }
  let refused = finish_connected_model(
    blocked,
    attempt,
    connected_model_inventory(),
    { "success": true, "ir": {} },
  )
  assert_eq(refused.document.document(), blocked.document.document())
  assert_eq(
    refused.document.original_inventory(),
    blocked.document.original_inventory(),
  )
}
