///|
test "library observations preserve IR and expose ordered private phases" {
  let input = observed_input(
    "pub fn secret_name(x : Bool) -> Bool { let y = !x; helper(y) }\nfn helper(x : Bool) -> Bool { x }",
  )
  let expected = @frontend.compile_library(input)
  let records = []
  let actual = @frontend.compile_library(
    input,
    scope=observer(records, Ref(0)).scope(),
  )
  assert_eq(actual.ir, expected.ir)
  assert_eq(actual.entries, expected.entries)
  for (a, b) in actual.metadata.zip(expected.metadata) {
    assert_eq(a.node_id, b.node_id)
    assert_true(a.data.equals(b.data))
  }
  assert_true(actual.provenance[0].equals(expected.provenance[0]))
  assert_eq(
    records.filter(r => r.signal == @observe.Started).map(r => r.stage.name()),
    ["frontend", "parse", "profile-check", "resolve", "profile-check", "lower"],
  )
  for record in records {
    assert_true(record.details is None)
    assert_false(record.to_json().stringify().contains("secret"))
    if record.stage != @observe.Frontend {
      assert_eq(record.context.parent_id, records[0].context.span_id)
    }
  }
  assert_eq(records.filter(r => r.signal == @observe.Succeeded).length(), 6)
}

///|
test "library failures close active spans and skip later phases" {
  for
    (source, code, stage, start_count) in [
      ("pub fn f(", "syntax", @observe.Parse, 2),
      (
        "pub fn f(x : Array[Bool]) -> Bool { true }",
        "unsupported_type",
        @observe.ProfileCheck,
        3,
      ),
      (
        "pub fn f() -> Bool { missing }",
        "unknown_reference",
        @observe.Resolve,
        4,
      ),
      ("pub fn f() -> Bool { f() }", "recursive_call", @observe.ProfileCheck, 5),
    ] {
    let records = []
    let expected = library_failure(source)
    try {
      ignore(
        @frontend.compile_library(
          observed_input(source),
          scope=observer(records, Ref(0)).scope(),
        ),
      )
      fail("Expected rejection")
    } catch {
      @frontend.Invalid(d) => {
        assert_eq(d.code, "moonbit_frontend." + code)
        assert_eq(d.code, expected.code)
        assert_eq(d.detail, expected.detail)
        assert_eq(d.source, expected.source)
      }
      error => raise error
    }
    assert_eq(
      records.filter(r => r.signal == @observe.Started).length(),
      start_count,
    )
    assert_eq(
      records.filter(r => r.signal == @observe.Failed).map(r => r.stage),
      [stage, @observe.Frontend],
    )
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
test "library cancellation polls every phase and ends each active span once" {
  for phase = 1; phase <= 6; phase = phase + 1 {
    let records = []
    let starts = Ref(0)
    let o = observer(records, Ref(0))
    let o = {
      ..o,
      try_record: fn(record) {
        if record.signal == @observe.Started {
          starts.val += 1
        }
        records.push(record)
        @observe.Accepted
      },
    }
    try {
      ignore(
        @frontend.compile_library(
          observed_input(
            "pub fn f(x : Bool) -> Bool { let y = !x; g(y) }\nfn g(x : Bool) -> Bool { x }",
          ),
          scope=o.scope(),
          cancelled=fn() { starts.val == phase },
        ),
      )
      fail("Expected cancellation")
    } catch {
      @frontend.Invalid(d) => assert_eq(d.code, "moonbit_frontend.cancelled")
      error => raise error
    }
    assert_eq(starts.val, phase)
    assert_true(records.all(r => r.signal != @observe.Failed))
    let terminals = records.filter(r => r.signal == @observe.Cancelled)
    assert_eq(terminals.length(), if phase == 1 { 1 } else { 2 })
    assert_eq(terminals[terminals.length() - 1].stage, @observe.Frontend)
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
test "library disabled and throwing observation sinks preserve semantics" {
  let input = observed_input(
    "pub fn f(x : Bool) -> Bool { g(x) }\nfn g(x : Bool) -> Bool { !x }",
  )
  let expected = @frontend.compile_library(input)
  let work = Ref(0)
  let records = []
  let disabled = @frontend.compile_library(
    input,
    scope=observer(records, work, enabled=false).scope(),
  )
  assert_eq(work.val, 0)
  let broken = @frontend.compile_library(
    input,
    scope=observer(records, work, broken=true).scope(),
  )
  assert_true(work.val > 0)
  assert_true(records.is_empty())
  assert_eq(disabled.ir, expected.ir)
  assert_eq(broken.ir, expected.ir)
}
