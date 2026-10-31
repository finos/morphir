///|
test "runaway Extism guest: the call stops at its deadline" {
  let (guest, _) = load_extism(
    @fixtures.extism_runaway_guest(),
    call=@guest.CallBounds::new(deadline_ms=200, instructions=None),
  )
  assert_eq(exchange(guest, request(1)), "call-deadline")
}

///|
test "Extism guest: an exhausted budget is budget_exhausted" {
  let (guest, _) = load_extism(
    @fixtures.extism_runaway_guest(),
    call=@guest.CallBounds::new(deadline_ms=10000, instructions=Some(100000)),
  )
  assert_eq(exchange(guest, request(1)), "budget-exhausted")
}
