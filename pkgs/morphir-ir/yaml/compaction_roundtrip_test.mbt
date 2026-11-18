///|
test "classic orders stays typed-equal after whole-file compaction and expansion" {
  let files = Map(orders_v3_json())
  let expanded = Map(
    orders_v3_json().map(pair => {
      (pair.0, @wire.expand_names(@wire.compact_names(pair.1).written))
    }),
  )
  assert_eq(
    @yaml.read_tree_versioned(expanded),
    @yaml.read_tree_versioned(files),
  )
}

///|
test "v4 orders stays typed-equal after whole-file compaction and expansion" {
  let files = Map(orders_v4_json())
  let expanded = Map(
    orders_v4_json().map(pair => {
      (pair.0, @wire.expand_names(@wire.compact_names(pair.1).written))
    }),
  )
  assert_eq(
    @yaml.read_tree_versioned(expanded),
    @yaml.read_tree_versioned(files),
  )
}
