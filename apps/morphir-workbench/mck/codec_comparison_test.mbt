///|
fn codec_request(operation : String, input : Json) -> Json {
  @mck.handle({
    "id": 1,
    "op": operation,
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.26",
    "format": "json",
    "input": input,
  })
}

///|
test "comparison preserves opaque JSON numeric tokens before value rejection" {
  assert_eq(
    @mck.handle_line(
      "{\"id\":1,\"op\":\"compare-values\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.26\",\"format\":\"json\",\"input\":{\"actual\":1e400,\"expected\":{\"type\":\"unit\"},\"comparison\":{\"profile\":\"morphir-comparison-exact-v1\"}}}",
    ),
    Some({ "id": 1, "status": "invalid", "code": "execution.expected_struct" }),
  )
}

///|
test "binary source byte budget excludes the hex wrapper and frame overhead" {
  // Empty Ion input expressed as NOP bytes is intentionally a codec rejection.
  // At the exact raw-source limit it must reach that codec, rather than being
  // rejected by the larger hexadecimal transport representation.
  let source = "00".repeat(1048576)
  assert_eq(
    @mck.handle_line(
      Json::object({
        "id": 1,
        "op": "transcode-invocations",
        "suite": "workbench",
        "contractVersion": "0.1.0-draft.26",
        "format": "json",
        "input": {
          "sourceFormat": "ion-binary",
          "source": { "hex": source },
          "targetFormat": "ion-binary",
        },
      }).stringify(),
    ),
    Some({ "id": 1, "status": "invalid", "code": "workbench.invalid_ion" }),
  )
}

///|
test "expanded codec framing does not relax historical or absolute line limits" {
  let old_request = Json::object({
    "id": 1,
    "op": "decode-value",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.1",
    "format": "ion-text",
    "input": " ".repeat(2097152),
  }).stringify()
  for line in [old_request, " ".repeat(3146753)] {
    let rejected = try {
      @mck.handle_line(line) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "codec kit transcodes actual invocation bytes across all destinations" {
  let suite : Json = {
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "exact",
        "entry": "codec:main#identity",
        "arguments": [{ "type": "int", "value": "9007199254740993" }],
      },
    ],
  }
  for target in ["json", "ion-text", "ion-binary"] {
    assert_eq(
      codec_request("transcode-invocations", {
        "sourceFormat": "json",
        "source": { "utf8": suite.stringify() },
        "targetFormat": target,
      }),
      {
        "id": 1,
        "status": "ok",
        "value": { "targetFormat": target, "invocations": suite },
      },
    )
  }
}

///|
test "codec kit rejects duplicate raw suite members before projection" {
  assert_eq(
    codec_request("transcode-invocations", {
      "sourceFormat": "json",
      "source": {
        "utf8": "{\"profile\":\"morphir-invocations-v1\",\"calls\":[],\"calls\":[]}",
      },
      "targetFormat": "ion-binary",
    }),
    { "id": 1, "status": "invalid", "code": "execution.invalid_field" },
  )
}

///|
test "comparison kit uses normalized Decimal and escaped mismatch pointers" {
  assert_eq(
    codec_request("compare-values", {
      "actual": { "type": "decimal", "coefficient": "1250", "exponent": -2 },
      "expected": { "type": "decimal", "coefficient": "125", "exponent": -1 },
      "comparison": { "profile": "morphir-comparison-exact-v1" },
    }),
    {
      "id": 1,
      "status": "ok",
      "value": { "matches": true, "mismatchPath": Json::null() },
    },
  )
  assert_eq(
    codec_request("compare-values", {
      "actual": {
        "type": "record",
        "fields": [
          { "name": "a/b~c", "value": { "type": "bool", "value": true } },
        ],
      },
      "expected": {
        "type": "record",
        "fields": [
          { "name": "a/b~c", "value": { "type": "bool", "value": false } },
        ],
      },
      "comparison": { "profile": "morphir-comparison-exact-v1" },
    }),
    {
      "id": 1,
      "status": "ok",
      "value": { "matches": false, "mismatchPath": "/a~1b~0c" },
    },
  )
}
