///|
/// Seed otherwise unreachable counter boundaries without changing the public
/// API or iterating billions of genuine opening transitions.
fn connected_boundary_state(
  revision : Int32,
  inventory_sequence : Int32,
) -> (State, OpenAttempt) {
  let inventory = OriginalInventory::from_connected(
    Map::from_array([("retained.bin", b"\x00\xff")]),
    ["retained-empty"],
    NotReported,
  ) catch {
    _ => abort("bounded connected inventory")
  }
  let retained = Phase::Retained(
    Both(
      {
        document: Document::from_reply({ "ir": { "previous": true } }) catch {
          _ => abort("literal retained semantic view")
        },
        revision: DocumentRevision(revision),
      },
      { inventory, revision: InventoryRevision(inventory_sequence), },
    ),
  )
  let state = { sequence: 4, revision, inventory_sequence, phase: retained, }
  match state.begin(Idle) {
    Started(state, attempt) => (state, attempt)
    _ => abort("boundary seed must start a genuine opening")
  }
}

///|
test "connected adoption checks each independent revision before publishing either owner" {
  let inventory = OriginalInventory::from_connected(
    Map::from_array([("next.bin", b"next")]),
    [],
    NotReported,
  )
  for (semantic, originals) in [(2147483647, 9), (9, 2147483647)] {
    let (opening, attempt) = connected_boundary_state(semantic, originals)
    assert_true(
      try {
        ignore(opening.finish_connected(attempt, Json::null(), inventory))
        false
      } catch {
        RevisionLimit => true
        _ => false
      },
    )
    assert_eq(opening.current_revision(), Some(DocumentRevision(semantic)))
    assert_eq(opening.inventory_revision(), Some(InventoryRevision(originals)))
    assert_eq(opening.opening(), Some(attempt))
    assert_eq(
      opening.original_inventory().unwrap().copy_files()["retained.bin"],
      b"\x00\xff",
    )
    // Staleness takes precedence even at a revision boundary.
    assert_eq(
      opening.finish_connected(OpenAttempt(3), Json::null(), inventory),
      opening,
    )
  }
  for (semantic, originals) in [(2147483646, 9), (9, 2147483646)] {
    let (opening, attempt) = connected_boundary_state(semantic, originals)
    let next = opening.finish_connected(
      attempt,
      { "ir": { "next": true } },
      inventory,
    )
    assert_eq(next.current_revision(), Some(DocumentRevision(semantic + 1)))
    assert_eq(next.inventory_revision(), Some(InventoryRevision(originals + 1)))
    assert_eq(next.original_inventory(), Some(inventory))
    assert_eq(next.opening(), None)
    let (pending, token) = match next.begin(Idle) {
      Started(state, token) => (state, token)
      _ => abort("opening sequence independent of revision counters")
    }
    assert_true(
      try {
        ignore(pending.finish_connected(token, { "ir": {} }, inventory))
        false
      } catch {
        RevisionLimit => true
        _ => false
      },
    )
    assert_eq(pending.document(), next.document())
    assert_eq(pending.original_inventory(), next.original_inventory())
  }
}
