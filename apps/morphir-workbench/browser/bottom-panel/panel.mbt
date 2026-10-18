// An IDE-style tool panel below both experiences. It records what the
// application actually did: operation activity, diagnostics returned by the
// local worker or connected host, and run/evaluation outcomes. It never reads
// the browser console or invents host capabilities.

///|
pub(all) enum Tab {
  Logs
  Diagnostics
  Output
} derive(Eq)

///|
pub extend Tab with Eq::{equal, not_equal}

///|
pub(all) enum Size {
  Collapsed
  Normal
  Expanded
} derive(Eq)

///|
pub extend Size with Eq::{equal, not_equal}

///|
pub(all) enum Severity {
  Info
  Warning
  Error
} derive(Eq)

///|
pub extend Severity with Eq::{equal, not_equal}

///|
/// What a failed job ran and how it failed: what its details show and its plain-text report holds.
pub(all) struct Failure {
  job : Int32
  operation : String
  /// The reply's code, such as an engine problem code or `workbench.internal_error`; empty when it gave none.
  code : String
  stage : String
  message : String
  /// The job's context as `(label, value)` pairs in display order, such as `("Language", "elm")`.
  context : Array[(String, String)]
  /// The reply as JSON text after `redacted`, bounded; empty when there is none.
  raw : String
} derive(Eq)

///|
pub extend Failure with Eq::{equal, not_equal}

// Raw replies.

///|
/// The longest string a raw reply keeps under a member that is not in `kept_text_members`. Longer strings can
/// be source, so they become `<omitted: N characters>`.
pub let raw_text_bound : Int32 = 32

///|
/// Members whose text a raw reply keeps at any length: structure, diagnostics and the job's settings. Messages
/// (`message`, `detail`, `generationMessage`) are kept, so they can quote the source a failure points at.
let kept_text_members : Array[String] = [
  "success", "operation", "code", "stage", "message", "detail", "generationMessage",
  "severity", "kind", "path", "target", "provider", "profile", "coordinateProfile",
  "languageId", "language", "encoding", "codec", "id", "jobId", "version", "formatVersion",
  "schemaVersion",
]

///|
/// Members that hold source or a model, omitted whole whatever their shape, even when each string is short.
let omitted_members : Array[String] = [
  "content", "generated", "irSource", "sourceUnitIon", "sourceBase64", "expression",
  "text", "value", "ir", "nodes", "evaluations", "typedEvaluations",
]

///|
/// What a raw reply leaves out, for its label and the plain-text report.
pub let raw_note : String = "source, models and values omitted; other text over \{raw_text_bound} characters replaced by its size, except messages, codes and paths"

///|
/// `true` when `value` is a source location: an object of numbers only, with a line and a column.
fn is_location(value : Json) -> Bool {
  guard value is Object(fields) && fields.length() > 0 else { return false }
  let names = fields.keys().map(name => name.to_lower()).collect()
  fields.values().all(inner => inner is Number(_)) &&
  names.any(name => name.contains("line")) &&
  names.any(name => name.contains("column"))
}

///|
fn omitted(value : Json) -> Json {
  let size = match value {
    String(text) => text.length()
    _ => value.stringify().length()
  }
  Json::string("<omitted: " + size.to_string() + " characters>")
}

///|
/// `value` for a raw reply a person can paste. Only `kept_text_members` keep long text, a `source` stays only as a
/// location, `omitted_members` go whole, and every other string longer than `raw_text_bound` becomes its size, at
/// any depth.
pub fn redacted(value : Json) -> Json {
  fn walk(name : String, value : Json) -> Json {
    if value == Json::null() {
      return value
    }
    if omitted_members.contains(name) ||
      (name == "source" && !is_location(value)) {
      return omitted(value)
    }
    match value {
      Object(fields) => {
        let kept : Map[String, Json] = Map([])
        for key, inner in fields {
          kept[key] = walk(key, inner)
        }
        Json::object(kept)
      }
      Array(values) => Json::array(values.map(inner => walk(name, inner)))
      String(text) =>
        if text.length() <= raw_text_bound || kept_text_members.contains(name) {
          value
        } else {
          omitted(value)
        }
      other => other
    }
  }

  walk("", value)
}

///|
pub(all) struct Log {
  id : Int32
  time : String
  operation : String
  severity : Severity
  message : String
  failure : Failure?
} derive(Eq)

///|
pub extend Log with Eq::{equal, not_equal}

///|
/// `location` is the editor-style position; `coordinates` keeps the original
/// coordinate profile and values exactly as the reporter supplied them.
pub(all) struct Related {
  owner : String
  original : String
  allocated : String
  location : String
  coordinates : String
} derive(Eq)

///|
pub extend Related with Eq::{equal, not_equal}

///|
/// Where a problem sits in a project file: a one-based line and a display column (see `display_column`).
pub(all) struct Place {
  path : String
  line : Int32
  column : Int32
} derive(Eq, Debug)

///|
pub extend Place with Eq::{equal, not_equal}

///|
pub extend Place with @debug.Debug::{to_repr}

