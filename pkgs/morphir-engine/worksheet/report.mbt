///|
priv enum WorksheetStage {
  Read
  Evaluate
  Project
  Transport
} derive(Eq)

///|
priv struct WorksheetDiagnostic {
  stage : WorksheetStage
  range : Utf16Range?
} derive(Eq)

///|
pub struct Observation {
  priv form : WorksheetForm
  priv preview : String
  priv outcome : @execution.TerminalOutcome
} derive(Eq)

///|
pub struct WorksheetReport {
  priv source : CapturedWorksheetSource
  priv observations : Array[Observation]
  priv completion : @execution.TerminalOutcome
  priv diagnostic : WorksheetDiagnostic?
} derive(Eq)

///|
pub extend WorksheetReport with Eq::{equal, not_equal}

///|
pub extend Observation with Eq::{equal, not_equal}

///|
pub fn WorksheetReport::source(
  self : WorksheetReport,
) -> CapturedWorksheetSource {
  self.source
}

///|
pub fn WorksheetReport::observations(
  self : WorksheetReport,
) -> Array[Observation] {
  self.observations.copy()
}

///|
pub fn Observation::range(self : Observation) -> Utf16Range {
  self.form.range
}

///|
pub fn Observation::expression(self : Observation) -> String {
  self.form.expression
}

///|
pub fn Observation::preview(self : Observation) -> String {
  self.preview
}

///|
pub fn Observation::outcome(self : Observation) -> @execution.TerminalOutcome {
  self.outcome
}

///|
fn WorksheetStage::text(self : WorksheetStage) -> String {
  match self {
    Read => "read"
    Evaluate => "evaluate"
    Project => "project"
    Transport => "transport"
  }
}

///|
fn Observation::to_json(self : Observation) -> Json {
  {
    "id": "form-" + self.form.id.index.to_string(),
    "range": self.form.range.to_json(),
    "expression": self.form.expression,
    "preview": self.preview,
    "outcome": self.outcome.to_json(),
  }
}

///|
fn WorksheetDiagnostic::to_json(self : WorksheetDiagnostic) -> Json {
  {
    "stage": self.stage.text(),
    "range": self.range.map(Utf16Range::to_json).unwrap_or(Json::null()),
  }
}

///|
pub fn WorksheetReport::to_json(self : WorksheetReport) -> Json {
  {
    "profile": PROFILE,
    "contractVersion": CONTRACT_VERSION,
    "source": self.source.to_json(),
    "observations": self.observations.map(Observation::to_json),
    "completion": self.completion.to_json(),
    "diagnostic": self.diagnostic
    .map(WorksheetDiagnostic::to_json)
    .unwrap_or(Json::null()),
  }
}

///|
fn bounded_text(source : String, limit : Int32) -> String {
  if source.length() <= limit {
    return source
  }
  let end = if boundary(source, limit) { limit } else { limit - 1 }
  source[0:end].to_owned()
}

///|
fn failed(
  code : String,
  message : String,
  stage : @execution.OutcomeStage,
) -> @execution.TerminalOutcome {
  @execution.Failed({ stage, code, message: bounded_text(message, 512), })
}

///|
fn failure_report(
  source : CapturedWorksheetSource,
  code : String,
  message : String,
  stage : WorksheetStage,
  range : Utf16Range?,
  observations~ : Array[Observation] = [],
) -> WorksheetReport {
  {
    source,
    observations: observations.copy(),
    completion: failed(code, message, @execution.Evaluate),
    diagnostic: Some({ stage, range, }),
  }
}

///|
fn read_range(
  source : CapturedWorksheetSource,
  error : Error,
) -> Utf16Range? raise {
  match error {
    @scheme.Syntax(_, offset) => {
      let offsets = scalar_prefix(source)
      if offset < 0 || offset >= offsets.length() {
        raise @execution.Invalid("worksheet.invalid_range")
      }
      Some(Utf16Range::new(source, offsets[offset], offsets[offset]))
    }
    _ => None
  }
}

