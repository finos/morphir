///|
test "empty and comment-only worksheets return no observations" {
  for source in ["", "; nothing here\r\n", "#| nested #| comment |# |#"] {
    let captured = @worksheet.WorksheetRequest::decode(request(source))
    let report = captured.evaluate()
    assert_eq(report.observations().length(), 0)
    assert_true(report.successful())
    assert_eq(
      @worksheet.WorksheetReport::decode(captured, report.to_json().stringify()).to_json(),
      report.to_json(),
    )
  }
}

///|
test "Unicode CRLF ranges use original UTF16 offsets" {
  let report = evaluate(";😀\r\n\"😀\"\r\n(+ 1 2)")
  let rows = @wire.array(@wire.field(report, "observations"))
  assert_eq(@wire.field(rows[0], "range"), { "start": 5, "end": 9 })
  assert_eq(@wire.field(rows[1], "range"), { "start": 11, "end": 18 })
  assert_eq(@wire.field(rows[0], "outcome"), {
    "status": "returned",
    "value": { "type": "text", "units": [55357, 56832] },
  })
}

///|
test "interruption is canonical transport evidence before reading or during evaluation" {
  for source in ["", "(", "1\n(let loop () (loop))"] {
    let captured = @worksheet.WorksheetRequest::decode(request(source))
    let immediate = captured.evaluate(interrupted=fn() {
      Some(@worksheet.Cancelled)
    })
    assert_eq(
      immediate.to_json(),
      captured.terminated(@worksheet.Cancelled).to_json(),
    )
    assert_false(immediate.successful())
    assert_eq(
      @worksheet.WorksheetReport::decode(
        captured,
        immediate.to_json().stringify(),
      ).to_json(),
      immediate.to_json(),
    )
  }
  let captured = @worksheet.WorksheetRequest::decode(
    request("1\n(let loop () (loop))"),
  )
  for reason in [@worksheet.Cancelled, @worksheet.TimedOut] {
    for cutoff in [1, 2, 20] {
      let polls = Ref(0)
      let report = captured.evaluate(interrupted=fn() {
        polls.val += 1
        if polls.val > cutoff {
          Some(reason)
        } else {
          None
        }
      })
      assert_true(polls.val > cutoff)
      assert_eq(report.to_json(), captured.terminated(reason).to_json())
      assert_eq(
        @worksheet.WorksheetReport::decode(
          captured,
          report.to_json().stringify(),
        ).to_json(),
        report.to_json(),
      )
    }
  }
}

///|
test "fixed form and runtime limits retain their meanings" {
  let excessive = @worksheet.WorksheetRequest::decode(
    request("1\n".repeat(1001)),
  )
  let rejected = try {
    ignore(excessive.evaluate())
    false
  } catch {
    @execution.Invalid("worksheet.input_limit") => true
    _ => false
  }
  assert_true(rejected)
  let captured = @worksheet.WorksheetRequest::decode(
    request("1\n(let loop () (loop))\n2"),
  )
  let report = captured.evaluate()
  assert_eq(report.observations().length(), 2)
  assert_false(report.successful())
  let completion = report.completion().to_json()
  assert_eq(
    @wire.field(@wire.field(completion, "failure"), "code"),
    Json::string("worksheet.runtime_limit"),
  )
  assert_eq(
    @worksheet.WorksheetReport::decode(captured, report.to_json().stringify()).to_json(),
    report.to_json(),
  )
}

///|
test "host preparation shares the worksheet budget and cannot shift captured ranges" {
  let captured = @worksheet.WorksheetRequest::decode(
    request(";😀\r\n(+ project 2)"),
  )
  let report = captured.evaluate(prepare=runtime => {
    ignore(runtime.eval("(define project 40)"))
  })
  assert_eq(report.observations()[0].preview(), "42")
  assert_eq(report.observations()[0].expression(), "(+ project 2)")
  let failed = captured.evaluate(prepare=runtime => {
    ignore(runtime.eval("(let loop () (loop))"))
  })
  assert_false(failed.successful())
  assert_eq(
    @worksheet.WorksheetReport::decode(captured, failed.to_json().stringify()).to_json(),
    failed.to_json(),
  )
  assert_eq(
    @wire.field(
      @wire.field(@wire.field(failed.to_json(), "completion"), "failure"),
      "code",
    ),
    Json::string("worksheet.context_failed"),
  )
}
