///|
pub(all) enum Kind {
  Returned
  ModelError
  Failed
  Cancelled
} derive(Eq)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub(all) enum Level {
  Info
  Warning
  Error
} derive(Eq)

///|
pub extend Level with Eq::{equal, not_equal}

///|
pub(all) struct Call {
  id : String
  kind : Kind
  preview : String
  stage : String
  code : String
  message : String
} derive(Eq)

///|
pub extend Call with Eq::{equal, not_equal}

///|
pub(all) struct Cleanup {
  code : String
  message : String
} derive(Eq)

///|
pub extend Cleanup with Eq::{equal, not_equal}

///|
/// History retains previews, never the full canonical value tree.
pub(all) struct Summary {
  calls : Array[Call]
  omitted : Int32
  cleanup : Cleanup?
} derive(Eq)

///|
pub extend Summary with Eq::{equal, not_equal}

///|
pub(all) enum Projection {
  Absent
  Valid(Summary)
  Invalid(String)
} derive(Eq)

///|
pub extend Projection with Eq::{equal, not_equal}

///|
pub fn Kind::label(self : Kind) -> String {
  match self {
    Returned => "Returned"
    ModelError => "Model error"
    Failed => "Failed"
    Cancelled => "Cancelled"
  }
}

///|
pub fn Summary::level(self : Summary) -> Level {
  if self.cleanup != None || self.calls.any(c => c.kind == Failed) {
    Error
  } else if self.calls.any(c => c.kind == ModelError || c.kind == Cancelled) {
    Warning
  } else {
    Info
  }
}

///|
pub fn Summary::has_value(self : Summary) -> Bool {
  self.omitted == 0 &&
  self.calls.length() == 1 &&
  (self.calls[0].kind == Returned || self.calls[0].kind == ModelError)
}

///|
pub fn Summary::heading(self : Summary) -> String {
  (if self.calls.length() == 1 && self.omitted == 0 {
    self.calls[0].kind.label()
  } else {
    (self.calls.length() + self.omitted).to_string() + " calls"
  }) +
  (if self.cleanup == None { "" } else { " · Cleanup failed" })
}

///|
fn field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
pub fn bounded(value : String, limit : Int32) -> String {
  if value.length() <= limit {
    return value
  }
  let result = StringBuilder()
  let suffix = "… (truncated)"
  let available = if limit > suffix.length() {
    limit - suffix.length()
  } else {
    limit
  }
  let mut count = 0
  for char in value {
    let width = char.to_string().length()
    if count + width > available {
      break
    }
    result.write_char(char)
    count += width
  }
  result.to_string() + (if limit > suffix.length() { suffix } else { "" })
}

///|
fn summarize(outcomes : @execution.Outcomes) -> Summary {
  let count = if outcomes.calls.length() < 50 {
    outcomes.calls.length()
  } else {
    50
  }
  {
    calls: outcomes.calls[:count]
    .to_owned()
    .map(call => {
      let (kind, preview, stage, code, message) = match call.outcome {
        Returned(value) =>
          (Returned, bounded(value.to_json().stringify(), 4000), "", "", "")
        ModelError(code) =>
          (ModelError, "", "", code, "The model returned an SDK error.")
        Failed(failure) =>
          (Failed, "", stage_text(failure.stage), failure.code, failure.message)
        Cancelled => (Cancelled, "", "", "", "No value was returned.")
      }
      { id: call.id, kind, preview, stage, code, message, }
    }),
    omitted: outcomes.calls.length() - count,
    cleanup: outcomes.cleanup.map(f => { code: f.code, message: f.message, }),
  }
}

///|
fn stage_text(stage : @execution.OutcomeStage) -> String {
  match stage {
    Acquire => "acquire"
    Build => "build"
    Invoke => "invoke"
    Evaluate => "evaluate"
    Compare => "compare"
    Cleanup => "cleanup"
  }
}

///|
/// Decode once when receiving a result. A present malformed envelope never
/// falls back to a legacy success flag. Expected identities are caller-owned.
pub fn prepare(
  reply : Json,
  expected_ids~ : Array[String]? = None,
) -> (Json, Projection) {
  guard reply is Object(original) && original.contains("terminalOutcomes") else {
    return (reply, Absent)
  }
  let decoded = try {
    let outcomes = @execution.Outcomes::decode(
      @utf8.encode(field(reply, "terminalOutcomes").stringify()),
      "json",
    )
    if expected_ids is Some(ids) {
      if outcomes.calls.map(c => c.id) != ids {
        raise @execution.Invalid("execution.call_identity")
      }
    }
    outcomes
  } catch {
    error => {
      let reason = match error {
        @execution.Invalid(code) =>
          code.split(":").next().unwrap_or(code).to_owned()
        _ => "workbench.invalid_terminal_evidence"
      }
      return (
        { "success": false, "message": "Terminal evidence rejected: " + reason },
        Invalid(reason),
      )
    }
  }
  let summary = summarize(decoded)
  let fields = Map(original.iter().collect())
  for name in ["typed", "structured", "value", "outcome"] {
    fields.remove(name) |> ignore
  }
  fields["success"] = Json::boolean(
    decoded.cleanup == None &&
    decoded.calls.all(c => {
      c.outcome is Returned(_) || c.outcome is ModelError(_)
    }),
  )
  if decoded.calls.length() == 1 {
    let value = match decoded.calls[0].outcome {
      Returned(value) => Some(value.to_json())
      ModelError(code) => Some(@execution.Value::ModelError(code).to_json())
      _ => None
    }
    if value is Some(value) {
      fields["typed"] = value
      fields["structured"] = value_tree(value)
      fields["value"] = Json::string(value.stringify())
      fields["outcome"] = Json::string(
        if decoded.calls[0].outcome is ModelError(_) {
          "model-error"
        } else {
          "value"
        },
      )
    }
  }
  (Json::object(fields), Valid(summary))
}
