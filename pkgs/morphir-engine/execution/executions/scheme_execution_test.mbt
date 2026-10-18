///|
fn capability_execution_unit() -> @data.IRUnit raise {
  let original = unit()
  guard original.distribution.distribution is Library(_, _, definition) else {
    abort("library")
  }
  let module_definition = definition.modules[@ir.Path::parse("main")]
  let value_name = @ir.Name::parse("subtract")
  let definition = module_definition.value.values[value_name]
  guard definition.value.value is ExpressionBody(inputs, output, body) else {
    abort("expression")
  }
  module_definition.value.values[value_name] = {
    ..definition,
    value: {
      ..definition.value,
      value: @ir.ValueDefinition::ExpressionBody(
        inputs,
        output,
        @ir.Value::IfThenElse(
          @ir.ValueAttributes::default(),
          @ir.Value::Literal(
            @ir.ValueAttributes::default(),
            @ir.Literal::BoolLiteral(false),
          ),
          @ir.Value::Hole(
            @ir.ValueAttributes::default(),
            @ir.HoleReason::DeletedDuringRefactor("private"),
            Some(output),
          ),
          body,
        ),
      ),
    },
  }
  original
}

///|
test "Scheme execution accepts an explicitly selected reached-only policy" {
  let session = @host.Session::new(offer())
  let accepted = session.submit_scheme(
    capability_execution_unit(),
    suite(),
    policy=@execution.Permissive,
  )
  assert_eq(accepted.sequence(), 0)
}

///|
fn scheme_rejected(action : () -> Unit raise, code : String) -> Bool {
  try {
    action()
    false
  } catch {
    @host.Invalid(actual) => actual == code
    _ => false
  }
}

///|
fn claim_selected(
  session : @host.Session,
  identity : @receipts.Identity,
) -> @execution.SchemePlan raise {
  let selection = session.describe_scheme(identity)
  session.claim_scheme(
    identity,
    selection.plan_id,
    "scheme",
    selection.runtime,
    selection.policy,
  )
}

///|
test "Scheme executions capture policy source arguments and complete boundary independently" {
  let session = @host.Session::new(offer())
  let original = capability_execution_unit()
  let calls = suite()
  let accepted = session.submit_scheme(
    original,
    calls,
    policy=@execution.Permissive,
  )
  let identity = accepted.identity()
  let projection = session.describe_scheme(identity)
  assert_eq(projection.plan_id, "plan-1")
  assert_eq(projection.runtime, @host.Scheme)
  assert_eq(projection.policy, @execution.Permissive)
  calls.calls[0].arguments[0] = @protocol.Value::from_json({
    "type": "int",
    "value": "999",
  })
  calls.calls.clear()
  original.provenance.push(@protocol.Value::Unit.to_ion())
  if original.distribution.distribution is Library(_, _, definition) {
    definition.modules.clear()
  }
  projection.boundary.obj()["entries"] = []
  assert_true(
    session.describe_scheme(identity).boundary.obj()["entries"] is Array([_]),
  )
  let plan = claim_selected(session, identity)
  let mutable_suite = plan.suite()
  mutable_suite.calls[0].arguments[0] = @protocol.Value::from_json({
    "type": "int",
    "value": "500",
  })
  mutable_suite.calls.clear()
  let mutable_unit = plan.unit()
  if mutable_unit.distribution.distribution is Library(_, _, definition) {
    definition.modules.clear()
  }
  assert_true(plan.unit().provenance.is_empty())
  let outcomes = plan.evaluate_outcomes()
  assert_eq(outcomes.to_json(), returned().to_json())
  assert_true(
    rejected(() => {
      ignore(
        session.complete(
          identity,
          returned(value={ "type": "bool", "value": true }),
        ),
      )
    }),
  )
  let terminal = session.complete(identity, outcomes)
  outcomes.calls.clear()
  assert_eq(session.query(identity).to_json(), terminal.to_json())
  assert_eq(
    session.complete(identity, returned()).to_json(),
    terminal.to_json(),
  )
  assert_true(
    scheme_rejected(
      () => ignore(claim_selected(session, identity)),
      "workbench.host_already_claimed",
    ),
  )
}

