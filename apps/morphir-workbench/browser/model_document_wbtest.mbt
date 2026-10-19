///|
fn lifecycle_model() -> Model {
  {
    ..scope_model(),
    document: test_document({
      "success": true,
      "ir": { "formatVersion": 4 },
      "sourceFormatVersion": "1.0.0",
      "sourceUnitIon": "current source unit",
      "modelSource": {
        "kind": "original-file",
        "filename": "first.json",
        "codec": "morphir-json",
        "formatVersion": "1.0.0",
        "contentBase64": "AQID",
      },
    }),
    output: { "ir": { "previous": true }, "sourceUnitIon": "old source unit" },
    query: "search",
    collapsed_modules: ["module"],
  }
}

///|
test "close model releases owned views while preserving editor and worksheet inputs" {
  let before = lifecycle_model()
  let (after, _) = update(before, CloseModel, @cmd.Emit(fn(_) { @cmd.none }))
  assert_eq(after.document.document(), None)
  assert_eq(after.output, Json::null())
  assert_eq(after.selected, "")
  assert_eq(after.query, "")
  assert_eq(after.collapsed_modules, [])
  assert_true(after.history.is_empty())
  assert_eq(after.evaluation_result, Json::null())
  assert_eq(after.language_projects, before.language_projects)
  assert_eq(after.worksheet_source, before.worksheet_source)
  assert_true(after.worksheet_report == before.worksheet_report)
  assert_eq(after.host_execution, before.host_execution)
  assert_eq(after.model_revision, before.model_revision + 1)
  let (again, _) = update(after, CloseModel, @cmd.Emit(fn(_) { @cmd.none }))
  assert_eq(again.model_revision, after.model_revision)
  assert_eq(again.request_id, after.request_id)
}

///|
test "close refuses submitting and unknown host authority" {
  for unknown in [false, true] {
    let before = {
      ..lifecycle_model(),
      host_submitting: !unknown,
      submission_unknown: unknown,
      busy: true,
    }
    let (after, _) = update(before, CloseModel, @cmd.Emit(fn(_) { @cmd.none }))
    assert_eq(after.document, before.document)
    assert_eq(after.output, before.output)
    assert_eq(after.request_id, before.request_id)
    assert_true(after.status.contains("retained host execution"))
  }
}

///|
test "close pending open rejects late picker and inspection replies" {
  let before = lifecycle_model()
  let (document, attempt) = match before.document.begin(Idle) {
    Started(document, attempt) => (document, attempt)
    _ => abort("opening")
  }
  let pending = { ..before, document, busy: true, request_id: 8, }
  let (closed, _) = update(pending, CloseModel, @cmd.Emit(fn(_) { @cmd.none }))
  assert_false(closed.busy)
  let (late_picker, _) = update(
    closed,
    Imported(attempt, "malformed late picker"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(late_picker.document.document(), None)
  assert_eq(late_picker.request_id, closed.request_id)
  let (late_reply, _) = update(
    closed,
    ReceiveModel(attempt, 8, before.revision, "inspect", "malformed late reply"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(late_reply.document.document(), None)
  assert_eq(late_reply.status, closed.status)
}

///|
test "stale download controls cannot download a replacement model" {
  let before = lifecycle_model()
  let revision = before.document.current_revision().unwrap()
  // Replace through the same owner so identity cannot collide with a new owner.
  let replacement = {
    ..before,
    document: before.document.replace({ "ir": { "other": true } }) catch {
      _ => abort("replacement")
    },
  }
  for message in [DownloadOriginal(revision), DownloadSourceUnit(revision)] {
    let (after, _) = update(
      replacement,
      message,
      @cmd.Emit(fn(_) { @cmd.none }),
    )
    assert_eq(after.status, replacement.status)
    assert_eq(after.document, replacement.document)
  }
}
