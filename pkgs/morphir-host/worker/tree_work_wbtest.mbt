///|
// Independent loop tally for the landed Orders guest. It does not call the
// production charge model, read model files, or allocate payload documents.
fn reference_orders_work(modules : Int32) -> Int64 {
  let m = modules.to_int64()
  let documents = 67L * m + 3L
  let entries = 68L * m + 11L
  let directories = m + 8L
  let root_pages = (m + 16L) / 16L
  let main_pages = (m + 15L) / 16L
  let deliveries = 77L * m + root_pages
  let mut charged = 2L * (entries + documents + directories + 1L)
  charged += 2L * deliveries + 1L // generate loop and delivery dispatch
  for _ in 0..<modules {
    charged += 67L + 65L // document delivery and artifact chunks
    charged += 67L // resolve_member reloads each owning module
    charged += 1L // the type delivery scans its one listed type
    for _ in 0..<66 {
      charged += 65L // every value delivery scans the whole values listing
    }
    for pass in 0..<2 {
      for page in 0..<5 {
        charged += 1L + 66L // module load plus full members scan
        let emitted = if page < 4 { 16L } else { 2L }
        charged += emitted // TreeView emits this page
        if pass == 0 {
          charged += emitted
        } // unique admitted documents
        if page < 4 {
          charged += 1L
        } // retained continuation cursor
      }
    }
  }
  charged += 3L * (m + 1L) // root module loads, emitted rows and admission
  charged += main_pages + 1L + root_pages - 1L // package visits, cursors
  // All root lower/upper-bound callbacks, with the real binary search loop.
  let search = rank => {
    let mut low = 0
    let mut high = modules + 1
    let mut count = 0L
    while low < high {
      count += 1L
      let middle = low + (high - low) / 2
      if middle < rank {
        low = middle + 1
      } else {
        high = middle
      }
    }
    count
  }
  for rank in 1..<(modules + 2) {
    charged += search(rank)
  }
  for last = 16; last < modules; last = last + 16 {
    charged += search(last + 1) // the page lookahead is reopened next page
  }
  charged += search(0) + search(1) // SDK module and end of its prefix
  // Each artifact is 1,065,025 bytes: 17 verification blocks per file.
  charged += m + 1L + m + 17L * m
  charged
}

///|
test "Orders derived work covers exact A and B charged loops and exact budget boundary" {
  for
    (profile, modules, value_scans, exact, ceiling, old_ceiling) in [
      (
        TreeGenerationProfile::OrdersScaleA,
        1024,
        4392960L,
        5964752L,
        5965836L,
        3672788L,
      ),
      (
        TreeGenerationProfile::OrdersScaleB,
        2048,
        8785920L,
        11931602L,
        11933774L,
        7345366L,
      ),
    ] {
    let model = OrdersScaleWork::for_modules(modules)
    assert_eq(model.member_value_scans, value_scans)
    assert_eq(model.total(), ceiling)
    let reference = reference_orders_work(modules)
    assert_eq(reference, exact)
    assert_true(value_scans > old_ceiling)
    assert_true(reference <= ceiling)
    println(
      "Orders charge control modules=\{modules} reference=\{reference} ceiling=\{ceiling} valueScans=\{value_scans}",
    )
    let budget = TreeBudget::from_limits(profile.admission().support.limits)
    assert_eq(budget.work, ceiling)
    let work = Ref(0L)
    charge_tree_work(work, budget.work, ceiling, () => ())
    assert_eq(work.val, ceiling)
    let refused = try {
      charge_tree_work(work, budget.work, 1L, () => ())
      false
    } catch {
      TreeSource(_) => true
      error => raise error
    }
    assert_true(refused)
    assert_eq(work.val, ceiling)
  }
  let standard = TreeBudget::from_limits(
    TreeGenerationProfile::Standard.admission().support.limits,
  )
  assert_eq(standard.work, 65536L)
}

///|
test "Orders verification reserves rounded blocks for every file" {
  with_capture_test_root((path, _directory) => {
    let stage = TreeStage::open(path + "/out", "verification-blocks")
    defer stage.dispose()
    let budget = TreeBudget::from_limits(tree_support().limits)
    stage.write(test_tree_chunk("orders/a.txt", b"a"), budget, 0L)
    stage.write(test_tree_chunk("orders/b.txt", b"b"), budget, 0L)
    assert_eq(stage.verification_work(), 7L) // 3 paths + 2 files + 2 blocks
  })
}

///|
test "Orders work tally reconciles the retained tiny receipt without treating it as scale clearance" {
  // Old receipt: 3 modules, 204 documents, 4097 entries, 232 deliveries,
  // 25,226 units. Padding added 4097-215 entries to each capture walk.
  // Its three sub-64-KiB outputs cost 8 under aggregate rounding, now 10.
  // Production-sized files add 16 blocks per file without changing delivery
  // charges, since all input documents and chunks still fit one 64 KiB unit.
  let exact_tiny = reference_orders_work(3) + 2L * (4097L - 215L) - 3L * 16L
  assert_eq(exact_tiny, 25228L)
  assert_eq(exact_tiny, 25226L + 2L)
}