///|
test "Scheme execution omission stays strict and mismatches never claim or downgrade" {
  let session = @host.Session::new(offer())
  let strict = session.submit_scheme(unit(), suite())
  let permissive = session.submit_scheme(
    capability_execution_unit(),
    suite(),
    policy=@execution.Permissive,
  )
  let selected = session.describe_scheme(strict.identity())
  assert_eq(selected.policy, @execution.Strict)
  assert_true(
    scheme_rejected(
      () => {
        ignore(
          session.claim_scheme(
            strict.identity(),
            selected.plan_id,
            "scheme",
            @host.Scheme,
            @execution.Permissive,
          ),
        )
      },
      "workbench.host_selection_mismatch",
    ),
  )
  assert_eq(session.query(strict.identity()).to_json(), strict.to_json())
  let selected = session.describe_scheme(permissive.identity())
  for
    (plan_id, provider, policy) in [
      ("plan-other", "scheme", @execution.Permissive),
      (selected.plan_id, "replacement", @execution.Permissive),
      (selected.plan_id, "scheme", @execution.Strict),
    ] {
    assert_true(
      scheme_rejected(
        () => {
          ignore(
            session.claim_scheme(
              permissive.identity(),
              plan_id,
              provider,
              @host.Scheme,
              policy,
            ),
          )
        },
        "workbench.host_selection_mismatch",
      ),
    )
    assert_true(
      scheme_rejected(
        () => {
          ignore(
            session.replan_scheme(
              permissive.identity(),
              plan_id,
              provider,
              @host.Scheme,
              policy,
            ),
          )
        },
        "workbench.host_selection_mismatch",
      ),
    )
  }
  assert_eq(
    session.query(permissive.identity()).to_json(),
    permissive.to_json(),
  )
  assert_eq(
    claim_selected(session, strict.identity()).policy(),
    @execution.Strict,
  )
  assert_eq(
    claim_selected(session, permissive.identity()).policy(),
    @execution.Permissive,
  )
  assert_true(
    rejected(() => {
      ignore(session.submit_scheme(capability_execution_unit(), suite()))
    }),
  )
}

///|
test "Scheme and legacy execution claims cannot cross execution routes" {
  let session = @host.Session::new(offer())
  let legacy = session.submit(unit(), suite())
  let selected = session.submit_scheme(unit(), suite())
  assert_true(
    scheme_rejected(
      () => ignore(session.describe_scheme(legacy.identity())),
      "workbench.host_execution_kind",
    ),
  )
  assert_true(
    scheme_rejected(
      () => {
        ignore(
          session.claim_scheme(
            legacy.identity(),
            "plan-1",
            "scheme",
            @host.Scheme,
            @execution.Strict,
          ),
        )
      },
      "workbench.host_execution_kind",
    ),
  )
  assert_true(
    scheme_rejected(
      () => ignore(session.claim(selected.identity())),
      "workbench.host_execution_kind",
    ),
  )
  assert_eq(session.query(legacy.identity()).to_json(), legacy.to_json())
  assert_eq(session.query(selected.identity()).to_json(), selected.to_json())
  ignore(session.claim(legacy.identity()))
  ignore(claim_selected(session, selected.identity()))
}

///|
test "Scheme replan preserves original acceptance and allocates independent identity" {
  let session = @host.Session::new(offer())
  let first = session.submit_scheme(
    capability_execution_unit(),
    suite(),
    policy=@execution.Permissive,
  )
  let selection = session.describe_scheme(first.identity())
  let second = session.replan_scheme(
    first.identity(),
    selection.plan_id,
    "scheme",
    selection.runtime,
    selection.policy,
  )
  let next_selection = session.describe_scheme(second.identity())
  assert_eq(next_selection.plan_id, "plan-2")
  assert_false(first.identity() == second.identity())
  assert_eq(next_selection.policy, selection.policy)
  assert_eq(next_selection.boundary, selection.boundary)
  assert_eq(session.query(first.identity()).to_json(), first.to_json())
  assert_eq(session.query(second.identity()).to_json(), second.to_json())
  let stale = second.identity().to_json().obj()
  stale["snapshotId"] = first.identity().to_json().obj()["snapshotId"]
  assert_true(
    scheme_rejected(
      () => {
        ignore(
          claim_selected(
            session,
            @receipts.Identity::from_json(Json::object(stale)),
          ),
        )
      },
      "workbench.host_unknown_execution",
    ),
  )
  assert_true(
    scheme_rejected(
      () => {
        ignore(
          session.claim_scheme(
            second.identity(),
            selection.plan_id,
            "scheme",
            @host.Scheme,
            selection.policy,
          ),
        )
      },
      "workbench.host_selection_mismatch",
    ),
  )
  for identity in [first.identity(), second.identity()] {
    let plan = claim_selected(session, identity)
    ignore(session.complete(identity, plan.evaluate_outcomes()))
    assert_true(
      scheme_rejected(
        () => ignore(claim_selected(session, identity)),
        "workbench.host_already_claimed",
      ),
    )
  }
  let terminal_before = session.query(first.identity()).to_json()
  let third = session.replan_scheme(
    first.identity(),
    selection.plan_id,
    "scheme",
    selection.runtime,
    selection.policy,
  )
  assert_eq(session.describe_scheme(third.identity()).plan_id, "plan-3")
  assert_eq(session.query(first.identity()).to_json(), terminal_before)
}

