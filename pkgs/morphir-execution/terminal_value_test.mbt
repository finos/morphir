///|
test "standalone terminal codec preserves existing success and failure shapes" {
  let terminals : Array[Json] = [
    { "status": "returned", "value": { "type": "unit" } },
    { "status": "cancelled" },
    { "status": "model-error", "code": "sdk.division_by_zero" },
    {
      "status": "failed",
      "failure": {
        "stage": "evaluate",
        "code": "fixture.failed",
        "message": "Expected failure",
      },
    },
  ]
  for terminal in terminals {
    assert_eq(
      @execution.TerminalOutcome::from_json(terminal).to_json(),
      terminal,
    )
  }
  let rejected = try {
    @execution.TerminalOutcome::from_json({
      "status": "returned",
      "value": { "type": "model-error", "code": "sdk.division_by_zero" },
    })
    |> ignore
    false
  } catch {
    @execution.Invalid("workbench.invalid_outcome") => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "aggregate value budget is shared and failed acceptance is atomic" {
  let initial = @execution.ValueBudget::new()
  let full = initial.accept(@execution.Text(Array::make(99999, 65)))
  let exceeded = try {
    full.accept(@execution.Unit) |> ignore
    false
  } catch {
    @execution.Invalid("execution.value_limit") => true
    _ => false
  }
  assert_true(exceeded)
  // The original immutable budget remains usable after another budget fills.
  initial.accept(@execution.Unit) |> ignore
}
