///|
/// Exact prerelease Workbench terminal evidence, separate from frozen driver v1.
pub(all) enum TerminalOutcome {
  Returned(Value)
  ModelError(String)
  Failed(OutcomeFailure)
  Cancelled
} derive(Eq, Debug)

///|
pub extend TerminalOutcome with Eq::{equal, not_equal}

///|
pub extend TerminalOutcome with @debug.Debug::{to_repr}

///|
pub(all) enum OutcomeStage {
  Acquire
  Build
  Invoke
  Evaluate
  Compare
  Cleanup
} derive(Eq, Debug)

///|
pub extend OutcomeStage with Eq::{equal, not_equal}

///|
pub extend OutcomeStage with @debug.Debug::{to_repr}

///|
pub(all) struct OutcomeFailure {
  stage : OutcomeStage
  code : String
  message : String
} derive(Eq, Debug)

///|
pub extend OutcomeFailure with Eq::{equal, not_equal}

///|
pub extend OutcomeFailure with @debug.Debug::{to_repr}

///|
pub(all) struct CallOutcome {
  id : String
  outcome : TerminalOutcome
} derive(Eq, Debug)

///|
pub extend CallOutcome with Eq::{equal, not_equal}

///|
pub extend CallOutcome with @debug.Debug::{to_repr}

///|
pub(all) struct Outcomes {
  calls : Array[CallOutcome]
  cleanup : OutcomeFailure?
  extensions : Bytes?
} derive(Eq, Debug)

///|
pub extend Outcomes with Eq::{equal, not_equal}

///|
pub extend Outcomes with @debug.Debug::{to_repr}

///|
fn OutcomeStage::text(self : OutcomeStage) -> String {
  match self {
    Acquire => "acquire"
    Build => "build"
    Invoke => "invoke"
    Evaluate => "evaluate"
    Compare => "compare"
    Cleanup => "cleanup"
  }
}

///|
fn outcome_stage(value : @ion.IonValue) -> OutcomeStage raise {
  match string(value) {
    "acquire" => Acquire
    "build" => Build
    "invoke" => Invoke
    "evaluate" => Evaluate
    "compare" => Compare
    "cleanup" => Cleanup
    _ => raise Invalid("workbench.invalid_failure")
  }
}

///|
fn OutcomeFailure::validate(
  self : OutcomeFailure,
  cleanup : Bool,
) -> Unit raise {
  if (self.stage is Cleanup) != cleanup ||
    self.code.length() == 0 ||
    self.code.length() > 128 ||
    self.message.length() > 512 ||
    (
      !cleanup &&
      (valid_model_error(self.code) || self.code == "execution.cancelled")
    ) {
    raise Invalid("workbench.invalid_failure")
  }
}

///|
fn OutcomeFailure::to_json(self : OutcomeFailure) -> Json {
  { "stage": self.stage.text(), "code": self.code, "message": self.message }
}

///|
fn OutcomeFailure::to_ion(self : OutcomeFailure) -> @ion.IonValue {
  record([
    ("stage", @ion.IonValue::string(self.stage.text())),
    ("code", @ion.IonValue::string(self.code)),
    ("message", @ion.IonValue::string(self.message)),
  ])
}

///|
fn outcome_fields(
  value : @ion.IonValue,
  names : Array[String],
  code : String,
) -> Map[String, @ion.IonValue] raise {
  if value.has_annotations() {
    raise Invalid(code)
  }
  let f = fields(value, names) catch { _ => raise Invalid(code) }
  if f.length() != names.length() {
    raise Invalid(code)
  }
  f
}

///|
fn outcome_failure(
  value : @ion.IonValue,
  cleanup : Bool,
) -> OutcomeFailure raise {
  let code = "workbench.invalid_failure"
  let f = outcome_fields(value, ["stage", "code", "message"], code)
  let failure = OutcomeFailure::{
    stage: outcome_stage(required(f, "stage")),
    code: string(required(f, "code")),
    message: string(required(f, "message")),
  } catch {
    _ => raise Invalid(code)
  }
  failure.validate(cleanup)
  failure
}

