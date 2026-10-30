///|
fn expectations(n : String) -> @conformance.Expectations raise {
  @conformance.Expectations::decode(
    @utf8.encode(
      "{profile:\"morphir-conformance-v1\",version:\"test-v1\",provenance:\"5 minus 3 is 2, authored independently\",cases:[{id:\"subtract\",entry:\"calls:main#subtract\",arguments:[5,3],expected:" +
      n +
      "}]}",
    ),
  )
}

///|
fn provider(value : @protocol.Value) -> @execution.Provider {
  {
    targets: ["js"],
    acquire: fn() {
      {
        id: "memory",
        build: fn(_, _) { { "identity": "build" } },
        invoke: fn(_, _) {
          { values: [value], evidence: { "identity": "invoke" }, }
        },
        dispose: fn() { () },
      }
    },
  }
}

///|
test "independent expectation and live Scheme remain distinct evidence" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let report = @conformance.run(
    @conformance.prepare(plan, expected),
    provider(@protocol.Value::from_json({ "type": "int", "value": "2" })),
  )
  assert_true(report.successful())
  assert_eq(report.coverage.map(l => l.provider), ["independent", "scheme"])
  assert_eq(report.coverage[0].calls[0].status, "matched")
  assert_eq(report.coverage[1].calls[0].status, "matched")
  assert_eq(report.coverage[0].evidence, {
    "version": "test-v1",
    "provenance": "5 minus 3 is 2, authored independently",
  })
}

///|
test "shared wrong actual and evaluator cannot satisfy an independent expectation" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let wrong = @protocol.Value::from_json({ "type": "int", "value": "3" })
  let lane = @conformance.EvaluatorLane::{
    ..@conformance.EvaluatorLane::scheme(),
    evaluator: Some({
      profile: "injected-disagreement",
      evaluate: fn(_, _, _, _) { wrong },
    }),
  }
  let report = @conformance.run(
    @conformance.prepare(plan, expected, lanes=[lane]),
    provider(wrong),
  )
  assert_false(report.successful())
  assert_eq(report.coverage[1].calls[0].status, "matched")
  assert_eq(report.coverage[0].calls[0].status, "mismatch")
  assert_eq(report.coverage[0].calls[0].id, "subtract")
  assert_eq(report.coverage[0].calls[0].mismatch_path, Some(""))
}

///|
test "live evaluator disagreement fails even when independent expectations match" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let actual = @protocol.Value::from_json({ "type": "int", "value": "2" })
  let wrong = @protocol.Value::from_json({ "type": "int", "value": "3" })
  let lane = @conformance.EvaluatorLane::{
    ..@conformance.EvaluatorLane::scheme(),
    evaluator: Some({
      profile: "injected-disagreement",
      evaluate: fn(_, _, _, _) { wrong },
    }),
  }
  let report = @conformance.run(
    @conformance.prepare(plan, expected, lanes=[lane]),
    provider(actual),
  )
  assert_false(report.successful())
  assert_eq(report.coverage[0].calls[0].status, "matched")
  assert_eq(report.coverage[1].calls[0].status, "mismatch")
  assert_eq(report.coverage[1].calls[0].id, "subtract")
}

///|
test "missing and unsupported evaluator coverage never becomes a comparison" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let missing : @conformance.EvaluatorLane = {
    name: "rust",
    required: false,
    evaluator: None,
    unsupported: fn(_, _) { None },
    evidence: { "reason": "missing_binary" },
  }
  let actual = @protocol.Value::from_json({ "type": "int", "value": "2" })
  let report = @conformance.run(
    @conformance.prepare(plan, expected, lanes=[
      @conformance.EvaluatorLane::scheme(),
      missing,
    ]),
    provider(actual),
  )
  assert_true(report.successful())
  assert_eq(report.coverage[2].calls[0].status, "unavailable")
  assert_eq(report.coverage[2].calls[0].expected, None)
  assert_true(report.to_json().stringify().contains("\"matches\":null"))
  let required = { ..missing, required: true, }
  assert_true(
    try {
      ignore(@conformance.prepare(plan, expected, lanes=[required]))
      false
    } catch {
      @protocol.Invalid(code) => code.contains("evaluator_unavailable")
      _ => false
    },
  )
  let unsupported = {
    ..@conformance.EvaluatorLane::scheme(),
    required: true,
    unsupported: fn(_, _) { Some("unsupported_type") },
  }
  assert_true(
    try {
      ignore(@conformance.prepare(plan, expected, lanes=[unsupported]))
      false
    } catch {
      @protocol.Invalid(code) =>
        code.contains("evaluator_unsupported") && code.contains("subtract")
      _ => false
    },
  )
}

