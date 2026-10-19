///|
test "workspace selection preserves displayed model and selection" {
  let original : Json = {
    "package": "already displayed",
    "sourceFormatVersion": "1.0.0",
    "modelSource": {
      "kind": "original-file",
      "filename": "original.json",
      "codec": "morphir-json",
      "formatVersion": "1.0.0",
      "contentBase64": "AQID",
    },
  }
  let model = {
    ..scope_model(),
    document: test_document(original),
    busy: true,
    request_id: 7,
  }
  let projects : Array[Json] = [
    { "id": "project-1", "name": "demo", "available": true },
  ]
  let (after, _) = update(
    model,
    Receive(
      7,
      model.revision,
      "workspace",
      (
        {
          "success": true,
          "operation": "workspace",
          "projects": projects,
          "message": "Workspace opened",
        } : Json).stringify(),
    ),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_false(after.busy)
  assert_eq(after.document, model.document)
  assert_eq(after.document.original().unwrap().copy_bytes(), b"\x01\x02\x03")
  assert_eq(after.selected, model.selected)
  assert_eq(after.projects, projects)
}

///|
test "workspace chooser cannot replace a retained host submission" {
  let model = {
    ..scope_model(),
    host_submitting: true,
    busy: true,
    request_id: 7,
  }
  let (after, _) = update(
    model,
    Request("workspace"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(after.request_id, 7)
  assert_true(after.host_submitting)
  assert_eq(after.document.inspection(), model.document.inspection())
  assert_eq(
    after.status,
    "Resume or finish the retained host execution before replacing the model",
  )
}
