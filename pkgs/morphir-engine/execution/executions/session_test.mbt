///|
fn offer(cancel~ : Bool = true) -> @receipts.Offer raise {
  @receipts.Offer::from_json({
    "profile": "morphir/workbench/executions",
    "contractVersion": "0.2.0-draft.1",
    "hostId": "host",
    "sessionId": "session",
    "providerId": "scheme",
    "operations": Json::array(
      if cancel {
        [Json::string("query"), Json::string("cancel")]
      } else {
        [Json::string("query")]
      },
    ),
  })
}

///|
fn unit() -> @data.IRUnit raise {
  @data.IRUnit::new("test", @fixtures.invocation_library())
}

///|
fn suite() -> @protocol.Suite raise {
  @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "subtract",
        "entry": "calls:main#subtract",
        "arguments": [
          { "type": "int", "value": "45" },
          { "type": "int", "value": "3" },
        ],
      },
    ],
  })
}

///|
fn returned(
  value~ : Json = { "type": "int", "value": "42" },
) -> @protocol.Outcomes raise {
  @protocol.Outcomes::from_json({
    "contractVersion": "0.1.0-draft.5",
    "calls": [
      { "id": "subtract", "outcome": { "status": "returned", "value": value } },
    ],
    "cleanup": null,
    "extensions": null,
  })
}

///|
fn rejected(action : () -> Unit raise) -> Bool {
  try {
    action()
    false
  } catch {
    _ => true
  }
}

///|
fn Json::obj(self : Json) -> Map[String, Json] {
  match self {
    Object(fields) => fields
    _ => abort("expected object")
  }
}

///|
test "host snapshots own suite and IR and feed actual evaluator output" {
  let session = @host.Session::new(offer())
  let original = unit()
  let calls = suite()
  let submitted = session.submit(original, calls)
  let identity = submitted.identity()
  let client = @receipts.Cursor::start(
    offer(),
    identity,
    ["subtract"],
    submitted,
  )
  calls.calls[0].arguments[0] = @protocol.Value::from_json({
    "type": "int",
    "value": "999",
  })
  original.provenance.push(@protocol.Value::Unit.to_ion())
  if original.distribution.distribution is Library(_, _, definition) {
    definition.modules.clear()
  }
  let plan = session.claim(identity)
  assert_true(plan.unit.provenance.is_empty())
  let call = plan.suite.calls[0]
  let entry = plan.library.invocations.filter(e => e.fqname == call.entry)[0]
  let value = (@execution.Evaluator::scheme().evaluate)(
    plan.unit,
    call,
    entry.output,
    plan.library.invocation_types,
  )
  assert_eq(value.to_json(), { "type": "int", "value": "42" })
  ignore(session.complete(identity, returned(value=value.to_json())))
  let (client, _) = client.observe(session.query(identity))
  assert_true(client.latest().state() is Terminal(_))
  assert_eq(client.latest().sequence(), 2)
  assert_true(rejected(() => ignore(session.claim(identity))))
}

///|
test "cancel acknowledgement is idempotent and returned data wins the race" {
  let session = @host.Session::new(offer())
  let first = session.submit(unit(), suite())
  let identity = first.identity()
  let cancelled = session.cancel(identity)
  assert_true(cancelled.state() is Submitted)
  assert_true(cancelled.cancel_requested())
  assert_eq(cancelled.sequence(), 1)
  assert_eq(session.cancel(identity).to_json(), cancelled.to_json())
  ignore(session.claim(identity))
  let terminal = session.complete(identity, returned())
  assert_eq(terminal.sequence(), 3)
  assert_true(terminal.cancel_requested())
  assert_true(terminal.state() is Terminal(_))
  assert_eq(session.cancel(identity).to_json(), terminal.to_json())
  assert_eq(
    session.complete(identity, returned()).to_json(),
    terminal.to_json(),
  )
  assert_true(
    rejected(() => {
      ignore(
        session.complete(
          identity,
          returned(value={ "type": "int", "value": "7" }),
        ),
      )
    }),
  )
  assert_eq(session.query(identity).to_json(), terminal.to_json())
}

