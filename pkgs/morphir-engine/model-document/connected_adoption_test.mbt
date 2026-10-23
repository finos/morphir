///|
/// Pure storage/lifecycle behavior only. The receiver owns protocol verification,
/// release and current selection checks before this transition is called.
test "connected adoption publishes semantic projection and exact originals together" {
  let (opening, attempt) = start(@document.State::new())
  let inventory = connected_inventory(
    header=Reported(@document.OriginalRelease::new(99U, 2U, 7U)),
  )
  let reply : Json = {
    "success": true,
    "ir": { "formatVersion": 4, "module": "actual-inspection-view" },
    "sourceFormatVersion": "4.0.0",
  }
  let adopted = opening.finish_connected(attempt, reply, inventory)
  assert_eq(adopted.opening(), None)
  assert_eq(adopted.inspection(), reply)
  assert_true(
    adopted.document().unwrap().source is Projection(OriginalsNotProvided),
  )
  assert_eq(adopted.original(), None)
  assert_eq(adopted.original_tree(), None)
  let semantic_revision = adopted.current_revision().unwrap()
  let inventory_revision = adopted.inventory_revision().unwrap()
  assert_eq(adopted.original_inventory_for(inventory_revision), Some(inventory))
  assert_eq(
    adopted.original_inventory().unwrap().source_header,
    Reported(@document.OriginalRelease::new(99U, 2U, 7U)),
  )
  assert_eq(
    adopted.original_inventory().unwrap().copy_files()["notes/opaque.bin"],
    b"\x00\xff\x01\x80",
  )
  // A consumed opening cannot publish a second semantic or inventory owner.
  let duplicate = adopted.finish_connected(
    attempt,
    Json::null(),
    connected_inventory(),
  )
  assert_eq(duplicate, adopted)
  assert_eq(duplicate.current_revision(), Some(semantic_revision))
  assert_eq(duplicate.inventory_revision(), Some(inventory_revision))
  let closed = match adopted.close(Idle) {
    Closed(state, None) => state
    _ => abort("connected semantic and inventory owners close together")
  }
  assert_eq(closed.document(), None)
  assert_eq(closed.original_inventory(), None)
  assert_eq(closed.current_revision(), None)
  assert_eq(closed.inventory_revision(), None)
}

///|
test "connected stale failed and refused openings retain both previous owners" {
  let (opening, attempt) = start(@document.State::new())
  let previous = opening.finish_connected(
    attempt,
    original_reply(name="semantic-A.json"),
    connected_inventory(),
  )
  let semantic_revision = previous.current_revision().unwrap()
  let inventory_revision = previous.inventory_revision().unwrap()
  let (pending, stale) = start(previous)
  let (newer, current) = start(pending.reject(stale))
  // Ignore stale input before decoding; it cannot consume either revision.
  assert_eq(
    newer.finish_connected(stale, Json::null(), connected_inventory()),
    newer,
  )
  assert_true(
    try {
      ignore(
        newer.finish_connected(current, Json::null(), connected_inventory()),
      )
      false
    } catch {
      @document.InvalidReply => true
      _ => false
    },
  )
  assert_eq(newer.opening(), Some(current))
  assert_eq(newer.document(), previous.document())
  assert_eq(newer.original_inventory(), previous.original_inventory())
  assert_eq(newer.current_revision(), Some(semantic_revision))
  assert_eq(newer.inventory_revision(), Some(inventory_revision))
  for host in [@document.Submitting, Running, Disconnected, UnknownSubmission] {
    match newer.begin(host) {
      Refused(actual) => assert_eq(actual, host)
      _ => abort("retained host refuses connected replacement")
    }
    match newer.close(host) {
      Retained(actual) => assert_eq(actual, host)
      _ => abort("retained host refuses connected close")
    }
    assert_eq(newer.document(), previous.document())
    assert_eq(newer.original_inventory(), previous.original_inventory())
  }
  let replacement_inventory = @document.OriginalInventory::from_connected(
    Map::from_array([("replacement.bin", b"\x00\xff")]),
    ["empty"],
    NotReported,
  )
  let replaced = newer.finish_connected(
    current,
    original_reply(name="semantic-B.json", encoded="AQID"),
    replacement_inventory,
  )
  assert_eq(original(replaced).filename.to_string(), "semantic-B.json")
  assert_true(replaced.current_revision() != Some(semantic_revision))
  assert_true(replaced.inventory_revision() != Some(inventory_revision))
  assert_eq(replaced.original_inventory_for(inventory_revision), None)
  assert_eq(replaced.original_for(semantic_revision), None)
  assert_eq(replaced.original_inventory(), Some(replacement_inventory))
  assert_eq(replaced.opening(), None)
  let closed = match newer.close(Idle) {
    Closed(state, Some(cancel)) => {
      assert_eq(cancel, current)
      state
    }
    _ => abort("pending connected opening closes with its same token")
  }
  assert_eq(
    closed.finish_connected(current, Json::null(), connected_inventory()),
    closed,
  )
}
