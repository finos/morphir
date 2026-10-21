///|
fn report_failure() -> Unit raise {
  raise @execution.Invalid("worksheet.invalid_report")
}

///|
fn read_report_range(
  value : Json,
  source : CapturedWorksheetSource,
) -> Utf16Range raise {
  let code = "worksheet.invalid_range"
  let fields = object(value, ["start", "end"], code)
  Utf16Range::new(
    source,
    integer(fields["start"], code),
    integer(fields["end"], code),
  )
}

///|
fn read_diagnostic(
  value : Json,
  source : CapturedWorksheetSource,
) -> WorksheetDiagnostic? raise {
  if value is Null {
    return None
  }
  let code = "worksheet.invalid_report"
  let fields = object(value, ["stage", "range"], code)
  let stage = match string(fields["stage"], code) {
    "read" => Read
    "evaluate" => Evaluate
    "project" => Project
    "transport" => Transport
    _ => raise @execution.Invalid(code)
  }
  let range = if fields["range"] is Null {
    None
  } else {
    Some(read_report_range(fields["range"], source))
  }
  Some({ stage, range, })
}

///|
fn located(
  diagnostic : WorksheetDiagnostic?,
  stage : WorksheetStage,
  range : Utf16Range?,
) -> Bool {
  match diagnostic {
    Some(diagnostic) =>
      diagnostic.stage.text() == stage.text() && diagnostic.range == range
    None => false
  }
}

///|
fn portable_value(value : @execution.Value) -> Bool {
  match value {
    Integer(_) | Boolean(_) | Unit | Text(_) | Character(_) => true
    Float64(bits) => {
      let number = bits.reinterpret_as_double()
      !number.is_nan() && !number.is_inf()
    }
    Sequence(items) | Product(items) => items.all(portable_value)
    Record(fields) => fields.all(field => portable_value(field.1))
    _ => false
  }
}

///|
/// Validate supplied evidence against its captured source without evaluating it.
/// Acceptance proves structure and source reconciliation, not execution.
pub fn WorksheetReport::decode(
  request : WorksheetRequest,
  raw : String,
) -> WorksheetReport raise {
  let code = "worksheet.invalid_report"
  let fields = object(
    decode_json(raw, ReportDocument),
    [
      "profile", "contractVersion", "source", "observations", "completion", "diagnostic",
    ],
    code,
  )
  if fields["profile"] != Json::string(PROFILE) ||
    fields["contractVersion"] != Json::string(CONTRACT_VERSION) {
    report_failure()
  }
  let source = CapturedWorksheetSource::from_json(fields["source"]) catch {
    _ => raise @execution.Invalid(code)
  }
  // Compare the complete capture before checking ranges against either text.
  if source != request.source {
    raise @execution.Invalid("worksheet.source_mismatch")
  }
  let supplied = @wire.array(fields["observations"]) catch {
    _ => raise @execution.Invalid(code)
  }
  if supplied.length() > 1000 {
    report_failure()
  }
  let completion = @execution.TerminalOutcome::from_json(fields["completion"]) catch {
    _ => raise @execution.Invalid(code)
  }
  let diagnostic = read_diagnostic(fields["diagnostic"], source)
  // Owned-worker termination has no streamed prefix. It remains meaningful even
  // if the captured Scheme text would fail to parse after the worker started.
  let transport_terminal = match completion {
    Cancelled => true
    Failed(failure) =>
      ["worksheet.timeout", "worksheet.worker_failed"].contains(failure.code) &&
      failure.stage is @execution.Evaluate
    _ => false
  }
  if transport_terminal {
    if !supplied.is_empty() || !located(diagnostic, Transport, None) {
      report_failure()
    }
    return { source, observations: [], completion, diagnostic, }
  }
  let forms = inventory(source) catch {
    @execution.Invalid(reason) => raise @execution.Invalid(reason)
    error => {
      let expected = failed(
        "worksheet.read_failed",
        @scheme.error_message(error),
        @execution.Evaluate,
      )
      if !supplied.is_empty() ||
        completion != expected ||
        !located(diagnostic, Read, read_range(source, error)) {
        report_failure()
      }
      return { source, observations: [], completion, diagnostic, }
    }
  }
  if supplied.length() > forms.length() {
    raise @execution.Invalid("worksheet.invalid_range")
  }
  let rows : Array[Observation] = []
  let mut budget = @execution.ValueBudget::new()
  let mut projection_range : Utf16Range? = None
  let mut fatal : @execution.TerminalOutcome? = None
  for index, raw_row in supplied {
    let row_fields = object(
      raw_row,
      ["id", "range", "expression", "preview", "outcome"],
      code,
    )
    let form = forms[index]
    if row_fields["id"] != Json::string("form-" + index.to_string()) {
      raise @execution.Invalid("worksheet.invalid_identity")
    }
    let range = read_report_range(row_fields["range"], source)
    if range != form.range ||
      row_fields["expression"] != Json::string(form.expression) {
      raise @execution.Invalid("worksheet.invalid_range")
    }
    let preview = string(row_fields["preview"], code)
    if preview.length() > 4000 {
      report_failure()
    }
    let outcome = @execution.TerminalOutcome::from_json(row_fields["outcome"]) catch {
      _ => raise @execution.Invalid(code)
    }
    // A supplied report must already contain canonical terminal evidence.
    // The reusable value decoder also accepts spellings it normalizes.
    if outcome.to_json() != row_fields["outcome"] {
      report_failure()
    }
    match outcome {
      Returned(value) => {
        if !portable_value(value) {
          report_failure()
        }
        budget = budget.accept(value) catch {
          _ => raise @execution.Invalid(code)
        }
      }
      Failed(failure) => {
        if !(failure.stage is @execution.Evaluate) {
          report_failure()
        }
        if failure.code == "worksheet.value_unsupported" {
          if failure.message !=
            "This Scheme value has no portable worksheet representation." {
            report_failure()
          }
          if projection_range is None {
            projection_range = Some(range)
          }
        } else if ["worksheet.evaluation_failed", "worksheet.runtime_limit"].contains(
            failure.code,
          ) {
          if index != supplied.length() - 1 || preview != "" {
            report_failure()
          }
          fatal = Some(outcome)
        } else {
          report_failure()
        }
      }
      ModelError(_) => ()
      Cancelled => report_failure()
    }
    rows.push({ form, preview, outcome, })
  }
  match completion {
    Returned(Unit) => {
      if rows.length() != forms.length() {
        raise @execution.Invalid("worksheet.invalid_range")
      }
      if fatal is Some(_) {
        report_failure()
      }
      match projection_range {
        Some(range) =>
          if !located(diagnostic, Project, Some(range)) {
            report_failure()
          }
        None => if diagnostic is Some(_) { report_failure() }
      }
    }
    Failed(failure) if failure.code == "worksheet.context_failed" &&
      failure.stage is @execution.Evaluate =>
      if !rows.is_empty() || !located(diagnostic, Project, None) {
        report_failure()
      }
    Failed(failure) if failure.code == "worksheet.output_limit" &&
      failure.stage is @execution.Evaluate =>
      if fatal is Some(_) ||
        rows.length() >= forms.length() ||
        !located(diagnostic, Project, Some(forms[rows.length()].range)) {
        report_failure()
      }
    Failed(_) =>
      if fatal != Some(completion) ||
        rows.is_empty() ||
        !located(diagnostic, Evaluate, Some(rows[rows.length() - 1].form.range)) {
        report_failure()
      }
    _ => report_failure()
  }
  { source, observations: rows, completion, diagnostic, }
}