///|
test "every identity dimension is required for every host operation" {
  let session = @host.Session::new(offer())
  let first = session.submit(unit(), suite())
  for key in ["hostId", "sessionId", "providerId", "executionId", "snapshotId"] {
    let fields = first.identity().to_json().obj()
    fields[key] = "other"
    let wrong = @receipts.Identity::from_json(Json::object(fields))
    assert_true(rejected(() => ignore(session.query(wrong))))
    assert_true(rejected(() => ignore(session.cancel(wrong))))
    assert_true(rejected(() => ignore(session.claim(wrong))))
    assert_true(rejected(() => ignore(session.complete(wrong, returned()))))
    assert_true(rejected(() => session.release(wrong)))
  }
  assert_eq(session.query(first.identity()).to_json(), first.to_json())
}

///|
test "rejected terminal types and inventory never change authoritative state" {
  let session = @host.Session::new(offer())
  let first = session.submit(unit(), suite())
  let identity = first.identity()
  ignore(session.claim(identity))
  let before = session.query(identity).to_json()
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
  let wrong = returned()
  wrong.calls[0] = { ..wrong.calls[0], id: "other", }
  assert_true(rejected(() => ignore(session.complete(identity, wrong))))
  assert_eq(session.query(identity).to_json(), before)
  ignore(session.complete(identity, returned()))
}

///|
test "bounded retention refuses silent eviction and terminal release never reuses IDs" {
  let session = @host.Session::new(offer(), max_executions=1)
  let first = session.submit(unit(), suite())
  assert_true(rejected(() => ignore(session.submit(unit(), suite()))))
  assert_true(rejected(() => session.release(first.identity())))
  assert_eq(session.query(first.identity()).to_json(), first.to_json())
  ignore(session.complete(first.identity(), returned()))
  session.release(first.identity())
  assert_true(rejected(() => ignore(session.query(first.identity()))))
  let next = session.submit(unit(), suite())
  assert_false(next.identity() == first.identity())
  assert_eq(next.sequence(), 0)
}

///|
test "query-only hosts refuse cancellation and claim execution once" {
  let session = @host.Session::new(offer(cancel=false))
  let first = session.submit(unit(), suite())
  assert_true(rejected(() => ignore(session.cancel(first.identity()))))
  ignore(session.claim(first.identity()))
  let running = session.query(first.identity())
  assert_eq(running.sequence(), 1)
  assert_true(rejected(() => ignore(session.claim(first.identity()))))
  assert_eq(session.query(first.identity()).to_json(), running.to_json())
}

///|
test "receipt and claimed manifest mutations cannot change retained admission" {
  let session = @host.Session::new(offer())
  let first = session.submit(unit(), suite())
  let identity = first.identity()
  let plan = session.claim(identity)
  plan.library.invocations.clear()
  plan.suite.calls[0].arguments.clear()
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
  let terminal = session.complete(identity, returned())
  if terminal.state() is Terminal(outcomes) {
    outcomes.calls.clear()
  }
  let retained = session.query(identity)
  assert_true(
    retained.state() is Terminal(outcomes) && outcomes.calls.length() == 1,
  )
  let replacement = returned()
  ignore(session.complete(identity, replacement))
  replacement.calls.clear()
  assert_eq(session.query(identity).to_json(), retained.to_json())
}

///|
test "retention reserves terminal space and rejected submissions consume no IDs" {
  let source = unit()
  let calls = suite()
  let snapshot_size = match @data.Registry::new().checkpoint(source) {
    Binary(bytes) => bytes.length()
    _ => 0
  }
  let reserved = snapshot_size + calls.encode("json").length() + 1024 * 1024
  let session = @host.Session::new(offer(), max_bytes=reserved * 2 - 1)
  let first = session.submit(source, calls)
  assert_true(rejected(() => ignore(session.submit(source, calls))))
  ignore(session.complete(first.identity(), returned()))
  assert_true(rejected(() => ignore(session.submit(source, calls))))
  session.release(first.identity())
  let second = session.submit(source, calls)
  assert_eq(
    second.identity().to_json().obj()["executionId"],
    Json::string("execution-2"),
  )
  assert_eq(
    second.identity().to_json().obj()["snapshotId"],
    Json::string("snapshot-2"),
  )
  for
    (max_executions, max_bytes) in [
      (0, reserved),
      (65, reserved),
      (1, 1048575),
      (1, 67108865),
    ] {
    assert_true(
      rejected(() => {
        ignore(@host.Session::new(offer(), max_executions~, max_bytes~))
      }),
    )
  }
}

