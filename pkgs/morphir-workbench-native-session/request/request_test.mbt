///|
fn opening() -> String {
  "{\"profile\":\"morphir/workbench/native\",\"contractVersion\":\"0.1.0-draft.1\",\"operation\":\"session.open\"}"
}

///|
fn rejected(bytes : Bytes, code : String) -> Unit raise {
  let mut actual = "accepted"
  ignore(@request.decode(bytes)) catch {
    Invalid(value) => actual = value
  }
  assert_eq(actual, code)
}

///|
test "native framing rejects before authority or execution" {
  assert_eq(
    @request.decode(@utf8.encode(opening())).operation(),
    "session.open",
  )
  rejected(b"\xc3\x28", "native.frame.utf8")
  rejected(@utf8.encode(opening() + " {}"), "native.frame.json")
  rejected(@utf8.encode("{\"a\":1,\"\\u0061\":2}"), "native.frame.json")
  rejected(@utf8.encode("{}"), "native.frame.shape")
  rejected(@utf8.encode(" ".repeat(1048576) + opening()), "native.frame.limit")
  rejected(
    @utf8.encode("[".repeat(65) + "0" + "]".repeat(65)),
    "native.frame.limit",
  )
  rejected(@utf8.encode("[" + "0,".repeat(99999) + "0]"), "native.frame.limit")
}

///|
fn submission(
  model : String,
  source : String,
  format~ : String = "json",
) -> Bytes {
  @utf8.encode(
    (
      {
        "profile": "morphir/workbench/native",
        "contractVersion": "0.1.0-draft.1",
        "operation": "job.submit",
        "sessionId": "s",
        "payload": {
          "contractVersion": "0.1.0-draft.1",
          "model": model,
          "entry": "not-an-admitted-function",
          "inputs": { "format": format, "source": source },
        },
      } : Json).stringify(),
  )
}

///|
test "native frame boundary decodes nested JSON without model or value admission" {
  ignore(@request.decode(submission("{}", "[1]")))
  ignore(
    @request.decode(
      submission("null", "opaque Ion is not decoded here", format="ion-text"),
    ),
  )
  rejected(submission("{\"a\":1,\"a\":2}", "[]"), "native.frame.model")
  rejected(submission("{} {}", "[]"), "native.frame.model")
  rejected(
    submission("{}", "[{\"v\":1,\"\\u0076\":1}]"),
    "native.frame.arguments",
  )
  rejected(submission("{}", "[] []"), "native.frame.arguments")
  rejected(submission("{}", "{}"), "native.frame.arguments")
}

///|
test "native workspace integers use original number text" {
  let source = "{\"profile\":\"morphir/workbench/native\",\"contractVersion\":\"0.1.0-draft.1\",\"operation\":\"workspace.read\",\"sessionId\":\"s\",\"payload\":{\"grantId\":\"g\",\"sequence\":SEQUENCE,\"offset\":OFFSET}}"
  for sequence in ["1.00000000000000001", "2147483647.00000001", "1e-999"] {
    rejected(
      @utf8.encode(
        source
        .replace(old="SEQUENCE", new=sequence)
        .replace(old="OFFSET", new="0"),
      ),
      "native.frame.shape",
    )
  }
  for offset in ["1e-999", "-1e-999", "0.00000000000000000000001"] {
    rejected(
      @utf8.encode(
        source
        .replace(old="SEQUENCE", new="1")
        .replace(old="OFFSET", new=offset),
      ),
      "native.frame.shape",
    )
  }
  for sequence in ["1.0", "1e0", "10e-1", "1.000e+0", "21474836470e-1"] {
    ignore(
      @request.decode(
        @utf8.encode(
          source
          .replace(old="SEQUENCE", new=sequence)
          .replace(old="OFFSET", new="-0.0"),
        ),
      ),
    )
  }
}
