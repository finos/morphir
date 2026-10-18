///|
test "MCK envelopes retain their independent complete 2-MiB budget" {
  let text = " ".repeat(1048576) + "{\"input\":null}"
  assert_eq(mck_json(text), ({ "ok": true, "value": { "input": null } } : Json))
  assert_eq(
    mck_json(" ".repeat(2097151) + "0"),
    ({ "ok": true, "value": 0 } : Json),
  )
  assert_eq(
    mck_json(" ".repeat(2097152) + "0"),
    ({ "ok": false, "code": "workbench.mck_frame_limit" } : Json),
  )
  assert_eq(
    mck_json("\"" + "😀".repeat(524288) + "\""),
    ({ "ok": false, "code": "workbench.mck_frame_limit" } : Json),
  )
}

///|
test "MCK JSON parsing preserves opaque objects and rejects duplicate or trailing content" {
  assert_eq(
    mck_json("{\"$serde_json::private::Number\":\"1\"}"),
    ({ "ok": true, "value": { "$serde_json::private::Number": "1" } } : Json),
  )
  for text in ["{\"policy\":1,\"po\\u006cicy\":2}", "{}{}", "[1,]"] {
    assert_eq(
      mck_json(text),
      ({ "ok": false, "code": "workbench.invalid_json" } : Json),
    )
  }
}
