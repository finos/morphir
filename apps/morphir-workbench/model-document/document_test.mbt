///|
fn original_reply(
  name~ : String = "model.json",
  version~ : String = "1.0.0",
  encoded~ : String = "77u/ew0KfQ==",
) -> Json {
  {
    "success": true,
    "ir": {
      "formatVersion": 4,
      "originalArtifact": "legitimate nested model data",
    },
    "formatVersion": "4.0.0",
    "sourceFormatVersion": version,
    "modelSource": {
      "kind": "original-file",
      "filename": name,
      "codec": "morphir-json",
      "formatVersion": version,
      "contentBase64": encoded,
    },
    "originalArtifact": { "content": "retired private envelope" },
  }
}

///|
fn start(state : @document.State) -> (@document.State, @document.OpenAttempt) {
  match state.begin(Idle) {
    Started(state, attempt) => (state, attempt)
    _ => abort("expected opening")
  }
}

///|
fn original(state : @document.State) -> @document.OriginalFile {
  match state.document().unwrap().source {
    Original(file) => file
    _ => abort("expected original")
  }
}

///|
test "original ownership preserves exact bytes and separates source version" {
  let (state, attempt) = start(@document.State::new())
  let loaded = state.finish(attempt, original_reply())
  let file = original(loaded)
  assert_eq(file.format_version.to_release_string(), "1.0.0")
  assert_eq(file.copy_bytes(), b"\xef\xbb\xbf{\r\n}")
  assert_eq(file.byte_length(), 7)
  assert_eq(file.download(), {
    "path": "model.json",
    "content": "77u/ew0KfQ==",
    "binary": true,
    "encoding": "base64",
  })
  guard loaded.inspection() is Object(view) else { abort("inspection") }
  assert_false(view.contains("modelSource"))
  assert_false(view.contains("originalArtifact"))
  assert_eq(view["ir"], {
    "formatVersion": 4,
    "originalArtifact": "legitimate nested model data",
  })
}

///|
test "failed and late replacements keep the last usable original" {
  let (first, token) = start(@document.State::new())
  let loaded = first.finish(token, original_reply())
  let (opening, failed) = start(loaded)
  assert_eq(original(opening).download(), original(loaded).download())
  let rejected = opening.reject(failed)
  assert_eq(original(rejected).download(), original(loaded).download())
  let (newer, current) = start(rejected)
  assert_false(newer.is_current(failed))
  // A stale malformed offer must not even be decoded.
  let stale = newer.finish(failed, Json::null())
  assert_eq(stale.opening(), Some(current))
  assert_eq(original(stale).download(), original(loaded).download())
  let replaced = stale.finish(
    current,
    original_reply(name="replacement.json", encoded=""),
  )
  assert_eq(original(replaced).download(), {
    "path": "replacement.json",
    "content": "",
    "binary": true,
    "encoding": "base64",
  })
}

///|
test "close retires both current and pending ownership without resurrection" {
  let (first, token) = start(@document.State::new())
  let loaded = first.finish(token, original_reply())
  let (opening, pending) = start(loaded)
  let closed = match opening.close(Idle) {
    Closed(state, Some(cancel)) => {
      assert_eq(cancel, pending)
      state
    }
    _ => abort("close")
  }
  assert_eq(closed.document(), None)
  assert_eq(closed.inspection(), Json::null())
  assert_eq(closed.opening(), None)
  let late = closed.finish(pending, original_reply())
  assert_eq(late.document(), None)
  let (next, next_token) = start(closed)
  assert_false(next_token == pending)
  assert_eq(next.finish(pending, original_reply()).document(), None)
  match closed.close(Idle) {
    Closed(again, None) => assert_eq(again.inspection(), Json::null())
    _ => abort("idempotent close")
  }
}

///|
test "every retained or uncertain host state refuses opening and closing" {
  let (opening, token) = start(@document.State::new())
  let loaded = opening.finish(token, original_reply())
  for host in [@document.Submitting, Running, Disconnected, UnknownSubmission] {
    match loaded.begin(host) {
      Refused(reason) => assert_eq(reason, host)
      _ => abort("retained host opened")
    }
    match loaded.close(host) {
      Retained(reason) => assert_eq(reason, host)
      _ => abort("retained host closed")
    }
    assert_eq(original(loaded).byte_length(), 7)
  }
}

///|
test "missing provenance is explicitly a projection without original download" {
  let state = @document.State::new().replace({
    "success": true,
    "ir": { "formatVersion": 4 },
  })
  assert_true(
    state.document().unwrap().source is Projection(OriginalsNotProvided),
  )
}

///|
test "download revisions reject replaced and closed documents" {
  let first = @document.State::new().replace(original_reply())
  let revision = first.current_revision().unwrap()
  assert_eq(first.original_for(revision).unwrap().byte_length(), 7)
  let (opening, attempt) = start(first)
  assert_eq(opening.original_for(revision).unwrap().byte_length(), 7)
  let replacement = opening.finish(attempt, original_reply(name="next.json"))
  assert_eq(replacement.original_for(revision), None)
  let current = replacement.current_revision().unwrap()
  let closed = match replacement.close(Idle) {
    Closed(state, _) => state
    _ => abort("close")
  }
  assert_eq(closed.original_for(current), None)
  let reopened = closed.replace(original_reply())
  assert_eq(reopened.original_for(current), None)
}

///|
test "original offers reject inconsistent versions unsafe names and malformed bytes" {
  for
    reply in [
      original_reply(name="../model.json"),
      original_reply(name=""),
      original_reply(name="model\u0000.json"),
      original_reply(encoded="%%%%"),
      original_reply(encoded="YR=="), // Noncanonical unused base64 bits.
      original_reply(version="99.0.0"),
    ] {
    let (state, token) = start(@document.State::new())
    let failed = try {
      ignore(state.finish(token, reply))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(state.reject(token).document(), None)
  }
  let reply = original_reply()
  guard reply is Object(fields) else { abort("reply") }
  let fields = fields.copy()
  fields["sourceFormatVersion"] = Json::string("2.0.0")
  let failed = try {
    ignore(@document.Document::from_reply(Json::object(fields)))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