///|
test "deterministic observers preserve outcomes and required evidence" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let plan = @conformance.prepare(plan, expected)
  let actual = @protocol.Value::from_json({ "type": "int", "value": "2" })
  let records : Array[@observe.Observation] = []
  let clock = Ref(0.0)
  let next = Ref(0)
  let observer : @observe.Observer = {
    enabled: fn() { true },
    try_record: fn(r) {
      records.push(r)
      @observe.Accepted
    },
    monotonic: fn() {
      clock.val += 0.001
      clock.val
    },
    wall: fn() { 1000.0 },
    next_id: fn() {
      next.val += 1
      let hex = next.val.to_string(radix=16)
      "0000000000000000"[:16 - hex.length()].to_owned() + hex
    },
    run_id: "run",
    trace_id: "11111111111111111111111111111111",
    sequence: Ref(0),
  }
  let quiet = @conformance.run(plan, provider(actual))
  let observed = @conformance.run(plan, provider(actual), observer~)
  assert_eq(quiet.to_json(), observed.to_json())
  assert_true(records.length() > 0)
  for started in records.filter(r => r.signal is Started) {
    assert_eq(
      records
      .filter(r => {
        r.context.span_id == started.context.span_id &&
        (r.signal is Succeeded || r.signal is Failed || r.signal is Cancelled)
      })
      .length(),
      1,
    )
  }
}

///|
test "unsupported callbacks cannot mutate a model and skip the last comparison" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let lane : @conformance.EvaluatorLane = {
    ..@conformance.EvaluatorLane::scheme(),
    required: false,
    unsupported: fn(plan, _) {
      plan.driver.push(plan.driver[0])
      Some("unsupported")
    },
  }
  assert_true(
    try {
      ignore(
        @conformance.run(
          @conformance.prepare(plan, expected, lanes=[lane]),
          provider(@protocol.Value::from_json({ "type": "int", "value": "2" })),
        ),
      )
      false
    } catch {
      @protocol.Invalid(code) => code == "conformance.input_mutation"
      _ => false
    },
  )
}

///|
test "independent nested disagreement reports the precise field" {
  let actual = @protocol.Value::from_json({
    "type": "record",
    "fields": [
      {
        "name": "price",
        "value": { "type": "decimal", "coefficient": "425", "exponent": -2 },
      },
      { "name": "quantity", "value": { "type": "int", "value": "3" } },
    ],
  })
  let wrong = @protocol.Value::from_json({
    "type": "record",
    "fields": [
      {
        "name": "price",
        "value": { "type": "decimal", "coefficient": "426", "exponent": -2 },
      },
      { "name": "quantity", "value": { "type": "int", "value": "3" } },
    ],
  })
  let expected : @conformance.Expectations = {
    version: "test-v1",
    provenance: "Direct record reduction",
    cases: [
      {
        call: {
          id: "record-update",
          entry: "pricing:quotes#reprice",
          arguments: [
            actual,
            @protocol.Value::from_json({
              "type": "decimal",
              "coefficient": "425",
              "exponent": -2,
            }),
          ],
        },
        expected: wrong,
      },
    ],
  }
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.pricing()),
    expected.suite(),
  )
  let report = @conformance.run(
    @conformance.prepare(plan, expected),
    provider(actual),
  )
  assert_false(report.successful())
  assert_eq(report.coverage[0].calls[0].id, "record-update")
  assert_eq(report.coverage[0].calls[0].mismatch_path, Some("/price"))
  assert_eq(report.coverage[1].calls[0].status, "matched")
}

