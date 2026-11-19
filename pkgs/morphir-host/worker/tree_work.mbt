///|
// Charged work for the canonical Orders recipe/guest, not CPU instructions.
// M generated modules have 1 type and 65 listed values. The guest delivers
// 1 type + 66 values and makes two five-page member-inventory traversals.
// Keep each charged loop separate so changing that implementation requires
// revisiting its allowance. No fileNames overrides occur in this recipe.
priv struct OrdersScaleWork {
  capture : Int64
  exchange : Int64
  document_delivery : Int64
  artifact_write : Int64
  member_module_loads : Int64
  member_type_scans : Int64
  member_value_scans : Int64
  member_inventory : Int64
  root_inventory : Int64
  root_search : Int64
  verification : Int64
}

///|
fn OrdersScaleWork::total(self : OrdersScaleWork) -> Int64 {
  self.capture +
  self.exchange +
  self.document_delivery +
  self.artifact_write +
  self.member_module_loads +
  self.member_type_scans +
  self.member_value_scans +
  self.member_inventory +
  self.root_inventory +
  self.root_search +
  self.verification
}

///|
fn tree_verification_blocks(bytes : Int64) -> Int64 {
  bytes / 65536L + (if bytes % 65536L == 0L { 0L } else { 1L })
}

///|
fn OrdersScaleWork::for_modules(modules : Int32) -> OrdersScaleWork {
  // Only the closed A/B profiles and bounded unit controls call this helper.
  guard modules > 0 && modules <= 2048 else {
    abort("Orders work dimensions must be between 1 and 2048 modules")
  }
  let m = modules.to_int64()
  let documents = 67L * m + 3L
  let entries = 68L * m + 11L
  let directories = m + 8L
  let main_pages = (m + 15L) / 16L
  let root_pages = (m + 16L) / 16L // generated modules plus the SDK module
  let deliveries = 77L * m + root_pages
  // next_module searches the global sorted M+1-module array. Each main page
  // has a lookahead; there are also the two SDK-prefix callbacks. A binary
  // search needs at most ceil(log2(M+2)) comparisons per callback.
  let mut width = 1
  let mut levels = 0L
  while width < modules + 2 {
    width *= 2
    levels += 1L
  }
  {
    capture: 2L * (entries + documents + directories + 1L),
    exchange: 2L * deliveries + 1L,
    document_delivery: 67L * m,
    artifact_write: 65L * m,
    member_module_loads: 67L * m,
    member_type_scans: m,
    member_value_scans: 66L * 65L * m,
    // Ten load_module+members scans, 132 emitted rows, 66 first admissions
    // and eight continuation cursors for each generated module.
    member_inventory: (10L * (1L + 66L) + 132L + 66L + 8L) * m,
    // Module loads + emitted/admitted root rows, package visits and cursors.
    root_inventory: 3L * (m + 1L) + (main_pages + 1L) + (root_pages - 1L),
    root_search: (m + main_pages + 2L) * levels,
    // Directory-entry scan, per-file bookkeeping and per-file rounded blocks.
    verification: m + 1L + m + m * tree_verification_blocks(1065025L),
  }
}
