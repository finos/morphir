///|
extern "js" fn scope_test_environment() -> () -> Unit =
  #|() => {
  #|  const workbench = globalThis.morphirWorkbench, document = globalThis.document;
  #|  globalThis.morphirWorkbench = { connected: false };
  #|  globalThis.document = { querySelector: () => null };
  #|  return () => {
  #|    if (workbench === undefined) delete globalThis.morphirWorkbench; else globalThis.morphirWorkbench = workbench;
  #|    if (document === undefined) delete globalThis.document; else globalThis.document = document;
  #|  };
  #|}

///|
fn scope_model() -> Model {
  let restore = scope_test_environment()
  defer restore()
  {
    ..initial(),
    busy: false,
    jobs_available: true,
    selected: "value|original",
    evaluation_entry: "value|original",
    evaluation_result: { "success": true, "value": "42" },
  }
}

///|
test "local results clear on navigation even when native jobs are available" {
  let other = select(scope_model(), "value|other")
  assert_eq(other.evaluation_result, Json::null())
  assert_true(other.evaluation_terminal is Absent)
  assert_eq(select(other, "value|original").evaluation_result, Json::null())
}

///|
test "late local replies are refused after selecting another function" {
  let model = {
    ..scope_model(),
    selected: "value|other",
    busy: true,
    job: 7,
    evaluation_result: Json::null(),
  }
  let (after, _) = update(
    model,
    Receive(
      7,
      model.evaluation_revision,
      "evaluate",
      ({ "success": true, "value": "42" } : Json).stringify(),
    ),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(after.status, "Finished for another function")
  assert_eq(after.evaluation_result, Json::null())
  assert_false(after.busy)
}

///|
test "runtime changes cannot discard a pending host submission" {
  let model = {
    ..scope_model(),
    evaluation_typed: true,
    host_submitting: true,
    busy: true,
    job: 7,
  }
  let (after, _) = update(
    model,
    EvaluationRuntime(false),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_true(after.evaluation_typed)
  assert_eq(after.job, 7)
  assert_true(after.host_submitting)
}

///|
test "captured host results survive navigation independently of current job discovery" {
  let model = {
    ..scope_model(),
    evaluation_host_job: true,
    jobs_available: false,
    host_draft: Some({ arguments: "[]", mode: @evaluation.Fields, revision: 0, }),
  }
  let other = select(model, "value|other")
  assert_eq(other.evaluation_result, model.evaluation_result)
  let restored = select(other, "value|original")
  assert_eq(restored.evaluation_arguments, "[]")
  assert_eq(restored.evaluation_revision, 0)
  assert_eq(restored.evaluation_result, model.evaluation_result)
}
