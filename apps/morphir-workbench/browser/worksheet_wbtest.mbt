///|
test "worksheet capture survives edits while stale source navigation is refused" {
  let started = send(
    {
      ..ready_model(language="scheme"),
      worksheet: true,
      worksheet_source: "(+ 40 2)",
    },
    [Request("worksheet")],
  )
  let capture = started.worksheet_capture.unwrap()
  let report = capture.evaluate()
  let reply : Json = {
    "success": true,
    "worksheetReport": report.to_json().stringify(),
  }
  let edited = send(started, [Source("; changed\n(+ 40 2)")])
  let received = send(edited, [
    Receive(
      started.request_id,
      started.worksheet_revision,
      "worksheet",
      reply.stringify(),
    ),
  ])
  assert_false(received.busy)
  assert_true(received.worksheet_report is Some(_))
  assert_false(worksheet_matches(received, report.source()))
  let range = report.observations()[0].range()
  let stale = send(received, [Worksheet(Reveal(report.source(), range))])
  assert_eq(stale.worksheet_reveal, "")
  let restored = send(stale, [Source("(+ 40 2)")])
  assert_false(worksheet_matches(restored, report.source()))
  let current = send(started, [
    Receive(
      started.request_id,
      started.worksheet_revision,
      "worksheet",
      reply.stringify(),
    ),
    Worksheet(Reveal(report.source(), range)),
  ])
  assert_eq(current.worksheet_reveal, "1:1:1:1:9")
}

///|
test "worksheet receive rejects mismatched captures and cancel awaits owned termination" {
  let started = send(
    {
      ..ready_model(language="scheme"),
      worksheet: true,
      worksheet_source: "7",
    },
    [Request("worksheet")],
  )
  let report = started.worksheet_capture
    .unwrap()
    .evaluate()
    .to_json()
    .stringify()
  let forged = report.replace(old="\"revision\":0", new="\"revision\":1")
  let reply : Json = { "success": true, "worksheetReport": forged }
  let rejected = send(started, [
    Receive(started.request_id, 0, "worksheet", reply.stringify()),
  ])
  assert_true(rejected.worksheet_report is None)
  assert_false(rejected.busy)
  let stopping = send(started, [Cancel])
  assert_true(stopping.busy)
  assert_eq(stopping.request_id, started.request_id)
  assert_true(stopping.worksheet_capture is Some(_))
}

///|
test "worksheet follows the current project and source edits make its results stale" {
  let selected = send(multiple_projects(), [
    OpenWorkspaceFile("packages/two/src/main.scm"),
    AddContent(Worksheet),
    Request("worksheet"),
  ])
  let request = compile_request(selected, "worksheet")
  assert_eq(text(request, "projectPath"), "packages/two")
  let report = selected.worksheet_capture.unwrap().evaluate()
  assert_true(worksheet_matches(selected, report.source()))
  let switched = send(selected, [OpenWorkspaceFile("packages/one/src/main.scm")])
  assert_false(worksheet_matches(switched, report.source()))
  let edited = send(selected, [
    OpenWorkspaceFile("packages/two/src/main.scm"),
    Source("33"),
  ])
  assert_false(worksheet_matches(edited, report.source()))
}
