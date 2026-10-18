///|
pub using @execution {type CapabilityPolicy}

///|
pub(all) suberror Invalid {
  InvalidProfile
  InvalidPolicy
}

///|
/// A recognized evaluator identity, decoded from the actual worker catalog.
pub(all) enum Evaluator {
  SchemePortable
} derive(Eq)

///|
pub extend Evaluator with Eq::{equal, not_equal}

///|
pub fn Evaluator::from_json(value : Json) -> Evaluator? {
  match value {
    String("scheme-portable-v1/shared-sdk/bounded") => Some(SchemePortable)
    _ => None
  }
}

///|
pub fn Evaluator::to_json(self : Evaluator) -> Json {
  match self {
    SchemePortable => Json::string("scheme-portable-v1/shared-sdk/bounded")
  }
}

///|
pub fn policy_from_control(value : String) -> CapabilityPolicy? {
  match value {
    "strict" => Some(@execution.Strict)
    "permissive" => Some(@execution.Permissive)
    _ => None
  }
}

///|
pub fn policy_value(policy : CapabilityPolicy) -> String {
  match policy {
    Strict => "strict"
    Permissive => "permissive"
  }
}

///|
pub fn policy_label(policy : CapabilityPolicy) -> String {
  match policy {
    Strict => "Whole model before running"
    Permissive => "As code executes"
  }
}

///|
/// Compatibility codec. Historical wire names stay here, outside domain state.
pub fn selection_from_json(value : Json) -> CapabilityPolicy raise Invalid {
  guard value is Object(fields) &&
    fields.length() == 3 &&
    fields.get("profile") == Some(Json::string("morphir/workbench/admission")) &&
    fields.get("contractVersion") == Some(Json::string("0.1.0-draft.1")) else {
    raise InvalidProfile
  }
  match fields.get("policy") {
    Some(String(value)) =>
      match policy_from_control(value) {
        Some(policy) => policy
        None => raise InvalidPolicy
      }
    _ => raise InvalidPolicy
  }
}

///|
pub fn selection_to_json(policy : CapabilityPolicy) -> Json {
  {
    "profile": "morphir/workbench/admission",
    "contractVersion": "0.1.0-draft.1",
    "policy": policy_value(policy),
  }
}

///|
pub fn policy_offer() -> Json {
  {
    "profile": "morphir/workbench/admission",
    "contractVersion": "0.1.0-draft.1",
    "policies": [
      policy_value(@execution.Strict),
      policy_value(@execution.Permissive),
    ],
  }
}

///|
/// An offer is evidence for this evaluator and selected entry only.
pub fn supports_checks(
  offer : Json,
  evaluator : Evaluator,
  entry : String,
) -> Bool {
  guard offer is Object(fields) &&
    fields.get("evaluator") == Some(evaluator.to_json()) &&
    fields.get("admission") is Some(Object(checks)) &&
    checks.get("profile") == Some(Json::string("morphir/workbench/admission")) &&
    checks.get("contractVersion") == Some(Json::string("0.1.0-draft.1")) &&
    checks.get("policies") == Some((["strict", "permissive"] : Json)) &&
    fields.get("entries") is Some(Object(entries)) &&
    entries.get(entry) is Some(Object(boundary)) else {
    return false
  }
  boundary.get("supported") == Some(Json::boolean(true))
}
