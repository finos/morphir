///|
test "evaluation policy is explicit and does not affect generated execution" {
  assert_true(evaluation_policy("strict") is Strict)
  assert_true(evaluation_policy("permissive") is Permissive)
  assert_true(
    try {
      ignore(evaluation_policy("unchecked"))
      false
    } catch {
      _ => true
    },
  )
  let cli = parse_cli([
    "eval", "model.yaml", "--suite", "calls.ion", "--suite-format", "ion-text", "--checking-policy",
    "permissive", "--json",
  ])
  assert_eq(cli.command, "eval")
  assert_eq(value(cli, "checking-policy"), "permissive")
  assert_true(!render_help("execute").contains("--checking-policy"))
  assert_true(render_help("worksheet").contains("<file|->"))
}

///|
test "evaluation exit classification retains typed outcomes" {
  fn report(terminal : @protocol.TerminalOutcome) -> @protocol.Outcomes {
    {
      calls: [{ id: "call", outcome: terminal, }],
      cleanup: None,
      extensions: None,
    }
  }
  assert_eq(evaluation_status(report(Returned(Unit))), 0)
  assert_eq(evaluation_status(report(ModelError("division_by_zero"))), 1)
  assert_eq(
    evaluation_status(
      report(
        Failed({ stage: Evaluate, code: "scheme.limit", message: "Limit", }),
      ),
    ),
    1,
  )
  assert_eq(evaluation_status(report(Cancelled)), 130)
  assert_eq(evaluation_status(report(Cancelled), timed_out=true), 1)
}