///|
fn TerminalOutcome::to_json(self : TerminalOutcome) -> Json {
  match self {
    Returned(value) => { "status": "returned", "value": value.to_json() }
    ModelError(code) => { "status": "model-error", "code": code }
    Failed(failure) => { "status": "failed", "failure": failure.to_json() }
    Cancelled => { "status": "cancelled" }
  }
}

///|
fn TerminalOutcome::to_ion(self : TerminalOutcome) -> @ion.IonValue {
  match self {
    Returned(value) =>
      record([
        ("status", @ion.IonValue::string("returned")),
        ("value", value.to_ion()),
      ])
    ModelError(code) =>
      record([
        ("status", @ion.IonValue::string("model-error")),
        ("code", @ion.IonValue::string(code)),
      ])
    Failed(failure) =>
      record([
        ("status", @ion.IonValue::string("failed")),
        ("failure", failure.to_ion()),
      ])
    Cancelled => record([("status", @ion.IonValue::string("cancelled"))])
  }
}

///|
fn terminal_outcome(
  value : @ion.IonValue,
  json : Bool,
) -> TerminalOutcome raise {
  let code = "workbench.invalid_outcome"
  let f = fields(value, ["status", "value", "code", "failure"]) catch {
    _ => raise Invalid(code)
  }
  let status = string(required(f, "status")) catch { _ => raise Invalid(code) }
  let names = match status {
    "returned" => ["status", "value"]
    "model-error" => ["status", "code"]
    "failed" => ["status", "failure"]
    "cancelled" => ["status"]
    _ => raise Invalid(code)
  }
  let f = outcome_fields(value, names, code)
  match status {
    "returned" => {
      let v = required(f, "value")
      let value = if json { payload_value(v, 0) } else { Value::from_ion(v) }
      if value is ModelError(_) {
        raise Invalid(code)
      }
      Returned(value)
    }
    "model-error" => {
      let model_code = string(required(f, "code")) catch {
        _ => raise Invalid("execution.model_error_code")
      }
      if !valid_model_error(model_code) {
        raise Invalid("execution.model_error_code")
      }
      ModelError(model_code)
    }
    "failed" => Failed(outcome_failure(required(f, "failure"), false))
    "cancelled" => Cancelled
    _ => abort("checked terminal status")
  }
}

///|
pub fn Outcomes::validate(self : Outcomes) -> Unit raise {
  if self.calls.is_empty() || self.calls.length() > 1000 {
    raise Invalid("execution.result_count")
  }
  let seen : Map[String, Bool] = Map([])
  for call in self.calls {
    if call.id == "" || call.id.length() > 128 || seen.contains(call.id) {
      raise Invalid("execution.call_identity")
    }
    seen[call.id] = true
    match call.outcome {
      Returned(value) => {
        if value is ModelError(_) {
          raise Invalid("workbench.invalid_outcome")
        }
        validate_value(value, 0, Ref(100000))
      }
      ModelError(code) =>
        if !valid_model_error(code) {
          raise Invalid("execution.model_error_code")
        }
      Failed(failure) => failure.validate(false)
      Cancelled => ()
    }
  }
  if self.cleanup is Some(failure) {
    failure.validate(true)
  }
  if self.extensions is Some(bytes) {
    if bytes.length() > 65536 {
      raise Invalid("execution.extension_limit")
    }
    ignore(@binary.read_binary_value(bytes[:]))
  }
}

///|
pub fn Outcomes::to_json(self : Outcomes) -> Json {
  {
    "contractVersion": "0.1.0-draft.5",
    "calls": self.calls.map(call => {
      ({ "id": call.id, "outcome": call.outcome.to_json() } : Json)
    }),
    "cleanup": self.cleanup.map(OutcomeFailure::to_json).unwrap_or(Json::null()),
    "extensions": match self.extensions {
      Some(bytes) =>
        {
          "format": "ion-binary",
          "bytes": bytes.to_array().map(b => b.to_int()),
        }
      None => Json::null()
    },
  }
}

