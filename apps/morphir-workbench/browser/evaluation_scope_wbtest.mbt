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

///|
fn policy_scope_model() -> Model {
  {
    ..scope_model(),
    jobs_available: false,
    evaluation_typed: true,
    evaluation_policy: "strict",
    local_evaluator: "scheme-portable-v1/shared-sdk/bounded",
    model: {
      "capabilityEvaluations": {
        "evaluator": "scheme-portable-v1/shared-sdk/bounded",
        "admission": {
          "profile": "morphir/workbench/admission",
          "contractVersion": "0.1.0-draft.1",
          "policies": ["strict", "permissive"],
        },
        "entries": {
          "original": {
            "supported": true,
            "default": [],
            "inputs": [],
            "output": { "type": "int" },
            "definitions": [],
          },
          "unsupported": {
            "supported": false,
            "reason": "execution.boundary_function",
          },
        },
      },
    },
  }
}

///|
test "policy changes retain exact drafts and source profiles while making results stale" {
  let model = {
    ..policy_scope_model(),
    source_profile: "moonbit-model-library-2026-10-17",
    evaluation_mode: @evaluation.Ion,
    evaluation_arguments: "[invalid Ion draft",
    evaluation_result_revision: 0,
  }
  let (after, _) = update(
    model,
    EvaluationPolicy("permissive"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(after.evaluation_policy, "permissive")
  assert_eq(after.evaluation_arguments, model.evaluation_arguments)
  assert_true(after.evaluation_mode == model.evaluation_mode)
  assert_eq(after.source_profile, model.source_profile)
  assert_eq(after.evaluation_result, model.evaluation_result)
  assert_true(after.evaluation_revision != after.evaluation_result_revision)
  assert_eq(after.job, model.job)
}

///|
test "local checking offer is scoped to the actual evaluator entry and complete boundary" {
  let model = policy_scope_model()
  assert_true(checking_available(model))
  for
    incompatible in [
      { ..model, connected: true, },
      { ..model, jobs_available: true, },
      { ..model, local_evaluator: "", },
      { ..model, local_evaluator: "some-other-evaluator", },
      { ..model, selected: "value|unsupported", },
      { ..model, selected: "value|private", },
      { ..model, evaluation_typed: false, },
    ] {
    assert_false(checking_available(incompatible))
    let (after, _) = update(
      incompatible,
      EvaluationPolicy("permissive"),
      @cmd.Emit(fn(_) { @cmd.none }),
    )
    assert_eq(after.evaluation_policy, "strict")
  }
  let requested = { ..model, evaluation_policy: "permissive", connected: true, }
  let (blocked, _) = update(requested, Evaluate, @cmd.Emit(fn(_) { @cmd.none }))
  assert_eq(blocked.evaluation_policy, "permissive")
  assert_eq(blocked.job, requested.job)
  let (strict, _) = update(
    blocked,
    EvaluationPolicy("strict"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(strict.evaluation_policy, "strict")
}

///|
test "editing policy during execution never rewrites the completed run selection" {
  let running = {
    ..policy_scope_model(),
    busy: true,
    job: 7,
    evaluation_policy: "permissive",
  }
  let (edited, _) = update(
    running,
    EvaluationPolicy("strict"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(edited.job, running.job)
  assert_true(edited.busy)
  let reply : Json = {
    "success": true,
    "value": "42",
    "admission": {
      "profile": "morphir/workbench/admission",
      "contractVersion": "0.1.0-draft.1",
      "policy": "permissive",
    },
  }
  let (finished, _) = update(
    edited,
    Receive(7, running.evaluation_revision, "evaluate", reply.stringify()),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(finished.evaluation_policy, "strict")
  assert_eq(
    text(field(finished.evaluation_result, "admission"), "policy"),
    "permissive",
  )
  assert_true(
    finished.evaluation_revision != finished.evaluation_result_revision,
  )
  assert_false(finished.busy)
}

///|
test "bounded local descriptions preserve existing strict entries without granting a policy offer" {
  let base = policy_scope_model()
  guard base.model is Object(data) else { abort("model object") }
  data["typedEvaluations"] = {
    "entries": {
      "outside": {
        "supported": true,
        "inputs": [],
        "default": [],
        "definitions": [],
      },
    },
  }
  let model = { ..base, selected: "value|outside", }
  assert_true(
    field(
      evaluation_profile(model.model, model.selected, true, standalone=true),
      "supported",
    ) ==
    Json::boolean(true),
  )
  assert_false(checking_available(model))
  let (after, _) = update(
    model,
    EvaluationPolicy("permissive"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  assert_eq(after.evaluation_policy, "strict")
}
