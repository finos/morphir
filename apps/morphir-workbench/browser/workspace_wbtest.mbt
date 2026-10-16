///|
test "workspace selection preserves displayed model and selection" {
  let original : Json = {
    "package": "already displayed",
    "originalArtifact": { "content": "AQID" },
  }
  let model = { ..scope_model(), model: original, busy: true, job: 7, }
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
  assert_eq(after.model, original)
  assert_eq(after.selected, model.selected)
  assert_eq(after.projects, projects)
}

///|
test "workspace chooser cannot replace a retained host submission" {
  let model = { ..scope_model(), host_submitting: true, busy: true, job: 7, }
  let (after, _) = update(
    model,
    Request("workspace"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(after.job, 7)
  assert_true(after.host_submitting)
  assert_eq(after.model, model.model)
  assert_eq(
    after.status,
    "Resume or finish the retained host job before replacing the model",
  )
}