///|
pub fn WorksheetRequest::evaluate(
  self : WorksheetRequest,
  interrupted~ : () -> WorkerTermination? = fn() { None },
  prepare~ : (@scheme.Runtime) -> Unit raise = fn(_) {  },
) -> WorksheetReport raise {
  // Interruption is a host decision; the shared evaluator only polls it.
  // Keep the established transport contract, which has no streamed prefix.
  let mut termination : WorkerTermination? = None
  fn poll() -> WorkerTermination? {
    if termination is None {
      termination = interrupted()
    }
    termination
  }
  if poll() is Some(reason) {
    return self.terminated(reason)
  }
  let source = self.source
  let empty = WorksheetReport::{
    source,
    observations: [],
    completion: @execution.Returned(@execution.Unit),
    diagnostic: None,
  }
  // Account row bytes incrementally. Reserve enough for the largest bounded
  // failure message and located completion before executing any form.
  let mut encoded = @utf8.encode(empty.to_json().stringify()).length() + 4096
  if encoded > 2097152 {
    raise @execution.Invalid("worksheet.input_limit")
  }
  let forms = inventory(source) catch {
    @execution.Invalid(code) => raise @execution.Invalid(code)
    error =>
      return failure_report(
        source,
        "worksheet.read_failed",
        @scheme.error_message(error),
        Read,
        read_range(source, error),
      )
  }
  let rows : Array[Observation] = []
  let mut diagnostic : WorksheetDiagnostic? = None
  let mut budget = @execution.ValueBudget::new()
  let runtime = @scheme.Runtime::new()
  runtime.set_cancelled(fn() { poll() is Some(_) })
  runtime.with_budget(runtime => {
    prepare(runtime) catch {
      error => {
        if termination is Some(reason) {
          return self.terminated(reason)
        }
        return failure_report(
          source,
          "worksheet.context_failed",
          @scheme.error_message(error),
          Project,
          None,
        )
      }
    }
    for form in forms {
      if poll() is Some(reason) {
        return self.terminated(reason)
      }
      let value = runtime.eval_datum(form.datum) catch {
        error => {
          if termination is Some(reason) {
            return self.terminated(reason)
          }
          let code = if error is @scheme.Limit(_) {
            "worksheet.runtime_limit"
          } else {
            "worksheet.evaluation_failed"
          }
          let outcome = failed(
            code,
            @scheme.error_message(error),
            @execution.Evaluate,
          )
          let row = Observation::{ form, preview: "", outcome, }
          let row_bytes = @utf8.encode(row.to_json().stringify()).length() + 1
          if encoded + row_bytes > 2097152 {
            return failure_report(
              source,
              "worksheet.output_limit",
              "Worksheet output exceeds its limit.",
              Project,
              Some(form.range),
              observations=rows,
            )
          }
          rows.push(row)
          return {
            source,
            observations: rows.copy(),
            completion: outcome,
            diagnostic: Some({ stage: Evaluate, range: Some(form.range), }),
          }
        }
      }
      if poll() is Some(reason) {
        return self.terminated(reason)
      }
      let preview = @scheme.value_preview(value, 4000) catch {
        _ => "#<preview unavailable>"
      }
      let outcome = try {
        // Bound expansion while constructing the portable value, before the
        // existing semantic validator charges the aggregate cross-row budget.
        let projected = project_value(value, 0, ProjectionBudget::new())
        budget = budget.accept(projected)
        @execution.Returned(projected)
      } catch {
        @execution.Invalid("execution.value_limit")
        | @execution.Invalid("execution.utf16_units") =>
          return failure_report(
            source,
            "worksheet.output_limit",
            "Worksheet output exceeds its limit.",
            Project,
            Some(form.range),
            observations=rows,
          )
        _ => {
          if diagnostic is None {
            diagnostic = Some({ stage: Project, range: Some(form.range), })
          }
          failed(
            "worksheet.value_unsupported",
            "This Scheme value has no portable worksheet representation.",
            @execution.Evaluate,
          )
        }
      }
      let row = Observation::{ form, preview, outcome, }
      let row_bytes = @utf8.encode(row.to_json().stringify()).length() + 1
      if encoded + row_bytes > 2097152 {
        return failure_report(
          source,
          "worksheet.output_limit",
          "Worksheet output exceeds its limit.",
          Project,
          Some(form.range),
          observations=rows,
        )
      }
      rows.push(row)
      encoded += row_bytes
    }
    if poll() is Some(reason) {
      return self.terminated(reason)
    }
    {
      source,
      observations: rows.copy(),
      completion: @execution.Returned(@execution.Unit),
      diagnostic,
    }
  }) catch {
    error =>
      match termination {
        Some(reason) => self.terminated(reason)
        None => raise error
      }
  }
}

///|
pub fn WorksheetReport::completion(
  self : WorksheetReport,
) -> @execution.TerminalOutcome {
  self.completion
}

///|
/// All forms completed and every observation has a portable returned value.
pub fn WorksheetReport::successful(self : WorksheetReport) -> Bool {
  self.completion is @execution.Returned(_) &&
  self.observations.all(row => row.outcome is @execution.Returned(_))
}