///|
test "rejected invocation admission leaves ownership and capacity unchanged" {
  let session = @host.Session::new(offer(), max_executions=1)
  for entry in ["calls:main#private", "calls:main#missing"] {
    let invalid = suite()
    invalid.calls[0] = { ..invalid.calls[0], entry, }
    assert_true(rejected(() => ignore(session.submit(unit(), invalid))))
  }
  let invalid = suite()
  invalid.calls[0].arguments.clear()
  assert_true(rejected(() => ignore(session.submit(unit(), invalid))))
  let first = session.submit(unit(), suite())
  assert_eq(
    first.identity().to_json().obj()["executionId"],
    Json::string("execution-1"),
  )
  assert_eq(session.query(first.identity()).to_json(), first.to_json())
}

///|
test "explicit cancellation and cleanup retain separate authoritative outcomes" {
  let session = @host.Session::new(offer())
  let first = session.submit(unit(), suite())
  let outcomes : @protocol.Outcomes = {
    calls: [{ id: "subtract", outcome: Cancelled, }],
    cleanup: Some({
      stage: Cleanup,
      code: "cleanup.failed",
      message: "retained separately",
    }),
    extensions: None,
  }
  let terminal = session.complete(first.identity(), outcomes)
  assert_false(terminal.cancel_requested())
  assert_true(
    terminal.state() is Terminal(evidence) &&
    evidence.calls[0].outcome is Cancelled &&
    evidence.cleanup != None,
  )
  let client = @receipts.Cursor::start(
    offer(),
    first.identity(),
    ["subtract"],
    first,
  )
  ignore(client.observe(terminal))
}

///|
test "actual Result.Err remains returned data and SDK errors remain model errors" {
  let source = @data.IRUnit::new("pricing", @fixtures.pricing())
  let session = @host.Session::new(offer())
  let error_value = @protocol.Value::Outcome(
    Err(@protocol.Value::Text([110, 111])),
  )
  let calls : @protocol.Suite = {
    calls: [
      {
        id: "data",
        entry: "pricing:boundaries#result",
        arguments: [error_value],
      },
      { id: "error", entry: "pricing:results#failure", arguments: [], },
    ],
    extensions: None,
  }
  let first = session.submit(source, calls)
  let plan = session.claim(first.identity())
  let evaluator = @execution.Evaluator::scheme()
  let outputs = plan.suite.calls.map(call => {
    let entry = plan.library.invocations.filter(e => e.fqname == call.entry)[0]
    let value = (evaluator.evaluate)(
      plan.unit,
      call,
      entry.output,
      plan.library.invocation_types,
    )
    @protocol.CallOutcome::{
      id: call.id,
      outcome: match value {
        ModelError(code) => ModelError(code)
        _ => Returned(value)
      },
    }
  })
  let terminal = session.complete(first.identity(), {
    calls: outputs,
    cleanup: None,
    extensions: None,
  })
  assert_true(
    terminal.state() is Terminal(outcomes) &&
    outcomes.calls[0].outcome == Returned(error_value) &&
    outcomes.calls[1].outcome is ModelError(_),
  )
}

///|
test "interleaved executions keep cancellation completion and release independent" {
  let session = @host.Session::new(offer(), max_executions=2)
  let first = session.submit(unit(), suite())
  let second = session.submit(unit(), suite())
  assert_false(first.identity() == second.identity())
  ignore(session.claim(first.identity()))
  let pending = session.cancel(first.identity())
  assert_true(pending.cancel_requested())
  assert_eq(session.query(second.identity()).to_json(), second.to_json())
  ignore(session.claim(second.identity()))
  let finished = session.complete(second.identity(), returned())
  assert_false(finished.cancel_requested())
  assert_eq(session.query(first.identity()).to_json(), pending.to_json())
  session.release(second.identity())
  let third = session.submit(unit(), suite())
  assert_eq(
    third.identity().to_json().obj()["executionId"],
    Json::string("execution-3"),
  )
  assert_true(rejected(() => ignore(session.query(second.identity()))))
  assert_eq(session.query(first.identity()).to_json(), pending.to_json())
  ignore(session.complete(first.identity(), returned()))
  assert_eq(session.query(third.identity()).to_json(), third.to_json())
}
