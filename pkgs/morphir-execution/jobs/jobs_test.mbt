///|
fn identity() -> @jobs.Identity raise {
  @jobs.Identity::from_json({
    "hostId": "host",
    "sessionId": "session",
    "providerId": "provider",
    "jobId": "job",
    "snapshotId": "snapshot",
  })
}

///|
fn offer(cancel? : Bool = true) -> @jobs.Offer raise {
  @jobs.Offer::from_json({
    "profile": "morphir/workbench/jobs",
    "contractVersion": "0.1.0-draft.1",
    "hostId": "host",
    "sessionId": "session",
    "providerId": "provider",
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
fn receipt(
  sequence : Int,
  state : String,
  cancel? : Bool = false,
  outcomes? : Json = Json::null(),
  snapshot? : String = "snapshot",
) -> @jobs.Receipt raise {
  @jobs.Receipt::from_json({
    "contractVersion": "0.1.0-draft.1",
    "identity": {
      "hostId": "host",
      "sessionId": "session",
      "providerId": "provider",
      "jobId": "job",
      "snapshotId": snapshot,
    },
    "sequence": sequence,
    "state": state,
    "cancelRequested": cancel,
    "outcomes": outcomes,
  })
}

///|
fn outcomes(status? : String = "returned") -> Json {
  {
    "contractVersion": "0.1.0-draft.5",
    "calls": [
      {
        "id": "call",
        "outcome": if status == "returned" {
          { "status": "returned", "value": { "type": "bool", "value": true } }
        } else {
          { "status": status }
        },
      },
    ],
    "cleanup": null,
    "extensions": null,
  }
}

///|
fn start(cancel? : Bool = true) -> @jobs.Cursor raise {
  @jobs.Cursor::start(
    offer(cancel~),
    identity(),
    ["call"],
    receipt(0, "submitted"),
  )
}

///|
test "host acknowledgement cannot replace returned data with cancellation" {
  let cursor = start()
  @debug.debug_inspect(cursor.cancel_action(), content="Send")
  let (running, _) = cursor.observe(receipt(1, "running", cancel=true))
  @debug.debug_inspect(running.cancel_action(), content="Pending")
  let (terminal, _) = running.observe(
    receipt(2, "terminal", cancel=true, outcomes=outcomes()),
  )
  @debug.debug_inspect(terminal.cancel_action(), content="AlreadyTerminal")
  @debug.debug_inspect(
    terminal
    .latest()
    .to_json()
    .field("outcomes")
    .field("calls")
    .first()
    .field("outcome")
    .field("status"),
    content="String(\"returned\")",
  )
  @debug.debug_inspect(
    cursor.latest().to_json().field("state"),
    content="String(\"submitted\")",
  )
}

///|
test "replay is idempotent and stale evidence does not regress the cursor" {
  let (cursor, _) = start().observe(receipt(4, "running"))
  let (_, same) = cursor.observe(receipt(4, "running"))
  let (unchanged, stale) = cursor.observe(receipt(1, "submitted"))
  @debug.debug_inspect(same, content="Replay")
  @debug.debug_inspect(stale, content="Stale")
  @debug.debug_inspect(
    unchanged.latest().to_json().field("sequence"),
    content="Number(4)",
  )
}

///|
test "conflicting same revision and authoritative regressions reject" {
  let (cursor, _) = start().observe(receipt(1, "running", cancel=true))
  assert_true(rejected(() => ignore(cursor.observe(receipt(1, "running")))))
  assert_true(
    rejected(() => ignore(cursor.observe(receipt(2, "submitted", cancel=true)))),
  )
  assert_true(rejected(() => ignore(cursor.observe(receipt(2, "running")))))
}

///|
test "terminal is immutable but can be replayed after reconnect" {
  let (cursor, _) = start().observe(
    receipt(2, "terminal", outcomes=outcomes(status="cancelled")),
  )
  assert_true(
    rejected(() => {
      ignore(cursor.observe(receipt(3, "terminal", outcomes=outcomes())))
    }),
  )
  let disconnected = cursor.disconnect()
  assert_false(disconnected.connected())
  assert_true(rejected(() => ignore(disconnected.observe(cursor.latest()))))
  let resumed = disconnected.reconnect(offer())
  let (_, kind) = resumed.observe(cursor.latest())
  @debug.debug_inspect(kind, content="Replay")
  @debug.debug_inspect(
    disconnected.latest().to_json().field("state"),
    content="String(\"terminal\")",
  )
}

///|
test "all authority and snapshot fields are bound even for stale receipts" {
  let (cursor, _) = start().observe(receipt(3, "running"))
  assert_true(
    rejected(() => {
      ignore(cursor.observe(receipt(1, "submitted", snapshot="other")))
    }),
  )
  for name in ["hostId", "sessionId", "providerId", "jobId", "snapshotId"] {
    let fields = identity().to_json().obj()
    fields[name] = "other"
    let value = receipt(4, "running").to_json().obj()
    value["identity"] = Json::object(fields)
    assert_true(
      rejected(() => {
        ignore(cursor.observe(@jobs.Receipt::from_json(Json::object(value))))
      }),
    )
  }
  let host = offer().to_json().obj()
  host["sessionId"] = "new-session"
  assert_true(
    rejected(() => {
      ignore(
        cursor
        .disconnect()
        .reconnect(@jobs.Offer::from_json(Json::object(host))),
      )
    }),
  )
}

///|
test "optional cancellation and exact profile negotiation" {
  @debug.debug_inspect(
    start(cancel=false).cancel_action(),
    content="Unavailable",
  )
  let fields = offer().to_json().obj()
  for
    version in [
      "0.1.0-draft.2", "0.1.0", "v0.1.0-draft.1", "0.1.0-draft.1+build",
    ] {
    fields["contractVersion"] = Json::string(version)
    assert_true(
      rejected(() => ignore(@jobs.Offer::from_json(Json::object(fields)))),
    )
  }
  fields["contractVersion"] = "0.1.0-draft.1"
  fields["operations"] = ["cancel"]
  assert_true(
    rejected(() => ignore(@jobs.Offer::from_json(Json::object(fields)))),
  )
  fields["operations"] = ["query", "query"]
  assert_true(
    rejected(() => ignore(@jobs.Offer::from_json(Json::object(fields)))),
  )
}

///|
test "receipt payload shape and startup are strict" {
  assert_true(rejected(() => ignore(receipt(0, "running"))))
  assert_true(rejected(() => ignore(receipt(0, "submitted", cancel=true))))
  assert_true(
    rejected(() => ignore(receipt(1, "running", outcomes=outcomes()))),
  )
  assert_true(rejected(() => ignore(receipt(1, "terminal"))))
  assert_true(rejected(() => ignore(receipt(1, "cancelled"))))
  assert_true(
    rejected(() => {
      ignore(
        @jobs.Cursor::start(
          offer(),
          identity(),
          ["call"],
          receipt(1, "running"),
        ),
      )
    }),
  )
  assert_true(
    rejected(() => {
      ignore(
        @jobs.Cursor::start(
          offer(),
          identity(),
          ["call", "call"],
          receipt(0, "submitted"),
        ),
      )
    }),
  )
  assert_true(
    rejected(() => {
      ignore(
        @jobs.Cursor::start(offer(), identity(), [], receipt(0, "submitted")),
      )
    }),
  )
}

///|
test "terminal inventory binds to submitted calls" {
  let value = outcomes().obj()
  value["calls"] = [{ "id": "other", "outcome": { "status": "cancelled" } }]
  assert_true(
    rejected(() => {
      ignore(
        start().observe(receipt(1, "terminal", outcomes=Json::object(value))),
      )
    }),
  )
  let duplicate = outcomes().obj()
  duplicate["calls"] = [
    { "id": "call", "outcome": { "status": "cancelled" } },
    { "id": "call", "outcome": { "status": "cancelled" } },
  ]
  assert_true(
    rejected(() => {
      ignore(receipt(1, "terminal", outcomes=Json::object(duplicate)))
    }),
  )
}

///|
test "mutable input and returned copies cannot mutate admitted authority" {
  let ids = ["call"]
  let cursor = @jobs.Cursor::start(
    offer(),
    identity(),
    ids,
    receipt(0, "submitted"),
  )
  ids[0] = "forged"
  let (terminal, _) = cursor.observe(
    receipt(1, "terminal", outcomes=outcomes()),
  )
  let exported = terminal.latest().to_json().obj()
  exported["state"] = "submitted"
  @debug.debug_inspect(
    terminal.latest().to_json().field("state"),
    content="String(\"terminal\")",
  )
}

///|
test "host revision requires a state or acknowledgement change" {
  assert_true(rejected(() => ignore(start().observe(receipt(1, "submitted")))))
  let (cursor, _) = start().observe(receipt(1, "running"))
  assert_true(rejected(() => ignore(cursor.observe(receipt(2, "running")))))
  let (acknowledged, _) = cursor.observe(receipt(3, "running", cancel=true))
  @debug.debug_inspect(acknowledged.cancel_action(), content="Pending")
}

///|
test "bounds count UTF16 units and preserve portable sequence maxima" {
  let fields = identity().to_json().obj()
  fields["jobId"] = Json::string("😀".repeat(64))
  ignore(@jobs.Identity::from_json(Json::object(fields)))
  fields["jobId"] = Json::string("😀".repeat(65))
  assert_true(
    rejected(() => ignore(@jobs.Identity::from_json(Json::object(fields)))),
  )
  let maximum = receipt(2147483647, "running")
  let (_, kind) = start().observe(maximum)
  @debug.debug_inspect(kind, content="Advanced")
  let value = maximum.to_json().obj()
  for sequence in [-1.0, 0.5, 2147483648.0] {
    value["sequence"] = Json::number(sequence)
    assert_true(
      rejected(() => ignore(@jobs.Receipt::from_json(Json::object(value)))),
    )
  }
  value["sequence"] = 1
  value["unknown"] = true
  assert_true(
    rejected(() => ignore(@jobs.Receipt::from_json(Json::object(value)))),
  )
}

///|
test "disconnect and client cancel leave nonterminal host evidence intact" {
  let cursor = start().disconnect()
  @debug.debug_inspect(cursor.cancel_action(), content="Disconnected")
  @debug.debug_inspect(
    cursor.latest().to_json().field("state"),
    content="String(\"submitted\")",
  )
  let cursor = cursor.reconnect(offer())
  @debug.debug_inspect(cursor.cancel_action(), content="Send")
  @debug.debug_inspect(
    cursor.latest().to_json().field("cancelRequested"),
    content="False",
  )
  let host = offer().to_json().obj()
  host["operations"] = ["query"]
  assert_true(
    rejected(() => {
      ignore(
        cursor
        .disconnect()
        .reconnect(@jobs.Offer::from_json(Json::object(host))),
      )
    }),
  )
  assert_true(
    rejected(() => {
      ignore(start(cancel=false).observe(receipt(1, "submitted", cancel=true)))
    }),
  )
}

///|
test "terminal cleanup and primary failure both survive" {
  let value : Json = {
    "contractVersion": "0.1.0-draft.5",
    "calls": [
      {
        "id": "call",
        "outcome": {
          "status": "failed",
          "failure": {
            "stage": "evaluate",
            "code": "execution.evaluate",
            "message": "primary",
          },
        },
      },
    ],
    "cleanup": {
      "stage": "cleanup",
      "code": "provider.dispose",
      "message": "cleanup",
    },
    "extensions": null,
  }
  let (cursor, _) = start().observe(receipt(1, "terminal", outcomes=value))
  assert_eq(cursor.latest().to_json().field("outcomes"), value)
}

///|
fn rejected(f : () -> Unit raise) -> Bool {
  try {
    f()
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
fn Json::field(self : Json, name : String) -> Json {
  self.obj()[name]
}

///|
fn Json::first(self : Json) -> Json {
  match self {
    Array(items) => items[0]
    _ => abort("expected array")
  }
}
