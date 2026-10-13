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
pub(all) struct Log {
  id : Int
  time : String
  operation : String
  severity : Severity
  message : String
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
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  message : String
  location : String
  coordinates : String
  related : Array[Related]
  fix : String
  stage : String
} derive(Eq)

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
/// Diagnostics from one operation run, scoped to the document revision it read.
pub(all) struct Report {
  id : Int
  time : String
  operation : String
  job : Int
  scope : String
  revision : Int
  diagnostics : Array[Diagnostic]
} derive(Eq)

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub(all) struct Outcome {
  id : Int
  time : String
  operation : String
  severity : Severity
  title : String
  lines : Array[String]
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
  next : Int
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
}

///|
pub let max_logs : Int = 200

///|
pub let max_reports : Int = 20

///|
pub let max_diagnostics : Int = 50

///|
pub let max_outcomes : Int = 50

///|
pub let max_text : Int = 4000

///|
let tabs : Array[Tab] = [Logs, Diagnostics, Output]

///|
let navigation_keys : Array[String] = ["ArrowLeft", "ArrowRight", "Home", "End"]

///|
pub fn State::new() -> State {
  { tab: Logs, size: Collapsed, logs: [], reports: [], outcomes: [], next: 1, }
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
fn tab_index(tab : Tab) -> Int {
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
fn[T] keep_last(items : Array[T], item : T, limit : Int) -> Array[T] {
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
) -> State {
  let entry = {
    id: self.next,
    time,
    operation,
    severity,
    message: bounded(message),
  }
  { ..self, logs: keep_last(self.logs, entry, max_logs), next: self.next + 1, }
}

///|

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
  job : Int,
  scope : String,
  revision : Int,
  diagnostics : Array[Diagnostic],
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
) -> State {
  let entry = {
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
  revisions : Map[String, Int],
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
/// Errors and warnings in current reports.
pub fn State::problem_count(self : State, revisions : Map[String, Int]) -> Int {
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
fn number(value : Json, key : String) -> Int? {
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
/// The local MoonBit frontend reports one-based lines and zero-based columns.
fn frontend_diagnostic(value : Json) -> Diagnostic {
  let source = field(value, "source")
  let (location, coordinates) = match
    (
      number(source, "startLine"),
      number(source, "startColumn"),
      number(source, "endLine"),
      number(source, "endColumn"),
    ) {
    (Some(line), Some(column), Some(end_line), Some(end_column)) =>
      (
        "line " + line.to_string() + ", column " + (column + 1).to_string(),
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
    _ => ("", text(value, "coordinateProfile"))
  }
  {
    severity: Error,
    code: text(value, "code"),
    message: text(value, "detail"),
    location,
    coordinates,
    related: [],
    fix: "",
    stage: "",
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
  }
}

///|
pub fn reply_diagnostics(reply : Json) -> Array[Diagnostic] {
  let found : Array[Diagnostic] = []
  let failed = field(reply, "success") != Json::boolean(true)
  if field(reply, "frontendDiagnostic") is Object(_) {
    found.push(frontend_diagnostic(field(reply, "frontendDiagnostic")))
  }
  for diagnostic in items(field(reply, "diagnostics")) {
    found.push(host_diagnostic(diagnostic))
  }
  if failed && found.is_empty() {
    found.push({
      severity: Error,
      code: "",
      message: text(reply, "message"),
      location: "",
      coordinates: "",
      related: [],
      fix: "",
      stage: "",
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
      stage: "",
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
      stage: "",
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
    })
  }
  found
}

// View ---------------------------------------------------------------------

///|
pub(all) struct Props {
  state : State
  status : String
  busy : Bool
  revisions : Map[String, Int]
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
fn plural(count : Int, noun : String) -> String {
  count.to_string() + " " + noun + (if count == 1 { "" } else { "s" })
}

///|
fn empty(message : String) -> @html.Html {
  @html.p(class="tool-empty", message)
}

///|
fn logs_view(state : State) -> Array[@html.Html] {
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
        @html.li(class="tool-log " + severity_class(entry.severity), [
          @html.span(class="tool-time", entry.time),
          @html.span(class="tool-severity", severity_label(entry.severity)),
          @html.span(class="tool-operation", entry.operation),
          @html.span(class="tool-message", entry.message),
        ])
      }),
    ),
  ]
}

///|
fn diagnostics_view(
  state : State,
  revisions : Map[String, Int],
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
            report.diagnostics.map(d => {
              @html.li(class="tool-diagnostic " + severity_class(d.severity), [
                @html.span(class="tool-severity", severity_label(d.severity)),
                @html.code(class="tool-code", hidden=d.code == "", d.code),
                @html.span(class="tool-message", d.message),
                @html.span(
                  class="tool-location",
                  hidden=d.location == "",
                  title=d.coordinates,
                  d.location,
                ),
                @html.details(
                  class="tool-related",
                  hidden=d.related.is_empty() && d.fix == "",
                  [
                    @html.summary(
                      (if d.stage == "" { "" } else { d.stage + " · " }) +
                      "Related declarations and suggested fix",
                    ),
                    @html.ul(
                      d.related.map(r => {
                        @html.li([
                          @html.code(r.owner),
                          @html.span(
                            "Authored: " +
                            r.original +
                            " · Allocated: " +
                            r.allocated,
                          ),
                          @html.span(title=r.coordinates, r.location),
                        ])
                      }),
                    ),
                    @html.p(class="tool-fix", hidden=d.fix == "", d.fix),
                  ],
                ),
              ])
            }),
          )
        },
      ],
    )
  })
}

///|
fn output_view(state : State) -> Array[@html.Html] {
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
      @html.pre(class="tool-lines", outcome.lines.join("\n")),
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
        logs_view(state),
      )
    Diagnostics =>
      (
        plural(problems, "current problem") +
        " · " +
        plural(state.reports.length(), "report") +
        ", newest first",
        diagnostics_view(state, props.revisions),
      )
    Output =>
      (
        plural(state.outcomes.length(), "result") + ", newest first",
        output_view(state),
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