///|
test "expectation provenance and profile are mandatory" {
  let expected = expectations("2")
  for invalid in [{ ..expected, version: "", }, { ..expected, provenance: "", }] {
    assert_true(
      try {
        invalid.validate()
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        @conformance.Expectations::decode(
          @utf8.encode(
            "{profile:\"future\",version:\"1\",provenance:\"hand\",cases:[]}",
          ),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "explicit JSON expectation codec preserves rich typed values" {
  let values = [
    @protocol.Value::from_json({ "type": "int", "value": "9007199254740993" }),
    @protocol.Value::from_json({
      "type": "decimal",
      "coefficient": "12345678901234567890123456789",
      "exponent": -32,
    }),
    @protocol.Float64(9221120237041090626UL),
    @protocol.Text([0, 55296, 65, 57343]),
    @protocol.Unit,
  ]
  let expected : @conformance.Expectations = {
    version: "json-v1",
    provenance: "Authored codec edge cases",
    cases: values.map(v => {
      call: { id: "codec", entry: "codec:main#identity", arguments: [v], },
      expected: v,
    }),
  }
  // Each suite needs unique call identities; the semantic DTO is independent
  // of the generated model and accepts JSON only as an explicit opt-out.
  let expected = {
    ..expected,
    cases: expected.cases.mapi((i, c) => {
      ..c,
      call: { ..c.call, id: "codec-" + i.to_string(), },
    }),
  }
  let json = expected.to_json().stringify()
  let decoded = @conformance.Expectations::decode(
    @utf8.encode(json),
    format="json",
  )
  assert_eq(decoded.to_json(), expected.to_json())
  assert_true(
    try {
      ignore(
        @conformance.Expectations::decode(
          @utf8.encode(
            "{profile:\"morphir-conformance-v1\",version:\"1\",provenance:\"hand\",cases:[]}",
          ),
          format="json",
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "partial and duplicate coverage cannot satisfy required evidence" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let report = @conformance.run(
    @conformance.prepare(plan, expected),
    provider(@protocol.Value::from_json({ "type": "int", "value": "2" })),
  )
  assert_true(report.successful())
  assert_false(
    @conformance.Report::{ ..report, coverage: [report.coverage[1]], }.successful(),
  )
  assert_false(
    @conformance.Report::{
      ..report,
      coverage: [report.coverage[0], report.coverage[1], report.coverage[1]],
    }.successful(),
  )
  // Simulate a complete two-call execution with a truncated comparison lane.
  report.execution.calls.push({ ..report.execution.calls[0], id: "second", })
  report.execution.terminals.push({ id: "second", status: "succeeded", })
  assert_true(report.execution.successful())
  assert_false(report.successful())
}

///|
test "generated cancellation remains distinct and avoids acquisition" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let acquired = Ref(0)
  let base = provider(
    @protocol.Value::from_json({ "type": "int", "value": "2" }),
  )
  let cancelled_provider = {
    ..base,
    acquire: fn() raise {
      acquired.val += 1
      (base.acquire)()
    },
  }
  let report = @conformance.run(
    @conformance.prepare(plan, expected),
    cancelled_provider,
    cancelled=fn() { true },
  )
  assert_true(report.cancelled())
  assert_false(report.successful())
  assert_eq(acquired.val, 0)
  assert_eq(report.coverage[0].calls[0].status, "cancelled")
  assert_eq(report.coverage[1].calls[0].status, "cancelled")
}

///|
test "cancellation during the final evaluator cannot turn into a match" {
  let expected = expectations("2")
  let plan = @execution.plan(
    @data.IRUnit::new("model", @fixtures.invocation_library()),
    expected.suite(),
  )
  let cancelled = Ref(false)
  let actual = @protocol.Value::from_json({ "type": "int", "value": "2" })
  let lane = @conformance.EvaluatorLane::{
    ..@conformance.EvaluatorLane::scheme(),
    evaluator: Some({
      profile: "cancellation-test",
      evaluate: fn(_, _, _, _) {
        cancelled.val = true
        actual
      },
    }),
  }
  let report = @conformance.run(
    @conformance.prepare(plan, expected, lanes=[lane]),
    provider(actual),
    cancelled=fn() { cancelled.val },
  )
  assert_true(report.execution.successful())
  assert_eq(report.coverage[0].calls[0].status, "matched")
  assert_eq(report.coverage[1].calls[0].status, "cancelled")
  assert_eq(report.coverage[1].calls[0].expected, None)
  assert_true(report.cancelled())
  assert_false(report.successful())
}

///|
test "cancellation before provider discovery retains all conformance coverage" {
  let expected = expectations("2")
  let plan = @conformance.prepare(
    @execution.plan(
      @data.IRUnit::new("model", @fixtures.invocation_library()),
      expected.suite(),
    ),
    expected,
  )
  let ordinary = @conformance.run(
    plan,
    provider(@protocol.Value::from_json({ "type": "int", "value": "2" })),
    cancelled=() => true,
  )
  let stopped = @conformance.cancelled_report(plan)
  assert_eq(stopped.to_json(), ordinary.to_json())
  assert_true(stopped.cancelled())
  assert_true(
    stopped.coverage.all(lane => {
      lane.calls.all(call => call.status == "cancelled")
    }),
  )
}