///|
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  message : String
  location : String
  coordinates : String
  related : Array[Related]
  fix : String
  stage : String
  place : Place?
} derive(Eq)

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
/// Diagnostics from one operation run, scoped to the document revision it read.
pub(all) struct Report {
  id : Int32
  time : String
  operation : String
  job : Int32
  scope : String
  revision : Int32
  diagnostics : Array[Diagnostic]
  failure : Failure?
} derive(Eq)

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub(all) struct Outcome {
  id : Int32
  time : String
  operation : String
  severity : Severity
  title : String
  lines : Array[String]
  terminal : @outcomes.Summary?
  failure : Failure?
} derive(Eq)

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub(all) struct State {
  tab : Tab
  size : Size
  logs : Array[Log]
  reports : Array[Report]
  outcomes : Array[Outcome]
  next : Int32
  /// The keys of the details the person opened, such as `log-12`, `diagnostic-4-0` or `raw-log-12`.
  open : Array[String]
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
pub(all) enum Action {
  Activate(Tab)
  Key(String)
  Open
  Collapse
  Expand
  Restore
  Clear
  Reveal(Place)
  /// Opens or closes one set of details.
  Toggle(String)
  /// Asks the workbench to copy this plain-text report.
  CopyDetails(String)
}

///|
pub let max_logs : Int32 = 200

///|
pub let max_reports : Int32 = 20

///|
pub let max_diagnostics : Int32 = 50

///|
pub let max_outcomes : Int32 = 50

///|
pub let max_text : Int32 = 4000

///|
/// At most this many sets of details stay open; opening one more closes the oldest.
pub let max_open : Int32 = 50

///|
/// The longest raw reply kept with a failure, in characters.
pub let max_raw : Int32 = 8000

///|
let tabs : Array[Tab] = [Logs, Diagnostics, Output]

///|
let navigation_keys : Array[String] = ["ArrowLeft", "ArrowRight", "Home", "End"]

///|
pub fn State::new() -> State {
  {
    tab: Logs,
    size: Collapsed,
    logs: [],
    reports: [],
    outcomes: [],
    next: 1,
    open: [],
  }
}

///|
pub fn tab_id(tab : Tab) -> String {
  match tab {
    Logs => "tool-tab-logs"
    Diagnostics => "tool-tab-diagnostics"
    Output => "tool-tab-output"
  }
}

///|
fn tab_label(tab : Tab) -> String {
  match tab {
    Logs => "Logs"
    Diagnostics => "Diagnostics"
    Output => "Output"
  }
}

///|
fn tab_index(tab : Tab) -> Int32 {
  match tab {
    Logs => 0
    Diagnostics => 1
    Output => 2
  }
}

///|
/// Returns the new state and, after keyboard navigation, the tab to focus.
pub fn State::update(self : State, action : Action) -> (State, String?) {
  match action {
    Activate(tab) =>
      if self.size == Collapsed {
        ({ ..self, tab, size: Normal, }, None)
      } else if tab == self.tab {
        ({ ..self, size: Collapsed, }, None)
      } else {
        ({ ..self, tab, }, None)
      }
    Key(key) => {
      let index = tab_index(self.tab)
      let next = match key {
        "ArrowRight" => Some(tabs[(index + 1) % tabs.length()])
        "ArrowLeft" => Some(tabs[(index + tabs.length() - 1) % tabs.length()])
        "Home" => Some(tabs[0])
        "End" => Some(tabs[tabs.length() - 1])
        _ => None
      }
      match next {
        Some(tab) => ({ ..self, tab, }, Some(tab_id(tab)))
        None => (self, None)
      }
    }
    Open => ({ ..self, size: Normal, }, None)
    Collapse => ({ ..self, size: Collapsed, }, None)
    Expand => ({ ..self, size: Expanded, }, None)
    Restore => ({ ..self, size: Normal, }, None)
    Reveal(_) | CopyDetails(_) => (self, None)
    Toggle(key) =>
      (
        {
          ..self,
          open: if self.open.contains(key) {
            self.open.filter(k => k != key)
          } else {
            keep_last(self.open, key, max_open)
          },
        },
        None,
      )
    Clear =>
      (
        match self.tab {
          Logs => { ..self, logs: [], }
          Diagnostics => { ..self, reports: [], }
          Output => { ..self, outcomes: [], }
        },
        None,
      )
  }
}

///|
fn bounded(text : String) -> String {
  if text.length() <= max_text {
    return text
  }
  let kept = StringBuilder()
  let mut count = 0
  for char in text {
    if count >= max_text {
      break
    }
    kept.write_char(char)
    count += 1
  }
  kept.to_string() + "… (truncated)"
}

///|
fn[T] keep_last(items : Array[T], item : T, limit : Int32) -> Array[T] {
  let start = if items.length() >= limit {
    items.length() - limit + 1
  } else {
    0
  }
  let kept = items[start:].to_owned()
  kept.push(item)
  kept
}

///|
pub fn State::log(
  self : State,
  time : String,
  operation : String,
  severity : Severity,
  message : String,
  failure~ : Failure? = None,
) -> State {
  let entry = {
    id: self.next,
    time,
    operation,
    severity,
    message: bounded(message),
    failure: failure.map(bounded_failure),
  }
  { ..self, logs: keep_last(self.logs, entry, max_logs), next: self.next + 1, }
}

///|

///|
fn bounded_failure(failure : Failure) -> Failure {
  {
    ..failure,
    code: bounded(failure.code),
    stage: bounded(failure.stage),
    message: bounded(failure.message),
    context: failure.context.map(pair => (pair.0, bounded(pair.1))),
    raw: if failure.raw.length() <= max_raw {
      failure.raw
    } else {
      failure.raw.unsafe_substring(start=0, end=max_raw) + "\n… (truncated)"
    },
  }
}

///|
fn bounded_diagnostic(d : Diagnostic) -> Diagnostic {
  let count = if d.related.length() < 20 { d.related.length() } else { 20 }
  {
    ..d,
    code: bounded(d.code),
    location: bounded(d.location),
    coordinates: bounded(d.coordinates),
    fix: bounded(d.fix),
    stage: bounded(d.stage),
    place: d.place,
    message: bounded(
      d.message +
      (if d.related.length() > count {
        " · " +
        (d.related.length() - count).to_string() +
        " more related locations not retained"
      } else {
        ""
      }),
    ),
    related: d.related[:count]
    .to_owned()
    .map(r => {
      owner: bounded(r.owner),
      original: bounded(r.original),
      allocated: bounded(r.allocated),
      location: bounded(r.location),
      coordinates: bounded(r.coordinates),
    }),
  }
}

///|
pub fn State::report(
  self : State,
  time : String,
  operation : String,
  job : Int32,
  scope : String,
  revision : Int32,
  diagnostics : Array[Diagnostic],
  failure~ : Failure? = None,
) -> State {
  let kept = diagnostics[:if diagnostics.length() < max_diagnostics {
      diagnostics.length()
    } else {
      max_diagnostics
    }]
    .to_owned()
    .map(bounded_diagnostic)
  if diagnostics.length() > max_diagnostics {
    kept.push({
      severity: Info,
      code: "",
      message: (diagnostics.length() - max_diagnostics).to_string() +
      " more diagnostics were not retained.",
      location: "",
      coordinates: "",
      related: [],
      fix: "",
      stage: "",
      place: None,
    })
  }
  let entry = {
    id: self.next,
    time,
    operation,
    job,
    scope,
    revision,
    diagnostics: kept,
    failure: failure.map(bounded_failure),
  }
  {
    ..self,
    reports: keep_last(self.reports, entry, max_reports),
    next: self.next + 1,
  }
}

///|
pub fn State::outcome(
  self : State,
  time : String,
  operation : String,
  severity : Severity,
  title : String,
  lines : Array[String],
  terminal~ : @outcomes.Summary? = None,
  failure~ : Failure? = None,
) -> State {
  let entry = {
    terminal,
    failure: failure.map(bounded_failure),
    id: self.next,
    time,
    operation,
    severity,
    title: bounded(title),
    lines: lines[:if lines.length() < 100 { lines.length() } else { 100 }]
    .to_owned()
    .map(bounded),
  }
  {
    ..self,
    outcomes: keep_last(self.outcomes, entry, max_outcomes),
    next: self.next + 1,
  }
}

///|
/// A report is current when it is the newest for its scope and read the
/// scope's current revision. Older or superseded reports remain visible.
pub fn State::is_current(
  self : State,
  report : Report,
  revisions : Map[String, Int32],
) -> Bool {
  let newest = self.reports
    .iter()
    .filter(other => other.scope == report.scope)
    .fold(init=report.id, (id, other) => {
      if other.id > id {
        other.id
      } else {
        id
      }
    })
  newest == report.id &&
  revisions
  .get(report.scope)
  .map(revision => revision == report.revision)
  .unwrap_or(true)
}

///|
pub fn terminal_severity(summary : @outcomes.Summary) -> Severity {
  match summary.level() {
    Info => Info
    Warning => Warning
    Error => Error
  }
}

///|
pub fn terminal_diagnostics(
  projection : @outcomes.Projection,
) -> Array[Diagnostic] {
  fn problem(
    severity : Severity,
    code : String,
    message : String,
    location : String,
    stage : String,
  ) -> Diagnostic {
    {
      severity,
      code,
      message,
      location,
      stage,
      coordinates: "",
      related: [],
      fix: "",
      place: None,
    }
  }
  match projection {
    Absent => []
    Invalid(code) =>
      [
        problem(
          Error,
          "workbench.invalid_terminal_evidence",
          "Terminal evidence rejected: " + code,
          "",
          "validation",
        ),
      ]
    Valid(summary) => {
      let diagnostics = []
      // Keep separate cleanup evidence visible even if the report reaches its cap.
      if summary.cleanup is Some(cleanup) {
        diagnostics.push(
          problem(Error, cleanup.code, cleanup.message, "Cleanup", "cleanup"),
        )
      }
      for call in summary.calls {
        match call.kind {
          Returned => ()
          ModelError =>
            diagnostics.push(
              problem(
                Warning,
                call.code,
                call.message,
                "Call " + call.id,
                "model",
              ),
            )
          Failed =>
            diagnostics.push(
              problem(
                Error,
                call.code,
                call.message,
                "Call " + call.id,
                call.stage,
              ),
            )
          Cancelled =>
            diagnostics.push(
              problem(
                Warning,
                "execution.cancelled",
                call.message,
                "Call " + call.id,
                "cancel",
              ),
            )
        }
      }
      diagnostics
    }
  }
}

///|
/// Errors and warnings in current reports.
pub fn State::problem_count(
  self : State,
  revisions : Map[String, Int32],
) -> Int32 {
  self.reports
  .iter()
  .filter(report => self.is_current(report, revisions))
  .fold(init=0, (count, report) => {
    count + report.diagnostics.filter(d => d.severity != Info).length()
  })
}

// Host reply envelopes ---------------------------------------------------

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
fn number(value : Json, key : String) -> Int32? {
  match field(value, key) {
    Number(n, ..) => Some(n.to_int())
    _ => None
  }
}

///|
fn items(value : Json) -> Array[Json] {
  match value {
    Array(values) => values
    _ => []
  }
}

///|
fn severity(value : String) -> Severity {
  match value.to_lower() {
    "error" => Error
    "warning" | "warn" => Warning
    _ => Info
  }
}

///|
/// The column to show for a reported column. The Elm and Morphir source profiles report one-based columns, shown
/// as written; every other profile, such as the MoonBit parser's zero-based columns, is shown plus one.
pub fn display_column(profile : String, column : Int32) -> Int32 {
  match profile {
    "elm-source-position-v1" | "morphir-source-location-v1" => column
    _ => column + 1
  }
}

///|
/// A file path prefixes the location. A problem with a path and a range also carries its `place`.
fn frontend_diagnostic(value : Json) -> Diagnostic {
  let source = field(value, "source")
  let profile = text(value, "coordinateProfile")
  let file = match text(value, "path") {
    "" => ""
    path => path + " "
  }
  let (location, coordinates) = match
    (
      number(source, "startLine"),
      number(source, "startColumn"),
      number(source, "endLine"),
      number(source, "endColumn"),
    ) {
    (Some(line), Some(column), Some(end_line), Some(end_column)) =>
      (
        file +
        "line " +
        line.to_string() +
        ", column " +
        display_column(profile, column).to_string(),
        text(value, "coordinateProfile") +
        " " +
        line.to_string() +
        ":" +
        column.to_string() +
        "–" +
        end_line.to_string() +
        ":" +
        end_column.to_string(),
      )
    _ => (text(value, "path"), text(value, "coordinateProfile"))
  }
  let place = match
    (
      text(value, "path"),
      number(source, "startLine"),
      number(source, "startColumn"),
    ) {
    (path, Some(line), Some(column)) if path != "" =>
      Some({ path, line, column: display_column(profile, column), })
    _ => None
  }
  {
    severity: Error,
    code: text(value, "code"),
    message: text(value, "detail"),
    location,
    coordinates,
    related: [],
    fix: "",
    stage: match text(value, "stage") {
      "" => "frontend"
      stage => stage
    },
    place,
  }
}

///|
/// Connected v1 playground diagnostics use zero-based line/character ranges.
fn host_diagnostic(value : Json) -> Diagnostic {
  let place = field(value, "location")
  let start = field(field(place, "range"), "start")
  let end = field(field(place, "range"), "end")
  let uri = text(place, "uri")
  let name = uri
    .split("/")
    .collect()
    .last()
    .map(s => s.to_owned())
    .unwrap_or(uri)
  let (location, coordinates) = match
    (
      number(start, "line"),
      number(start, "character"),
      number(end, "line"),
      number(end, "character"),
    ) {
    (Some(line), Some(character), Some(end_line), Some(end_character)) =>
      (
        name + ":" + (line + 1).to_string() + ":" + (character + 1).to_string(),
        uri +
        " " +
        line.to_string() +
        ":" +
        character.to_string() +
        "–" +
        end_line.to_string() +
        ":" +
        end_character.to_string(),
      )
    _ => (name, uri)
  }
  {
    severity: severity(text(value, "severity")),
    code: text(value, "code"),
    message: text(value, "message"),
    location,
    coordinates,
    related: [],
    fix: "",
    stage: "",
    place: None,
  }
}

///|
/// Diagnostics carried by a workbench host reply. A failure without structured
/// diagnostics becomes one error with the host's message.

///|
fn naming_diagnostic(value : Json) -> Diagnostic {
  let related = items(field(value, "locations")).map(loc => {
    let position = frontend_diagnostic({
      "source": field(loc, "source"),
      "coordinateProfile": field(value, "coordinateProfile"),
    })
    Related::{
      owner: text(loc, "owner"),
      original: text(loc, "original"),
      allocated: text(loc, "allocated"),
      location: position.location,
      coordinates: position.coordinates,
    }
  })
  let first = related.get(0)
  {
    severity: Warning,
    code: text(value, "code"),
    message: text(value, "message"),
    location: first.map(r => r.location).unwrap_or(""),
    coordinates: first.map(r => r.coordinates).unwrap_or(""),
    related,
    fix: text(value, "fix"),
    stage: text(value, "stage"),
    place: None,
  }
}

///|
/// A problem without its own `path` takes the path of the file that lists it.
fn with_path(problem : Json, path : String) -> Json {
  match problem {
    Object(fields) if text(problem, "path") == "" && path != "" => {
      let copy = fields.copy()
      copy["path"] = Json::string(path)
      Json::object(copy)
    }
    _ => problem
  }
}

///|
pub fn reply_diagnostics(reply : Json) -> Array[Diagnostic] {
  let found : Array[Diagnostic] = []
  let failed = field(reply, "success") != Json::boolean(true)
  if field(reply, "frontendDiagnostics") is Array(files) {
    for file in files {
      for problem in items(field(file, "problems")) {
        found.push(frontend_diagnostic(with_path(problem, text(file, "path"))))
      }
    }
  } else if field(reply, "frontendDiagnostic") is Object(_) {
    found.push(frontend_diagnostic(field(reply, "frontendDiagnostic")))
  }
  for diagnostic in items(field(reply, "diagnostics")) {
    found.push(host_diagnostic(diagnostic))
  }
  if failed && found.is_empty() {
    found.push({
      severity: Error,
      code: text(reply, "code"),
      message: text(reply, "message"),
      location: "",
      coordinates: "",
      related: [],
      fix: "",
      stage: text(reply, "stage"),
      place: None,
    })
  }
  let generation = items(field(reply, "generationDiagnostics"))
  for problem in generation {
    found.push({
      severity: Error,
      code: text(problem, "code"),
      message: text(problem, "detail"),
      location: if text(problem, "nodePath") == "" {
        ""
      } else {
        "IR node " + text(problem, "nodePath")
      },
      coordinates: text(problem, "nodePath"),
      related: [],
      fix: "",
      stage: "generation",
      place: None,
    })
  }
  if generation.is_empty() && text(reply, "generationMessage") != "" {
    found.push({
      severity: Error,
      code: "",
      message: text(reply, "generationMessage"),
      location: "",
      coordinates: "",
      related: [],
      fix: "",
      stage: "generation",
      place: None,
    })
  }
  for warning in items(field(reply, "sourceWarnings")) {
    if warning is Object(_) {
      found.push(naming_diagnostic(warning))
    }
  }
  for warning in items(field(reply, "generationWarnings")) {
    if warning is Object(_) {
      found.push(naming_diagnostic(warning))
    }
    if warning is String(message) {
      found.push({
        severity: Warning,
        code: "",
        message,
        location: "",
        coordinates: "",
        related: [],
        fix: "",
        stage: "",
        place: None,
      })
    }
  }
  if text(reply, "inspectionMessage") != "" {
    found.push({
      severity: Warning,
      code: "",
      message: "Local inspection is unavailable: " +
      text(reply, "inspectionMessage"),
      location: "",
      coordinates: "",
      related: [],
      fix: "",
      stage: "",
      place: None,
    })
  }
  found
}

// Plain-text reports ------------------------------------------------------

///|
fn stage_label(stage : String) -> String {
  match stage {
    "frontend" => "frontend"
    "typecheck" => "typecheck"
    "backend" | "generation" => "generation"
    "reply" | "compile" | "internal" => "internal (" + stage + ")"
    other => other
  }
}

///|
/// The first line of every plain-text report: the redaction keeps messages, and messages can quote the source.
pub let source_warning : String = "Messages can quote your source."

///|
fn context_lines(failure : Failure) -> Array[String] {
  failure.context
  .filter(pair => pair.1 != "")
  .map(pair => pair.0 + ": " + pair.1)
}

///|
/// The plain-text report of a failed job, to paste into an issue. Its first line warns that messages can quote
/// source; the raw reply is `redacted`.
pub fn failure_text(failure : Failure, time : String) -> String {
  let lines = [
    source_warning,
    "Morphir Workbench failure",
    "Operation: " + failure.operation + " (job " + failure.job.to_string() + ")",
  ]
  if failure.code != "" {
    lines.push("Code: " + failure.code)
  }
  if failure.stage != "" {
    lines.push("Stage: " + stage_label(failure.stage))
  }
  lines.push("Message: " + failure.message)
  lines.append(context_lines(failure))
  lines.push("Time: " + time)
  if failure.raw != "" {
    lines.push("")
    lines.push("Reply (" + raw_note + "):")
    lines.push(failure.raw)
  }
  lines.join("\n")
}

///|
/// The plain-text report of one diagnostic, with the job that reported it.
pub fn diagnostic_text(d : Diagnostic, report : Report) -> String {
  let lines = [
    source_warning,
    "Morphir Workbench diagnostic",
    "Severity: " + severity_label(d.severity),
  ]
  if d.code != "" {
    lines.push("Code: " + d.code)
  }
  if d.stage != "" {
    lines.push("Stage: " + stage_label(d.stage))
  }
  if d.location != "" {
    lines.push(
      "Location: " +
      d.location +
      (if d.coordinates == "" { "" } else { " (" + d.coordinates + ")" }),
    )
  }
  lines.push("Message: " + d.message)
  for r in d.related {
    lines.push("Related: " + r.owner + ", " + r.location)
  }
  if d.fix != "" {
    lines.push("Fix: " + d.fix)
  }
  lines.push(
    "Reported by: " +
    report.operation +
    " (job " +
    report.job.to_string() +
    (if report.scope == "session" {
      ""
    } else {
      ", " + report.scope + " revision " + report.revision.to_string()
    }) +
    ") at " +
    report.time,
  )
  if report.failure is Some(failure) {
    lines.append(context_lines(failure))
  }
  lines.join("\n")
}

// View ---------------------------------------------------------------------

///|
pub(all) struct Props {
  state : State
  status : String
  busy : Bool
  revisions : Map[String, Int32]
}

///|
fn icon(name : String) -> @html.Html {
  @html.span(
    class="action-icon icon-" + name,
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
}

///|
fn control(
  label : String,
  icon_name : String,
  emit : @cmd.Cmd,
  expanded : Bool?,
) -> @html.Html {
  let attrs = @html.Attrs::build()
    .aria_label(label)
    .aria_controls("tool-panel-body")
  @html.button(
    class="tool-control",
    title=label,
    attrs=match expanded {
      Some(value) => attrs.aria_expanded(value.to_string())
      None => attrs
    },
    on_click=emit,
    icon(icon_name),
  )
}

///|
fn severity_label(severity : Severity) -> String {
  match severity {
    Info => "Info"
    Warning => "Warning"
    Error => "Error"
  }
}

///|
fn severity_class(severity : Severity) -> String {
  match severity {
    Info => "severity-info"
    Warning => "severity-warning"
    Error => "severity-error"
  }
}

///|
fn plural(count : Int32, noun : String) -> String {
  count.to_string() + " " + noun + (if count == 1 { "" } else { "s" })
}

///|
fn empty(message : String) -> @html.Html {
  @html.p(class="tool-empty", message)
}

///|
/// The DOM id of the details a key opens, prefixed so it cannot clash with other ids on the page:
/// `tool-details-log-12` for `log-12`, `tool-raw-log-12` for `raw-log-12`.
pub fn details_id(key : String) -> String {
  if key.has_prefix("raw-") {
    "tool-raw-" + key.unsafe_substring(start=4, end=key.length())
  } else {
    "tool-details-" + key
  }
}

///|
/// A disclosure button for one set of details: it names what it opens and says whether it is open.
fn disclosure(
  state : State,
  key : String,
  label : String,
  name : String,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let open = state.open.contains(key)
  let attrs = @html.Attrs::build()
    .aria_expanded(open.to_string())
    .aria_label(name)
  @html.button(
    class=if open { "tool-disclosure open" } else { "tool-disclosure" },
    // The details exist only while open, so only then does the button control them.
    attrs=if open { attrs.aria_controls(details_id(key)) } else { attrs },
    on_click=emit(Toggle(key)),
    [
      @html.span(
        class="tool-chevron",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "",
      ),
      @html.span(label),
    ],
  )
}

///|
fn detail_row(label : String, value : @html.Html) -> Array[@html.Html] {
  [@html.dt(label), @html.dd(value)]
}

///|
/// Copy details and the raw reply, under a failure's or a diagnostic's details. `subject` names them, such as
/// `Compile job 3`.
fn detail_actions(
  state : State,
  key : String,
  subject : String,
  report : String,
  raw : String,
  emit : @cmd.Emit[Action],
) -> Array[@html.Html] {
  let raw_key = "raw-" + key
  let items : Array[@html.Html] = [
    @html.div(class="tool-detail-actions", [
      @html.button(
        class="secondary small",
        attrs=@html.Attrs::build().aria_label("Copy details of " + subject),
        on_click=emit(CopyDetails(report)),
        "Copy details",
      ),
      if raw == "" {
        @html.nothing
      } else {
        disclosure(state, raw_key, "Raw reply", "Raw reply of " + subject, emit)
      },
    ]),
  ]
  if raw != "" && state.open.contains(raw_key) {
    items.push(
      @html.pre(
        id=details_id(raw_key),
        class="tool-raw",
        attrs=@html.Attrs::build()
          .role("region")
          .aria_label("Raw reply of " + subject + ": " + raw_note)
          .tabindex(0),
        raw,
      ),
    )
  }
  items
}

///|
/// What a failure's controls name: its operation and job, such as `Compile job 3`.
fn failure_subject(failure : Failure) -> String {
  failure.operation + " job " + failure.job.to_string()
}

///|
/// The details of a failed job: its code, stage, message and context, Copy details and the raw reply.
fn failure_details(
  state : State,
  key : String,
  failure : Failure,
  time : String,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let rows : Array[@html.Html] = []
  if failure.code != "" {
    rows.append(detail_row("Code", @html.code(failure.code)))
  }
  if failure.stage != "" {
    rows.append(detail_row("Stage", @html.text(stage_label(failure.stage))))
  }
  rows.append(
    detail_row(
      "Message",
      @html.span(class="tool-detail-message", failure.message),
    ),
  )
  rows.append(
    detail_row(
      "Job",
      @html.text(failure.operation + " · job " + failure.job.to_string()),
    ),
  )
  for pair in failure.context {
    if pair.1 != "" {
      rows.append(detail_row(pair.0, @html.text(pair.1)))
    }
  }
  @html.div(
    id=details_id(key),
    class="tool-details",
    [
      @html.dl(class="tool-detail-grid", rows),
      ..detail_actions(
        state,
        key,
        failure_subject(failure),
        failure_text(failure, time),
        failure.raw,
        emit,
      ),
    ],
  )
}

///|
fn logs_view(state : State, emit : @cmd.Emit[Action]) -> Array[@html.Html] {
  if state.logs.is_empty() {
    return [
      empty(
        "No activity yet. Initialization, compile, run, worksheet, import, evaluation, download and cancellation events appear here.",
      ),
    ]
  }
  [
    @html.ol(
      class="tool-list tool-logs",
      state.logs
      .rev()
      .map(entry => {
        let cells : Array[@html.Html] = [
          @html.span(class="tool-time", entry.time),
          @html.span(class="tool-severity", severity_label(entry.severity)),
          @html.span(class="tool-operation", entry.operation),
          @html.span(class="tool-message", entry.message),
        ]
        if entry.failure is Some(failure) {
          let key = "log-" + entry.id.to_string()
          cells.push(
            @html.div(class="tool-extra", [
              disclosure(
                state,
                key,
                "Details",
                "Details of " + failure_subject(failure),
                emit,
              ),
            ]),
          )
          if state.open.contains(key) {
            cells.push(failure_details(state, key, failure, entry.time, emit))
          }
        }
        @html.li(class="tool-log " + severity_class(entry.severity), cells)
      }),
    ),
  ]
}

///|
fn diagnostics_view(
  state : State,
  revisions : Map[String, Int32],
  emit : @cmd.Emit[Action],
) -> Array[@html.Html] {
  if state.reports.is_empty() {
    return [
      empty(
        "No diagnostics yet. Compiler, generator, input and host problems from your runs appear here with their codes and locations.",
      ),
    ]
  }
  state.reports
  .rev()
  .map(report => {
    let current = state.is_current(report, revisions)
    let heading = report.operation +
      " · job " +
      report.job.to_string() +
      (if report.scope == "session" {
        ""
      } else {
        " · " + report.scope + " revision " + report.revision.to_string()
      }) +
      " · " +
      report.time
    @html.section(
      class=if current { "tool-report current" } else { "tool-report previous" },
      [
        @html.div(class="tool-report-heading", [
          @html.span(
            class="tool-badge",
            if current {
              "Current"
            } else {
              "Previous"
            },
          ),
          @html.span(heading),
        ]),
        if report.diagnostics.is_empty() {
          @html.p(class="tool-clean", "No problems reported.")
        } else {
          @html.ul(
            class="tool-list",
            report.diagnostics.mapi((index, d) => {
              diagnostic_row(state, report, index, d, emit)
            }),
          )
        },
      ],
    )
  })
}

///|
/// One diagnostic: severity, code, message and location on one line, and its details behind a disclosure.
fn diagnostic_row(
  state : State,
  report : Report,
  index : Int32,
  d : Diagnostic,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let key = "diagnostic-" + report.id.to_string() + "-" + index.to_string()
  let subject = (if d.code == "" { severity_label(d.severity) } else { d.code }) +
    (if d.location == "" { "" } else { " at " + d.location })
  let location = match d.place {
    Some(place) =>
      @html.button(
        class="tool-location tool-reveal",
        title=d.coordinates,
        on_click=emit(Reveal(place)),
        d.location,
      )
    None =>
      @html.span(
        class="tool-location",
        hidden=d.location == "",
        title=d.coordinates,
        d.location,
      )
  }
  let cells : Array[@html.Html] = [
    @html.span(class="tool-severity", severity_label(d.severity)),
    @html.code(class="tool-code", hidden=d.code == "", d.code),
    @html.span(class="tool-message", d.message),
    location,
    disclosure(state, key, "Details", "Details of " + subject, emit),
  ]
  if state.open.contains(key) {
    let rows : Array[@html.Html] = []
    if d.code != "" {
      rows.append(detail_row("Code", @html.code(d.code)))
    }
    rows.append(detail_row("Severity", @html.text(severity_label(d.severity))))
    if d.stage != "" {
      rows.append(detail_row("Stage", @html.text(stage_label(d.stage))))
    }
    if d.location != "" {
      rows.append(
        detail_row(
          "Location",
          @html.span([
            match d.place {
              Some(place) =>
                @html.button(
                  class="tool-reveal",
                  attrs=@html.Attrs::build().aria_label("Open " + d.location),
                  on_click=emit(Reveal(place)),
                  d.location,
                )
              None => @html.text(d.location)
            },
            if d.coordinates == "" {
              @html.nothing
            } else {
              @html.span(class="tool-coordinates", d.coordinates)
            },
          ]),
        ),
      )
    }
    rows.append(
      detail_row("Message", @html.span(class="tool-detail-message", d.message)),
    )
    rows.append(
      detail_row(
        "Reported by",
        @html.text(report.operation + " · job " + report.job.to_string()),
      ),
    )
    if report.failure is Some(failure) {
      for pair in failure.context {
        if pair.1 != "" {
          rows.append(detail_row(pair.0, @html.text(pair.1)))
        }
      }
    }
    let details : Array[@html.Html] = [@html.dl(class="tool-detail-grid", rows)]
    if !d.related.is_empty() {
      details.push(
        @html.div(class="tool-related", [
          @html.p(class="tool-detail-heading", "Related declarations"),
          @html.ul(
            d.related.map(r => {
              @html.li([
                @html.code(r.owner),
                @html.span(
                  "Authored: " + r.original + " · Allocated: " + r.allocated,
                ),
                @html.span(title=r.coordinates, r.location),
              ])
            }),
          ),
        ]),
      )
    }
    if d.fix != "" {
      details.push(@html.p(class="tool-fix", d.fix))
    }
    details.append(
      detail_actions(
        state,
        key,
        subject,
        diagnostic_text(d, report),
        report.failure.map(f => f.raw).unwrap_or(""),
        emit,
      ),
    )
    cells.push(@html.div(id=details_id(key), class="tool-details", details))
  }
  @html.li(class="tool-diagnostic " + severity_class(d.severity), cells)
}

///|
fn output_view(state : State, emit : @cmd.Emit[Action]) -> Array[@html.Html] {
  if state.outcomes.is_empty() {
    return [
      empty(
        "No output yet. Results and summaries from runs, worksheets, evaluations and compiles appear here. Generated files and IR stay in their panes.",
      ),
    ]
  }
  state.outcomes
  .rev()
  .map(outcome => {
    @html.section(class="tool-outcome " + severity_class(outcome.severity), [
      @html.div(class="tool-report-heading", [
        @html.span(class="tool-time", outcome.time),
        @html.strong(outcome.title),
      ]),
      match outcome.terminal {
        Some(summary) =>
          @terminal_view.view(@outcomes.Valid(summary), show_values=true)
        None => @html.pre(class="tool-lines", outcome.lines.join("\n"))
      },
      match outcome.failure {
        Some(failure) => {
          let key = "outcome-" + outcome.id.to_string()
          @html.div(class="tool-outcome-details", [
            disclosure(
              state,
              key,
              "Details",
              "Details of " + failure_subject(failure),
              emit,
            ),
            if state.open.contains(key) {
              failure_details(state, key, failure, outcome.time, emit)
            } else {
              @html.nothing
            },
          ])
        }
        None => @html.nothing
      },
    ])
  })
}

///|
pub fn view(props : Props, emit : @cmd.Emit[Action]) -> @html.Html {
  let state = props.state
  let open = state.size != Collapsed
  let problems = state.problem_count(props.revisions)
  let tab_buttons = tabs.map(tab => {
    let selected = tab == state.tab
    let count = if tab == Diagnostics && problems > 0 {
      problems.to_string()
    } else {
      ""
    }
    @html.button(
      id=tab_id(tab),
      class=if selected && open {
        "tool-tab selected"
      } else if selected {
        "tool-tab current"
      } else {
        "tool-tab"
      },
      attrs=@html.Attrs::build()
        .role("tab")
        .aria_selected(selected.to_string())
        .aria_controls("tool-panel-body")
        .tabindex(if selected { 0 } else { -1 }),
      on_click=emit(Activate(tab)),
      [
        @html.span(tab_label(tab)),
        @html.span(class="tool-count", hidden=count == "", count),
      ],
    )
  })
  let controls = match state.size {
    Collapsed => [control("Open panel", "chevron", emit(Open), Some(false))]
    Normal =>
      [
        control("Maximize panel", "expand", emit(Expand), None),
        control("Collapse panel", "chevron-down", emit(Collapse), Some(true)),
      ]
    Expanded =>
      [
        control("Restore panel size", "restore", emit(Restore), None),
        control("Collapse panel", "chevron-down", emit(Collapse), Some(true)),
      ]
  }
  let (summary, content) = match state.tab {
    Logs =>
      (
        state.logs.length().to_string() +
        " of at most " +
        max_logs.to_string() +
        " events, newest first",
        logs_view(state, emit),
      )
    Diagnostics =>
      (
        plural(problems, "current problem") +
        " · " +
        plural(state.reports.length(), "report") +
        ", newest first",
        diagnostics_view(state, props.revisions, emit),
      )
    Output =>
      (
        plural(state.outcomes.length(), "result") + ", newest first",
        output_view(state, emit),
      )
  }
  let size = match state.size {
    Collapsed => "collapsed"
    Normal => "normal"
    Expanded => "expanded"
  }
  @html.footer(class="tool-panel " + size, [
    @html.div(class="tool-bar", [
      @html.div(
        class="tool-tabs",
        // Tab navigation keys move focus only; they must not scroll the page
        // or the workspace behind the panel.
        attrs=@html.Attrs::build()
          .role("tablist")
          .aria_label("Tool panel")
          .on_keydown(event => {
            let key = event.key()
            if navigation_keys.contains(key) {
              event.prevent_default()
              emit(Key(key))
            } else {
              @cmd.none
            }
          }),
        tab_buttons,
      ),
      @html.span(
        class="statusbar",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        if props.busy {
          "◌ " + props.status
        } else {
          props.status
        },
      ),
      @html.div(class="tool-controls", controls),
    ]),
    @html.div(
      id="tool-panel-body",
      class="tool-body",
      hidden=!open,
      attrs=@html.Attrs::build()
        .role("tabpanel")
        .aria_labelledby(tab_id(state.tab))
        .tabindex(0),
      [
        @html.div(class="tool-body-heading", [
          @html.span(summary),
          @html.button(
            class="ghost",
            disabled=content.length() == 1 &&
              (match state.tab {
                Logs => state.logs.is_empty()
                Diagnostics => state.reports.is_empty()
                Output => state.outcomes.is_empty()
              }),
            on_click=emit(Clear),
            "Clear " + tab_label(state.tab).to_lower(),
          ),
        ]),
        @html.div(class="tool-content", content),
      ],
    ),
  ])
}
