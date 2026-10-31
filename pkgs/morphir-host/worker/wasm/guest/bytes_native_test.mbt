///|
test "per-call budget: a runaway guest stops at its call deadline" {
  let guest = load(
    @fixtures.runaway_guest(),
    call=@guest.CallBounds::new(deadline_ms=200, instructions=None),
  )
  assert_eq(exchange(guest, b"{}"), "call-deadline")
}

///|
test "per-call budget: an exhausted instruction budget is not a deadline" {
  let guest = load(
    @fixtures.runaway_guest(),
    call=@guest.CallBounds::new(deadline_ms=10000, instructions=Some(100000)),
  )
  assert_eq(exchange(guest, b"{}"), "budget-exhausted")
}

///|
test "the native engine enforces the memory ceiling, the budget and the call deadline" {
  assert_eq(
    @guest.engine_bounds(),
    @worker.EnforcedBounds::new(
      memory_ceiling=Enforced,
      instruction_budget=Enforced,
      call_deadline=Enforced,
    ),
  )
}
