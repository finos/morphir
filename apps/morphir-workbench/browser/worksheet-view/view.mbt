///|
pub(all) enum Action {
  Reveal(@worksheet.CapturedWorksheetSource, @worksheet.Utf16Range)
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
/// Captured CRLF offsets become display coordinates before crossing CodeMirror.
fn point(source : String, offset : Int32) -> (Int32, Int32) {
  let mut line = 1
  let mut column = 1
  let mut index = 0
  while index < offset {
    let unit = source.code_unit_at(index).to_int()
    if unit == 13 {
      line += 1
      column = 1
      if index + 1 < offset && source.code_unit_at(index + 1).to_int() == 10 {
        index += 1
      }
    } else if unit == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
    index += 1
  }
  (line, column)
}

///|
pub fn reveal(
  source : @worksheet.CapturedWorksheetSource,
  range : @worksheet.Utf16Range,
  nonce : Int32,
) -> String {
  let json = range.to_json()
  let start = match field(json, "start") {
    Number(n, ..) => n.to_int()
    _ => 0
  }
  let end = match field(json, "end") {
    Number(n, ..) => n.to_int()
    _ => 0
  }
  let (line, column) = point(source.text(), start)
  let (end_line, end_column) = point(source.text(), end)
  line.to_string() +
  ":" +
  column.to_string() +
  ":" +
  nonce.to_string() +
  ":" +
  end_line.to_string() +
  ":" +
  end_column.to_string()
}

///|
fn failure(report : @worksheet.WorksheetReport) -> Json {
  let json = report.to_json()
  let completion = field(json, "completion")
  if text(completion, "status") == "failed" {
    return field(completion, "failure")
  }
  for row in report.observations() {
    if row.outcome() is @execution.Failed(failure) {
      return {
        "code": failure.code,
        "message": failure.message,
        "stage": "project",
      }
    }
  }
  Json::null()
}

///|
pub fn diagnostics(
  report : @worksheet.WorksheetReport,
) -> Array[@bottom_panel.Diagnostic] {
  let problem = failure(report)
  if problem == Json::null() {
    return []
  }
  let diagnostic = field(report.to_json(), "diagnostic")
  let range = field(diagnostic, "range")
  let (line, column) = match field(range, "start") {
    Number(n, ..) => point(report.source().text(), n.to_int())
    _ => (0, 0)
  }
  [
    {
      severity: @bottom_panel.Error,
      code: text(problem, "code"),
      message: text(problem, "message"),
      location: if line > 0 {
        "worksheet.scm:" + line.to_string() + ":" + column.to_string()
      } else {
        ""
      },
      coordinates: "",
      related: [],
      fix: "",
      stage: text(diagnostic, "stage"),
      place: if line > 0 {
        Some({ path: "worksheet.scm", line, column, })
      } else {
        None
      },
    },
  ]
}

///|
pub fn marks(report : @worksheet.WorksheetReport) -> String {
  let problem = failure(report)
  let range = field(field(report.to_json(), "diagnostic"), "range")
  match (field(range, "start"), field(range, "end")) {
    (Number(start, ..), Number(end, ..)) if problem != Json::null() => {
      let (line, column) = point(report.source().text(), start.to_int())
      let (end_line, end_column) = point(report.source().text(), end.to_int())
      Json::array([
        {
          "line": line,
          "column": column,
          "endLine": end_line,
          "endColumn": end_column,
          "message": text(problem, "message"),
        },
      ]).stringify()
    }
    _ => ""
  }
}

///|
pub fn view(
  report : @worksheet.WorksheetReport,
  current : Bool,
  on_action : @cmd.Emit[Action],
) -> @html.Html {
  let rows = report.observations()
  let body : Array[@html.Html] = []
  if !current {
    body.push(
      @html.p(
        class="worksheet-stale muted small",
        "Results are from an earlier revision. Run again to navigate in the current source.",
      ),
    )
  }
  for row in rows {
    let outcome = row.outcome().to_json()
    let status = text(outcome, "status")
    let detail = if status == "returned" {
      text(field(outcome, "value"), "type")
    } else {
      status
    }
    let message = if status == "failed" {
      text(field(outcome, "failure"), "message")
    } else {
      row.preview()
    }
    body.push(
      @html.div(class="worksheet-result", [
        @html.button(
          class="worksheet-expression",
          disabled=!current,
          attrs=@html.Attrs::build()
            .aria_label("Show expression in source")
            .title(
              if current {
                "Show expression in source"
              } else {
                "Source has changed"
              },
            ),
          on_click=on_action(Reveal(report.source(), row.range())),
          @html.code(row.expression()),
        ),
        @html.div(class="worksheet-observation", [
          @html.pre(class="value", message),
          @html.details(class="worksheet-typed", [
            @html.summary("Typed details · " + detail),
            @html.pre(outcome.stringify(indent=2)),
          ]),
        ]),
      ]),
    )
  }
  let completion = field(report.to_json(), "completion")
  if text(completion, "status") == "cancelled" {
    body.push(
      @html.p(
        class="worksheet-completion",
        "Cancelled. The local worker stopped; no partial results were retained.",
      ),
    )
  } else if text(completion, "status") == "failed" {
    body.push(
      @html.p(
        class="worksheet-completion",
        text(field(completion, "failure"), "message"),
      ),
    )
  } else if rows.is_empty() {
    body.push(@html.p(class="muted", "No expressions to run."))
  }
  @html.div(class="worksheet-results", body)
}
