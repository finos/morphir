///|
test "throwing sink cannot replace a successful result or original failure" {
  let health = @observability.Health::new()
  let base : @observability.Observer = {
    enabled: fn() { true },
    try_record: fn(_) raise { raise @execution.Invalid("sink failed") },
    monotonic: fn() { 1.0 },
    wall: fn() { 2.0 },
    next_id: fn() { "0000000000000001" },
    run_id: "run",
    trace_id: "00000000000000000000000000000001",
    sequence: Ref(0),
  }
  let scope = base.isolated(health).scope()
  assert_eq(scope.observe(@observability.Build, fn(_) { 42 }), 42)
  let original = try {
    ignore(
      scope.observe(@observability.Invoke, fn(_) -> Unit raise {
        raise @execution.Invalid("driver failed")
      }),
    )
    false
  } catch {
    @execution.Invalid("driver failed") => true
    _ => false
  }
  assert_true(original)
  assert_eq(health.to_json(), {
    "accepted": 0,
    "filtered": 0,
    "dropped": 0,
    "unavailable": 4,
  })
}

///|
test "recursive logging is bounded and every rejected delivery is counted" {
  let health = @observability.Health::new()
  let observer : Ref[@observability.Observer?] = Ref(None)
  let base : @observability.Observer = {
    enabled: fn() { true },
    try_record: record => {
      assert_true(observer.val.unwrap().record(record) is Dropped)
      @observability.Accepted
    },
    monotonic: fn() { 1.0 },
    wall: fn() { 2.0 },
    next_id: fn() { "0000000000000001" },
    run_id: "run",
    trace_id: "00000000000000000000000000000001",
    sequence: Ref(0),
  }
  observer.val = Some(base.isolated(health))
  assert_eq(
    observer.val.unwrap().scope().observe(@observability.Build, fn(_) { 42 }),
    42,
  )
  assert_eq(health.to_json(), {
    "accepted": 2,
    "filtered": 0,
    "dropped": 2,
    "unavailable": 0,
  })
}
