///|
priv enum WorksheetOperation {
  EvaluateWorksheet
  ValidateWorksheet
}

///|
fn worksheet_observation(id : Json, operation : Json, input : Json) -> Json {
  try {
    if @utf8.encode(input.stringify()).length() > 8388608 {
      raise @execution.Invalid("workbench.input_limit")
    }
    let selected = match operation {
      String("worksheet-evaluate") => EvaluateWorksheet
      String("worksheet-validate") => ValidateWorksheet
      _ => raise @execution.Invalid("workbench.invalid_request")
    }
    let names = match selected {
      EvaluateWorksheet => ["request"]
      ValidateWorksheet => ["request", "report"]
    }
    guard input is Object(fields) &&
      fields.length() == names.length() &&
      names.all(name => fields.contains(name)) else {
      raise @execution.Invalid("workbench.invalid_request")
    }
    let raw_request = @wire.string(fields["request"]) catch {
      _ => raise @execution.Invalid("workbench.invalid_request")
    }
    let request = @worksheet.WorksheetRequest::decode(raw_request)
    let report = match selected {
      EvaluateWorksheet => request.evaluate()
      ValidateWorksheet => {
        let raw_report = @wire.string(fields["report"]) catch {
          _ => raise @execution.Invalid("workbench.invalid_request")
        }
        @worksheet.WorksheetReport::decode(request, raw_report)
      }
    }
    { "id": id, "status": "ok", "value": report.to_json() }
  } catch {
    @execution.Invalid(code) => invalid(id, code)
    _ => invalid(id, "workbench.invalid_request")
  }
}
