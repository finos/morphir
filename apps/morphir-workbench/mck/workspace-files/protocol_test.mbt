///|
fn request(operation : String, input : Json) -> Json {
  @mck.handle_line(
    (
      {
        "id": 1,
        "op": operation,
        "suite": @mck.SUITE,
        "contractVersion": @mck.VERSION,
        "format": "json",
        "input": input,
      } : Json).stringify(),
  ).unwrap()
}

///|
fn encoded(text : String) -> Json {
  { "encoding": "utf8", "source": text }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
test "file capability witness exposes file and directory changes with exact bytes" {
  let baseline = encoded(
    "{\"version\":1,\"files\":{\"old/main.scm\":\"11\",\"keep/main.scm\":\"22\"}}",
  )
  let candidate = encoded(
    "{\"version\":1,\"files\":{\"new/main.scm\":\"33\",\"keep/main.scm\":\"44\",\"models/raw\":{\"encoding\":\"base64\",\"content\":\"AP+A\"}}}",
  )
  let result = request("observe-file-edit", {
    "baseline": baseline,
    "candidate": candidate,
    "directories": ["", "old", "keep", "empty"],
  })
  assert_eq(field(result, "status"), Json::string("ok"))
  let value = field(result, "value")
  assert_eq(
    field(value, "writes"),
    (
      { "new/main.scm": "MzM=", "keep/main.scm": "NDQ=", "models/raw": "AP+A" } :
      Json),
  )
  assert_eq(field(value, "deletes"), (["old/main.scm"] : Json))
  assert_eq(field(value, "createDirectories"), (["models", "new"] : Json))
  assert_eq(field(value, "removeDirectories"), (["old"] : Json))
}

///|
test "file capability witness refuses renderer paths and operation or session substitution" {
  let frame = "{\"profile\":\"morphir/workbench/workspace-files\",\"contractVersion\":\"0.1.0-draft.1\",\"operation\":\"workspace.commit\",\"sessionId\":\"page\",\"payload\":{\"grantId\":\"folder\",\"sequence\":2}}"
  assert_eq(
    field(request("validate-request", encoded(frame)), "status"),
    Json::string("ok"),
  )
  let reply = "{\"profile\":\"morphir/workbench/workspace-files\",\"contractVersion\":\"0.1.0-draft.1\",\"operation\":\"workspace.commit\",\"sessionId\":\"other\",\"ok\":true,\"value\":{\"sequence\":2,\"revision\":3}}"
  assert_eq(
    field(
      request("validate-reply", {
        "request": encoded(frame),
        "reply": encoded(reply),
      }),
      "code",
    ),
    Json::string("workspace_files.session"),
  )
  let invalid = encoded("{\"version\":1,\"files\":{\"../outside\":\"11\"}}")
  assert_eq(
    field(
      request("observe-file-edit", {
        "baseline": encoded("{\"version\":1,\"files\":{}}"),
        "candidate": invalid,
        "directories": [""],
      }),
      "code",
    ),
    Json::string("workspace_files.path"),
  )
}
