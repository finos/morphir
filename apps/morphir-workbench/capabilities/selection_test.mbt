///|
test "policy codecs preserve exact selections and reject malformed compatibility data" {
  for policy in [@execution.Strict, @execution.Permissive] {
    assert_eq(
      @capabilities.selection_from_json(@capabilities.selection_to_json(policy)),
      policy,
    )
    assert_eq(
      @capabilities.policy_from_control(@capabilities.policy_value(policy)),
      Some(policy),
    )
  }
  assert_eq(@capabilities.policy_from_control(""), None)
  assert_eq(@capabilities.policy_from_control("Strict"), None)
  for
    invalid in [
      Json::null(),
      Json::string("strict"),
      ({ "policy": "strict" } : Json),
      (
        {
          "profile": "other",
          "contractVersion": "0.1.0-draft.1",
          "policy": "strict",
        } : Json),
      (
        {
          "profile": "morphir/workbench/admission",
          "contractVersion": "future",
          "policy": "strict",
        } : Json),
      (
        {
          "profile": "morphir/workbench/admission",
          "contractVersion": "0.1.0-draft.1",
          "policy": "other",
        } : Json),
      (
        {
          "profile": "morphir/workbench/admission",
          "contractVersion": "0.1.0-draft.1",
          "policy": "strict",
          "extra": true,
        } : Json),
    ] {
    let rejected = try {
      ignore(@capabilities.selection_from_json(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "evaluator recognition and checking offers cannot grant support to another entry" {
  assert_true(
    @capabilities.Evaluator::from_json(@capabilities.SchemePortable.to_json()) ==
    Some(@capabilities.SchemePortable),
  )
  assert_true(
    @capabilities.Evaluator::from_json(Json::string("unknown")) is None,
  )
  assert_true(@capabilities.Evaluator::from_json(Json::null()) is None)
  let offer : Json = {
    "evaluator": @capabilities.SchemePortable.to_json(),
    "admission": @capabilities.policy_offer(),
    "entries": {
      "public": { "supported": true },
      "unsupported": { "supported": false },
    },
  }
  assert_true(
    @capabilities.supports_checks(offer, @capabilities.SchemePortable, "public"),
  )
  assert_false(
    @capabilities.supports_checks(
      offer,
      @capabilities.SchemePortable,
      "unsupported",
    ),
  )
  assert_false(
    @capabilities.supports_checks(
      offer,
      @capabilities.SchemePortable,
      "private",
    ),
  )
  assert_false(
    @capabilities.supports_checks(
      Json::null(),
      @capabilities.SchemePortable,
      "public",
    ),
  )
  guard offer is Object(fields) else { abort("offer object") }
  fields["evaluator"] = Json::string("unknown")
  assert_false(
    @capabilities.supports_checks(offer, @capabilities.SchemePortable, "public"),
  )
}
