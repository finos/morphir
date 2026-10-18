///|
fn request(source : String, revision~ : Json = Json::number(0.0)) -> String {
  Json::object({
    "profile": "morphir/workbench/worksheet",
    "contractVersion": "0.1.0-draft.1",
    "source": { "id": "source", "revision": revision, "text": source },
  }).stringify()
}

///|
fn rejects(source : String, expected : String) -> Unit raise {
  let code = try {
    @worksheet.WorksheetRequest::decode(source) |> ignore
    "accepted"
  } catch {
    @execution.Invalid(code) => code
    _ => "unexpected"
  }
  assert_eq(code, expected)
}

///|
test "capture preserves exact source and mathematically integral revision" {
  let text = "\"😀\"\r\n(+ 1 2)"
  let captured = @worksheet.WorksheetRequest::decode(
    request(text, revision=Json::number(4.0)),
  )
  assert_eq(captured.source().text(), text)
  assert_eq(captured.source().to_json(), {
    "id": "source",
    "revision": 4,
    "text": text,
  })
  let range = @worksheet.Utf16Range::new(captured.source(), 6, 13)
  assert_eq(range.slice(captured.source()), "(+ 1 2)")
  let split_rejected = try {
    @worksheet.Utf16Range::new(captured.source(), 2, 3) |> ignore
    false
  } catch {
    @execution.Invalid("worksheet.invalid_range") => true
    _ => false
  }
  assert_true(split_rejected)
}

///|
test "raw capture boundary rejects duplicates and malformed UTF16" {
  rejects("{\"profile\":1,\"profile\":2}", "worksheet.invalid_json")
  rejects(
    request("a").replace(old="\"a\"", new="\"\\ud800\""),
    "worksheet.invalid_json",
  )
  rejects(
    request("a").replace(old="\"source\"", new="\"\\udfff\""),
    "worksheet.invalid_json",
  )
  rejects(
    request("a").replace(old="\"source\"", new="\"bad\\u0000id\""),
    "worksheet.invalid_request",
  )
}

///|
test "revision and source limits reject before reading or evaluation" {
  for
    revision in [
      "-1", "2147483648", "1e400", "1e-400", "0.000000000000000000001", "1.00000000000000000001",
    ] {
    rejects(
      request("a").replace(old="\"revision\":0", new="\"revision\":" + revision),
      "worksheet.invalid_request",
    )
  }
  rejects(request("a".repeat(262145)), "worksheet.invalid_request")
  rejects(" ".repeat(2097153), "worksheet.input_limit")
}