///|
/// Ion keeps exact native returned values and opaque extension bytes in a blob.
pub fn Outcomes::to_ion(self : Outcomes) -> @ion.IonValue raise {
  self.validate()
  record([
    ("contractVersion", @ion.IonValue::string("0.1.0-draft.5")),
    (
      "calls",
      @ion.IonValue::list(
        self.calls.map(call => {
          record([
            ("id", @ion.IonValue::string(call.id)),
            ("outcome", call.outcome.to_ion()),
          ])
        }),
      ),
    ),
    (
      "cleanup",
      self.cleanup
      .map(OutcomeFailure::to_ion)
      .unwrap_or(@ion.IonValue::untyped_null()),
    ),
    (
      "extensions",
      self.extensions
      .map(@ion.IonValue::blob)
      .unwrap_or(@ion.IonValue::untyped_null()),
    ),
  ])
}

///|
fn absent_outcome_field(value : @ion.IonValue) -> Bool {
  !value.has_annotations() && value.kind() is Null(@ion.Null)
}

///|
fn read_outcomes(value : @ion.IonValue, json : Bool) -> Outcomes raise {
  let f = outcome_fields(
    value,
    ["contractVersion", "calls", "cleanup", "extensions"],
    "workbench.invalid_outcomes",
  )
  if string(required(f, "contractVersion")) != "0.1.0-draft.5" {
    raise Invalid("workbench.invalid_outcomes")
  }
  let calls = list(required(f, "calls"))
  if calls.is_empty() || calls.length() > 1000 {
    raise Invalid("execution.result_count")
  }
  let cleanup = required(f, "cleanup")
  let extensions = required(f, "extensions")
  let result = Outcomes::{
    calls: calls.map(call => {
      let f = outcome_fields(
        call,
        ["id", "outcome"],
        "workbench.invalid_outcomes",
      )
      CallOutcome::{
        id: string(required(f, "id")),
        outcome: terminal_outcome(required(f, "outcome"), json),
      }
    }),
    cleanup: if absent_outcome_field(cleanup) {
      None
    } else {
      Some(outcome_failure(cleanup, true))
    },
    extensions: if absent_outcome_field(extensions) {
      None
    } else if json {
      Some(json_extension(extensions))
    } else {
      if extensions.has_annotations() {
        raise Invalid("execution.unexpected_annotation")
      }
      match extensions.kind() {
        Blob(bytes) => Some(bytes)
        _ => raise Invalid("execution.extension_format")
      }
    },
  }
  result.validate()
  result
}

///|
pub fn Outcomes::from_json(value : Json) -> Outcomes raise {
  read_outcomes(@text.read_ion(value.stringify()[:]), true)
}

///|
pub fn Outcomes::from_ion(value : @ion.IonValue) -> Outcomes raise {
  read_outcomes(value, false)
}

///|
pub fn Outcomes::decode(bytes : Bytes, format : String) -> Outcomes raise {
  if bytes.length() > 1048576 {
    raise Invalid("execution.input_limit")
  }
  let source = @utf8.decode(bytes[:])
  match format {
    "json" => {
      ignore(@json.parse(source))
      read_outcomes(@text.read_ion(source[:]), true)
    }
    "ion-text" => read_outcomes(@text.read_ion(source[:]), false)
    _ => raise Invalid("execution.unsupported_format")
  }
}

///|
/// Admission succeeds for well-formed failed/cancelled evidence too. It neither
/// runs nor authenticates a job. Caller admits declarations before this function.
pub fn validate_outcomes(
  outcomes : Outcomes,
  suite : Suite,
  entries : Array[PublicEntry],
  definitions : Array[CustomType],
) -> Unit raise {
  validate_invocations(suite, entries, definitions)
  outcomes.validate()
  if outcomes.calls.length() != suite.calls.length() {
    raise Invalid("execution.result_count")
  }
  if outcomes.extensions != suite.extensions {
    raise Invalid("execution.outcome_extensions")
  }
  for i = 0; i < outcomes.calls.length(); i = i + 1 {
    let call = outcomes.calls[i]
    if call.id != suite.calls[i].id {
      raise Invalid("execution.call_identity")
    }
    let entry = entries.filter(e => e.name == suite.calls[i].entry)[0]
    match call.outcome {
      Returned(value) =>
        validate_as(value, entry.output, definitions, output=true)
      ModelError(code) =>
        validate_as(
          Value::ModelError(code),
          entry.output,
          definitions,
          output=true,
        )
      Failed(_) | Cancelled => ()
    }
  }
}