///|
test "Scheme cancellation and failed evidence keep separate validated terminals" {
  let session = @host.Session::new(offer())
  let accepted = session.submit_scheme(
    capability_execution_unit(),
    suite(),
    policy=@execution.Permissive,
  )
  ignore(session.cancel(accepted.identity()))
  let plan = claim_selected(session, accepted.identity())
  let outcomes = plan.evaluate_outcomes(cancelled=fn() { true })
  assert_true(outcomes.calls[0].outcome is Cancelled)
  let terminal = session.complete(accepted.identity(), outcomes)
  assert_true(terminal.cancel_requested())
  assert_eq(terminal.sequence(), 3)
  session.release(accepted.identity())
  assert_true(
    scheme_rejected(
      () => ignore(session.describe_scheme(accepted.identity())),
      "workbench.host_unknown_execution",
    ),
  )
  let accepted = session.submit_scheme(unit(), suite())
  let invalid_inventory = returned()
  invalid_inventory.calls.clear()
  assert_true(
    rejected(() => {
      ignore(session.complete(accepted.identity(), invalid_inventory))
    }),
  )
  assert_eq(session.query(accepted.identity()).to_json(), accepted.to_json())
}

///|
test "Scheme accepted boundary bytes count toward retained quota" {
  let source = unit()
  let calls = suite()
  let snapshot_size = match @data.Registry::new().checkpoint(source) {
    Binary(bytes) => bytes.length()
    _ => abort("binary")
  }
  let plan = @execution.plan_scheme_capabilities(source, calls)
  let base = snapshot_size + calls.encode("json").length() + 1024 * 1024
  let boundary_size = @utf8.encode(plan.boundary_json().stringify()).length()
  assert_true(boundary_size > 0)
  let session = @host.Session::new(offer(), max_bytes=base + boundary_size - 1)
  assert_true(
    scheme_rejected(
      () => ignore(session.submit_scheme(source, calls)),
      "workbench.host_capacity",
    ),
  )
  let legacy = session.submit(source, calls)
  assert_eq(legacy.identity().to_json().obj()["executionId"], "execution-1")
  let exact = @host.Session::new(offer(), max_bytes=base + boundary_size)
  ignore(exact.submit_scheme(source, calls))
}

///|
test "failed submission projection validation does not publish or consume an execution identity" {
  let session = @host.Session::new(offer())
  let rejected = scheme_rejected(
    fn() raise {
      ignore(
        session.submit_scheme(
          capability_execution_unit(),
          suite(),
          policy=@execution.Permissive,
          validate_projection=Some(fn(_, _) raise {
            raise @host.Invalid("workbench.native_projection_limit")
          }),
        ),
      )
    },
    "workbench.native_projection_limit",
  )
  assert_true(rejected)
  let accepted = session.submit_scheme(
    capability_execution_unit(),
    suite(),
    policy=@execution.Permissive,
    validate_projection=Some(fn(receipt, projection) raise {
      assert_true(receipt.identity() == projection.identity)
      assert_eq(projection.policy, @execution.Permissive)
    }),
  )
  assert_eq(accepted.identity().execution_id().to_string(), "execution-1")
  let retained = session.describe_scheme(accepted.identity())
  assert_eq(retained.policy, @execution.Permissive)
}

///|
test "reentrant projection validation cannot overwrite another accepted execution" {
  let session = @host.Session::new(offer())
  let nested : Ref[@receipts.Receipt?] = Ref(None)
  let rejected = scheme_rejected(
    fn() raise {
      ignore(
        session.submit_scheme(
          capability_execution_unit(),
          suite(),
          policy=@execution.Permissive,
          validate_projection=Some(fn(_, _) raise {
            nested.val = Some(session.submit_scheme(unit(), suite()))
          }),
        ),
      )
    },
    "workbench.host_submission_changed",
  )
  assert_true(rejected)
  guard nested.val is Some(accepted) else { abort("Nested accepted execution") }
  assert_eq(accepted.identity().execution_id().to_string(), "execution-1")
  let original = session.query(accepted.identity())
  assert_true(original.identity() == accepted.identity())
  let next = session.submit_scheme(
    capability_execution_unit(),
    suite(),
    policy=@execution.Permissive,
  )
  assert_eq(next.identity().execution_id().to_string(), "execution-2")
  assert_eq(session.query(accepted.identity()).to_json(), original.to_json())
}
