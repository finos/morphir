///|
/// Owned-worker termination carries no unobserved partial results.
pub(all) enum WorkerTermination {
  Cancelled
  TimedOut
  WorkerFailed
}

///|
pub fn WorksheetRequest::terminated(
  self : WorksheetRequest,
  reason : WorkerTermination,
) -> WorksheetReport {
  let completion = match reason {
    Cancelled => @execution.Cancelled
    TimedOut =>
      failed(
        "worksheet.timeout",
        "Worksheet execution timed out.",
        @execution.Evaluate,
      )
    WorkerFailed =>
      failed(
        "worksheet.worker_failed",
        "The worksheet worker failed.",
        @execution.Evaluate,
      )
  }
  {
    source: self.source,
    observations: [],
    completion,
    diagnostic: Some({ stage: Transport, range: None, }),
  }
}

///|
/// Pure browser boundary. The returned string is a canonical request or report;
/// errors never turn an invalid capture into execution authority.
pub fn browser_command(source : String) -> Json {
  try {
    if source.length() > 8388608 || @utf8.encode(source).length() > 8388608 {
      raise @execution.Invalid("worksheet.input_limit")
    }
    let command = @wire.parse_bounded(
      source,
      max_depth=8,
      max_nodes=32,
      max_string_units=8388608,
    )
    let action = @wire.string(@wire.field(command, "action"))
    let names = match action {
      "capture" => ["action", "request"]
      "validate" => ["action", "request", "report"]
      "terminate" => ["action", "request", "reason"]
      _ => raise @execution.Invalid("worksheet.invalid_request")
    }
    let fields = object(command, names, "worksheet.invalid_request")
    let request = WorksheetRequest::decode(@wire.string(fields["request"]))
    let value = match action {
      "capture" => request.to_json()
      "validate" =>
        WorksheetReport::decode(request, @wire.string(fields["report"])).to_json()
      "terminate" => {
        let reason = match @wire.string(fields["reason"]) {
          "cancelled" => Cancelled
          "timeout" => TimedOut
          "worker-failed" => WorkerFailed
          _ => raise @execution.Invalid("worksheet.invalid_request")
        }
        request.terminated(reason).to_json()
      }
      _ => raise @execution.Invalid("worksheet.invalid_request")
    }
    { "ok": true, "value": value.stringify() }
  } catch {
    @execution.Invalid(code) => { "ok": false, "code": code }
    _ => { "ok": false, "code": "worksheet.invalid_request" }
  }
}
