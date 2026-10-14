///|
fn evidence(outcome : @execution.TerminalOutcome) -> @execution.Outcomes {
  { calls: [{ id: "call", outcome, }], cleanup: None, extensions: None, }
}

///|
test "terminal codecs preserve rich values failures and exact opaque bytes" {
  let metadata_bytes : Bytes = b"\xe0\x01\x00\xea\x0f"
  let outcomes : @execution.Outcomes = {
    calls: [
      { id: "bits", outcome: Returned(Float64(0x8000000000000000UL)), },
      { id: "err", outcome: Returned(Outcome(Err(Boolean(false)))), },
      { id: "sdk", outcome: ModelError("sdk.division_by_zero"), },
      {
        id: "failure",
        outcome: Failed({ stage: Invoke, code: "provider.crash", message: "", }),
      },
      { id: "cancel", outcome: Cancelled, },
    ],
    cleanup: Some({
      stage: Cleanup,
      code: "provider.dispose",
      message: "Disposal failed",
    }),
    extensions: Some(metadata_bytes),
  }
  outcomes.validate()
  assert_eq(@execution.Outcomes::from_json(outcomes.to_json()), outcomes)
  assert_eq(@execution.Outcomes::from_ion(outcomes.to_ion()), outcomes)
  assert_eq(outcomes.extensions, Some(metadata_bytes))
  let absent = evidence(Cancelled)
  assert_eq(@execution.Outcomes::from_ion(absent.to_ion()).extensions, None)
}

///|
test "terminal codec rejects duplicate fields annotated or typed null absence" {
  for
    source in [
      "{contractVersion:\"0.1.0-draft.5\",calls:[{id:\"call\",outcome:{status:\"cancelled\",status:\"cancelled\"}}],cleanup:null,extensions:null}",
      "{contractVersion:\"0.1.0-draft.5\",calls:[{id:\"call\",outcome:{status:\"cancelled\"}}],cleanup:null.struct,extensions:null}",
      "{contractVersion:\"0.1.0-draft.5\",calls:[{id:\"call\",outcome:{status:\"cancelled\"}}],cleanup:null,extensions:tag::null}",
    ] {
    assert_true(
      try {
        ignore(@execution.Outcomes::decode(@utf8.encode(source), "ion-text"))
        false
      } catch {
        _ => true
      },
    )
  }
  let duplicate = "{\"contractVersion\":\"0.1.0-draft.5\",\"calls\":[{\"id\":\"call\",\"outcome\":{\"status\":\"cancelled\",\"status\":\"cancelled\"}}],\"cleanup\":null,\"extensions\":null}"
  assert_true(
    try {
      ignore(@execution.Outcomes::decode(@utf8.encode(duplicate), "json"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "terminal budgets count UTF16 and returned value nodes" {
  let at_limit = evidence(
    Failed({
      stage: Invoke,
      code: "x".repeat(128),
      message: "😀".repeat(256),
    }),
  )
  at_limit.validate()
  for
    invalid in [
      evidence(Failed({ stage: Invoke, code: "😀".repeat(65), message: "", })),
      evidence(
        Failed({ stage: Invoke, code: "x", message: "😀".repeat(257), }),
      ),
      evidence(Returned(Sequence(Array::make(100000, @execution.Value::Unit)))),
      { ..evidence(Cancelled), extensions: Some(Bytes::make(65537, b' ')), },
    ] {
    assert_true(
      try {
        invalid.validate()
        false
      } catch {
        _ => true
      },
    )
  }
  evidence(Returned(Sequence(Array::make(99999, @execution.Value::Unit)))).validate()
  let mut nested : @execution.Value = Unit
  for _i = 0; _i < 64; _i = _i + 1 {
    nested = Optional(Some(nested))
  }
  evidence(Returned(nested)).validate()
  assert_true(
    try {
      evidence(Returned(Optional(Some(nested)))).validate()
      false
    } catch {
      _ => true
    },
  )
}

///|
test "terminal admission binds call order and exact extension bytes" {
  let suite : @execution.Suite = {
    calls: [{ id: "call", entry: "run", arguments: [], }],
    extensions: Some(b"\xe0\x01\x00\xea\x0f"),
  }
  let entries : Array[@execution.PublicEntry] = [
    { name: "run", inputs: [], output: Int, },
  ]
  let outcomes = { ..evidence(Cancelled), extensions: suite.extensions, }
  @execution.validate_outcomes(outcomes, suite, entries, [])
  for
    invalid in [
      evidence(Cancelled),
      { ..outcomes, calls: [{ id: "other", outcome: Cancelled, }], },
    ] {
    assert_true(
      try {
        @execution.validate_outcomes(invalid, suite, entries, [])
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "terminal admission checks each call against its selected output" {
  let suite : @execution.Suite = {
    calls: [
      { id: "first", entry: "integer", arguments: [], },
      { id: "second", entry: "boolean", arguments: [], },
    ],
    extensions: None,
  }
  let entries : Array[@execution.PublicEntry] = [
    { name: "integer", inputs: [], output: Int, },
    { name: "boolean", inputs: [], output: Bool, },
  ]
  let outcomes : @execution.Outcomes = {
    calls: [
      { id: "first", outcome: Returned(Integer(@bigint.BigInt::from_int(7))), },
      { id: "second", outcome: Returned(Boolean(false)), },
    ],
    cleanup: None,
    extensions: None,
  }
  @execution.validate_outcomes(outcomes, suite, entries, [])
  let wrong_second = {
    ..outcomes,
    calls: [outcomes.calls[0], { id: "second", outcome: Returned(Unit), }],
  }
  let rejected = try {
    @execution.validate_outcomes(wrong_second, suite, entries, [])
    false
  } catch {
    @execution.Invalid(code) => code.has_prefix("execution.wrong_type:")
    _ => false
  }
  assert_true(rejected)
}
