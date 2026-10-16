///|
fn observed_input(source : String) -> @frontend.Input {
  {
    unit_id: "secret-unit",
    package_name: "secret-package",
    module_name: "secret-module",
    source,
  }
}

///|
fn observer(
  records : Array[@observe.Observation],
  work : Ref[Int32],
  enabled~ : Bool = true,
  broken~ : Bool = false,
) -> @observe.Observer {
  {
    enabled: fn() { enabled },
    try_record: fn(record) raise {
      work.val += 1
      if broken {
        raise @frontend.Invalid({
          code: "sink",
          detail: "failed",
          source: None,
        })
      }
      records.push(record)
      @observe.Accepted
    },
    monotonic: fn() {
      work.val += 1
      work.val.to_double() / 100.0
    },
    wall: fn() {
      work.val += 1
      1000.0
    },
    next_id: fn() {
      work.val += 1
      let hex = work.val.to_string(radix=16)
      "0000000000000000"[:16 - hex.length()].to_owned() + hex
    },
    run_id: "run",
    trace_id: "11111111111111111111111111111111",
    sequence: Ref(0),
  }
}

///|
test "frontend observations preserve semantic IR origins and privacy" {
  let input = observed_input(
    "// secret-source λ😀\npub fn secret_name(secret_arg : Bool) -> Bool { !secret_arg }",
  )
  let expected = @frontend.compile(input)
  let records = []
  let actual = @frontend.compile(input, scope=observer(records, Ref(0)).scope())
  assert_eq(@ir_json.write(actual.ir), @ir_json.write(expected.ir))
  assert_eq(actual.entry, expected.entry)
  assert_eq(actual.unit_id, expected.unit_id)
  assert_eq(actual.public, expected.public)
  assert_eq(actual.metadata.length(), expected.metadata.length())
  for (a, b) in actual.metadata.zip(expected.metadata) {
    assert_eq(a.node_id, b.node_id)
    assert_true(a.data.equals(b.data))
  }
  assert_true(actual.provenance[0].equals(expected.provenance[0]))
  assert_eq(actual.annotations[0].text(), expected.annotations[0].text())
  assert_eq(records.map(r => (r.stage.name(), r.signal)), [
    ("frontend", @observe.Started),
    ("parse", @observe.Started),
    ("parse", @observe.Succeeded),
    ("profile-check", @observe.Started),
    ("profile-check", @observe.Succeeded),
    ("lower", @observe.Started),
    ("lower", @observe.Succeeded),
    ("frontend", @observe.Succeeded),
  ])
  for record in records {
    if record.stage != @observe.Frontend {
      assert_eq(record.context.parent_id, records[0].context.span_id)
    }
    assert_true(record.details is None)
    assert_true(!record.to_json().stringify().contains("secret"))
    assert_true(record.duration_seconds >= 0.0)
  }
  assert_true(records[7].duration_seconds > 0.0)
}

///|
test "source failures end active spans once and skip subsequent stages" {
  for
    (source, code, stage) in [
      ("pub fn broken(", "syntax", @observe.Parse),
      (
        "pub fn f(x : Int) -> Bool { true }",
        "unsupported_type",
        @observe.ProfileCheck,
      ),
      (
        "pub fn f(x : Bool) -> Bool { 1 }",
        "unsupported_expression",
        @observe.Lower,
      ),
    ] {
    let input = observed_input(source)
    let expected = try {
      ignore(@frontend.compile(input))
      abort("Expected rejection")
    } catch {
      @frontend.Invalid(d) => d
      error => raise error
    }
    let records = []
    let actual = try {
      ignore(@frontend.compile(input, scope=observer(records, Ref(0)).scope()))
      abort("Expected rejection")
    } catch {
      @frontend.Invalid(d) => d
      error => raise error
    }
    assert_eq(actual.code, "moonbit_frontend." + code)
    assert_eq(actual.code, expected.code)
    assert_eq(actual.detail, expected.detail)
    assert_eq(actual.source, expected.source)
    let failures = records.filter(r => r.signal == @observe.Failed)
    assert_eq(failures.map(r => r.stage), [stage, @observe.Frontend])
    assert_eq(records[records.length() - 3].stage, stage)
    for record in records.filter(r => r.signal == @observe.Started) {
      assert_eq(
        records
        .filter(r => r.context.span_id == record.context.span_id)
        .length(),
        2,
      )
    }
  }
}

///|
test "frontend cancellation retains its diagnostic and cancels every active span" {
  for
    (poll, stage) in [
      (1, @observe.Frontend),
      (2, @observe.Parse),
      (3, @observe.Lower),
    ] {
    let records = []
    let polls = Ref(0)
    let rejected = try {
      ignore(
        @frontend.compile(
          observed_input("pub fn f(x : Bool) -> Bool { !x }"),
          scope=observer(records, Ref(0)).scope(),
          cancelled=fn() {
            polls.val += 1
            polls.val == poll
          },
        ),
      )
      false
    } catch {
      @frontend.Invalid(d) => d.code == "moonbit_frontend.cancelled"
      error => raise error
    }
    assert_true(rejected)
    assert_true(records.all(r => r.signal != @observe.Failed))
    let cancelled = records.filter(r => r.signal == @observe.Cancelled)
    assert_eq(cancelled[0].stage, stage)
    assert_eq(cancelled[cancelled.length() - 1].stage, @observe.Frontend)
  }
}

///|
test "disabled and throwing sinks preserve frontend results and diagnostics" {
  let input = observed_input("pub fn f(x : Bool) -> Bool { x }")
  let expected = @frontend.compile(input)
  let work = Ref(0)
  let records = []
  let disabled = @frontend.compile(
    input,
    scope=observer(records, work, enabled=false).scope(),
  )
  assert_eq(work.val, 0)
  let broken = @frontend.compile(
    input,
    scope=observer(records, work, broken=true).scope(),
  )
  assert_true(work.val > 0)
  assert_true(records.is_empty())
  assert_eq(@ir_json.write(disabled.ir), @ir_json.write(expected.ir))
  assert_eq(@ir_json.write(broken.ir), @ir_json.write(expected.ir))
  let invalid = observed_input("pub fn f(x : Int) -> Bool { true }")
  let rejected = try {
    ignore(
      @frontend.compile(
        invalid,
        scope=observer(records, work, broken=true).scope(),
      ),
    )
    false
  } catch {
    @frontend.Invalid(d) => d.code == "moonbit_frontend.unsupported_type"
    error => raise error
  }
  assert_true(rejected)
}
