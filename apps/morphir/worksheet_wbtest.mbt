///|
test "worksheet capture preserves UTF8 and source identity" {
  let source = worksheet_capture(
    @utf8.encode("\"😀\"\r\n42"),
    "build/worksheet",
    7,
  )
  assert_eq(source.source().to_json(), {
    "id": "build/worksheet",
    "revision": 7,
    "text": "\"😀\"\r\n42",
  })
  let report = source.evaluate()
  assert_eq(worksheet_status(report), 0)
  assert_eq(report.observations().length(), 2)
  assert_eq(report.observations()[1].range().to_json(), { "start": 6, "end": 8 })
}

///|
test "worksheet capture refuses malformed UTF8 and input limits" {
  for bytes in [b"\xff", b"\xf0\x9f\x98"] {
    let rejected = try {
      ignore(worksheet_capture(bytes, "source", 0))
      false
    } catch {
      @config.Invalid("worksheet.invalid_utf8") => true
      _ => false
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(worksheet_capture(@utf8.encode("x".repeat(1048577)), "source", 0))
    false
  } catch {
    @config.Invalid("worksheet.input_limit") => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "worksheet status includes row failures and confirmed termination" {
  let capture = fn(text) raise {
    worksheet_capture(@utf8.encode(text), "source", 0)
  }
  assert_eq(worksheet_status(capture("").evaluate()), 0)
  assert_eq(worksheet_status(capture("1/3\n42").evaluate()), 1)
  assert_eq(worksheet_status(capture("1\nmissing\n2").evaluate()), 1)
  assert_eq(worksheet_status(capture("(").evaluate()), 1)
  assert_eq(
    worksheet_status(capture("1").terminated(@worksheet.Cancelled)),
    130,
  )
  assert_eq(worksheet_status(capture("1").terminated(@worksheet.TimedOut)), 1)
}
