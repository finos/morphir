///|
test "tabs open, switch and collapse the panel" {
  let state = @bottom_panel.State::new()
  assert_true(state.size == @bottom_panel.Collapsed)
  let (open, focus) = state.update(@bottom_panel.Activate(@bottom_panel.Output))
  assert_true(
    open.size == @bottom_panel.Normal && open.tab == @bottom_panel.Output,
  )
  assert_true(focus is None)
  let (switched, _) = open.update(@bottom_panel.Activate(@bottom_panel.Logs))
  assert_true(
    switched.size == @bottom_panel.Normal && switched.tab == @bottom_panel.Logs,
  )
  let (closed, _) = switched.update(@bottom_panel.Activate(@bottom_panel.Logs))
  assert_true(
    closed.size == @bottom_panel.Collapsed && closed.tab == @bottom_panel.Logs,
  )
  let (expanded, _) = open.update(@bottom_panel.Expand)
  let (restored, _) = expanded.update(@bottom_panel.Restore)
  assert_true(
    expanded.size == @bottom_panel.Expanded &&
    restored.size == @bottom_panel.Normal,
  )
}

///|
test "terminal diagnostics retain primary and cleanup as separate causes" {
  let (_reply, projection) = @outcomes.prepare({
    "terminalOutcomes": {
      "contractVersion": "0.1.0-draft.5",
      "calls": [
        {
          "id": "workbench",
          "outcome": {
            "status": "failed",
            "failure": {
              "stage": "evaluate",
              "code": "execution.evaluate",
              "message": "Evaluate failed",
            },
          },
        },
      ],
      "cleanup": {
        "stage": "cleanup",
        "code": "provider.dispose",
        "message": "Dispose failed",
      },
      "extensions": Json::null(),
    },
  })
  let diagnostics = @bottom_panel.terminal_diagnostics(projection)
  assert_eq(diagnostics.length(), 2)
  assert_eq(diagnostics[0].stage, "cleanup")
  assert_eq(diagnostics[0].code, "provider.dispose")
  assert_eq(diagnostics[1].stage, "evaluate")
  assert_eq(diagnostics[1].code, "execution.evaluate")
  guard projection is Valid(summary) else { fail("valid evidence") }
  let history = @bottom_panel.State::new().outcome(
    "12:00:00",
    "Evaluate",
    @bottom_panel.Error,
    summary.heading(),
    [],
    terminal=Some(summary),
  )
  assert_true(history.outcomes[0].terminal == Some(summary))
  assert_true(history.outcomes[0].lines.is_empty())
}

///|
test "arrow keys move the selected tab and return the tab to focus" {
  let state = @bottom_panel.State::new()
  let (next, focus) = state.update(@bottom_panel.Key("ArrowLeft"))
  assert_true(next.tab == @bottom_panel.Output)
  assert_eq(focus, Some("tool-tab-output"))
  let (wrapped, _) = next.update(@bottom_panel.Key("ArrowRight"))
  assert_true(wrapped.tab == @bottom_panel.Logs)
  let (last, _) = wrapped.update(@bottom_panel.Key("End"))
  let (first, _) = last.update(@bottom_panel.Key("Home"))
  assert_true(
    last.tab == @bottom_panel.Output && first.tab == @bottom_panel.Logs,
  )
  let (same, none) = first.update(@bottom_panel.Key("a"))
  assert_true(same == first && none is None)
  // Keyboard selection does not open a collapsed panel by itself.
  assert_true(next.size == @bottom_panel.Collapsed)
}

///|
test "history is bounded and messages are truncated" {
  let mut state = @bottom_panel.State::new()
  for i in 0..<(@bottom_panel.max_logs + 5) {
    state = state.log(
      "12:00:00",
      "compile",
      @bottom_panel.Info,
      "event " + i.to_string(),
    )
  }
  assert_eq(state.logs.length(), @bottom_panel.max_logs)
  assert_eq(state.logs[0].message, "event 5")
  let long = "x".repeat(@bottom_panel.max_text + 10)
  let logged = state.log("12:00:01", "run", @bottom_panel.Error, long)
  assert_true(logged.logs.last().unwrap().message.has_suffix("… (truncated)"))
  let many : Array[@bottom_panel.Diagnostic] = Array::makei(
    @bottom_panel.max_diagnostics + 3,
    i => {
      severity: @bottom_panel.Error,
      code: "E" + i.to_string(),
      message: "problem",
      location: "",
      coordinates: "",
      related: [],
      fix: "",
      stage: "",
      place: None,
    },
  )
  let reported = state.report("12:00:02", "Compile", 3, "source", 4, many)
  let diagnostics = reported.reports.last().unwrap().diagnostics
  assert_eq(diagnostics.length(), @bottom_panel.max_diagnostics + 1)
  assert_eq(
    diagnostics.last().unwrap().message,
    "3 more diagnostics were not retained.",
  )
}

///|
test "reports are current only for the newest run on the current revision" {
  let error : @bottom_panel.Diagnostic = {
    severity: @bottom_panel.Error,
    code: "recursive_call",
    message: "Recursion is outside this profile",
    location: "line 1, column 1",
    coordinates: "",
    related: [],
    fix: "",
    stage: "",
    place: None,
  }
  let state = @bottom_panel.State::new()
    .report("12:00:00", "Compile", 1, "source", 4, [error])
    .report("12:00:01", "Evaluate gate", 2, "inputs", 7, [])
  let revisions = Map([("source", 4), ("inputs", 7)])
  assert_true(state.is_current(state.reports[0], revisions))
  assert_eq(state.problem_count(revisions), 1)
  // Editing the source makes the report previous without removing it.
  assert_true(!state.is_current(state.reports[0], Map([("source", 5)])))
  assert_eq(state.problem_count(Map([("source", 5)])), 0)
  // A newer clean compile of the same scope supersedes the older report.
  let fixed = state.report("12:00:02", "Compile", 3, "source", 5, [])
  assert_true(!fixed.is_current(fixed.reports[0], Map([("source", 5)])))
  assert_eq(fixed.reports.length(), 3)
  let (cleared, _) = { ..fixed, tab: @bottom_panel.Diagnostics, }.update(
    @bottom_panel.Clear,
  )
  assert_true(cleared.reports.is_empty() && cleared.next == fixed.next)
}

///|
test "reply diagnostics keep codes, severities and locations" {
  let frontend = @json.parse(
    (
      #|{"success":false,"message":"recursive_call: recursion","frontendDiagnostic":{"code":"recursive_call","coordinateProfile":"moonbit-parser-position-v1","detail":"recursion","source":{"startLine":3,"startColumn":4,"endLine":3,"endColumn":9}}}
    ),
  )
  let found = @bottom_panel.reply_diagnostics(frontend)
  assert_eq(found.length(), 1)
  assert_true(found[0].severity == @bottom_panel.Error)
  assert_eq(found[0].code, "recursive_call")
  assert_eq(found[0].location, "line 3, column 5")
  assert_eq(found[0].coordinates, "moonbit-parser-position-v1 3:4–3:9")
  let host = @json.parse(
    (
      #|{"success":true,"diagnostics":[{"severity":"warning","code":"W1","message":"Unused","location":{"uri":"file:///main.gleam","range":{"start":{"line":0,"character":4},"end":{"line":0,"character":9}}}}],"generationWarnings":["Shadowed name"],"inspectionMessage":"Unsupported IR"}
    ),
  )
  let host_found = @bottom_panel.reply_diagnostics(host)
  assert_eq(host_found.length(), 3)
  assert_true(host_found[0].severity == @bottom_panel.Warning)
  assert_eq(host_found[0].location, "main.gleam:1:5")
  assert_eq(host_found[0].coordinates, "file:///main.gleam 0:4–0:9")
  assert_eq(host_found[1].message, "Shadowed name")
  assert_eq(
    host_found[2].message,
    "Local inspection is unavailable: Unsupported IR",
  )
  let generation = @json.parse(
    (
      #|{"success":true,"generationDiagnostics":[{"code":"unsupported-literal","nodePath":"main/answer","detail":"Float"}],"generationMessage":"Elm generation failed: unsupported-literal at main/answer: Float"}
    ),
  )
  let refused = @bottom_panel.reply_diagnostics(generation)
  assert_eq(refused.length(), 1)
  assert_eq(refused[0].location, "IR node main/answer")
  let plain = @bottom_panel.reply_diagnostics(
    @json.parse("{\"success\":false,\"message\":\"Cancelled\"}"),
  )
  assert_eq(plain[0].message, "Cancelled")
  assert_eq(
    @bottom_panel.reply_diagnostics(@json.parse("{\"success\":true}")).length(),
    0,
  )
}

///|
test "naming diagnostics retain related declarations as one scoped warning" {
  let reply = @json.parse(
    (
      #|{"success":true,"sourceWarnings":[{"code":"collision","stage":"frontend","message":"Recovered","fix":"Rename is_ready","coordinateProfile":"moonbit-parser-position-v1","locations":[{"owner":"value:ready","original":"isReady","allocated":"is-ready","source":{"startLine":2,"startColumn":7,"endLine":2,"endColumn":14}},{"owner":"value:ready-2","original":"is_ready","allocated":"is-ready-source","source":null}]}],"generationWarnings":[{"code":"backend-recovery","message":"Allocated","fix":"Choose a name","locations":[]},"Old warning"]}
    ),
  )
  let found = @bottom_panel.reply_diagnostics(reply)
  assert_eq(found.length(), 3)
  assert_true(found[0].severity == @bottom_panel.Warning)
  assert_eq(found[0].related.length(), 2)
  assert_eq(found[0].fix, "Rename is_ready")
  assert_eq(found[0].stage, "frontend")
  assert_eq(found[0].related[0].original, "isReady")
  assert_eq(found[0].related[0].allocated, "is-ready")
  assert_eq(found[0].related[0].location, "line 2, column 8")
  assert_eq(
    found[0].related[0].coordinates,
    "moonbit-parser-position-v1 2:7–2:14",
  )
  assert_eq(found[0].related[1].location, "")
  assert_eq(found[1].code, "backend-recovery")
  assert_eq(found[2].message, "Old warning")
  let reported = @bottom_panel.State::new().report(
    "12:00:00", "Compile", 1, "source", 3, found,
  )
  assert_eq(reported.problem_count(Map([("source", 3)])), 3)
  assert_eq(reported.problem_count(Map([("source", 4)])), 0)
  let many = Array::make(25, found[0].related[0])
  let bounded = reported.report("12:01:00", "Compile", 2, "source", 4, [
    { ..found[0], related: many, fix: "x".repeat(5000), },
  ])
  let stored = bounded.reports.last().unwrap().diagnostics[0]
  assert_eq(stored.related.length(), 20)
  assert_true(stored.message.contains("5 more related locations not retained"))
  assert_true(stored.fix.has_suffix("… (truncated)"))
}

///|
test "per-file frontend problems show their file and Elm columns as written" {
  let reply = @json.parse(
    (
      #|{"success":false,"message":"elm.parse: x","frontendDiagnostic":{"code":"elm.parse","coordinateProfile":"elm-source-position-v1","detail":"x","path":"src/A/B.elm","source":{"startLine":4,"startColumn":9,"endLine":4,"endColumn":10}},"frontendDiagnostics":[{"path":"src/A/B.elm","problems":[{"code":"elm.parse","coordinateProfile":"elm-source-position-v1","detail":"x","path":"src/A/B.elm","source":{"startLine":4,"startColumn":9,"endLine":4,"endColumn":10}},{"code":"elm.name","coordinateProfile":"elm-source-position-v1","detail":"y","path":"src/A/B.elm","source":null}]}]}
    ),
  ) catch {
    _ => abort("json")
  }
  let found = @bottom_panel.reply_diagnostics(reply).map(d => {
    (d.code, d.location)
  })
  @expect.expect(found, label="panel entries").to_equal([
    ("elm.parse", "src/A/B.elm line 4, column 9"),
    ("elm.name", "src/A/B.elm"),
  ])
}

///|
/// Property: the panel shows an Elm column as written and a MoonBit parser column plus one, for any position.
test "the panel column follows the coordinate profile" {
  @expect.for_all((position : (UInt32, UInt32)) => {
    let line = (position.0 % 10000).reinterpret_as_int() + 1
    let column = (position.1 % 10000).reinterpret_as_int()
    let shown = (profile : String) => {
      let reply : Json = {
        "success": false,
        "frontendDiagnostic": {
          "code": "c",
          "coordinateProfile": profile,
          "detail": "d",
          "source": {
            "startLine": Json::number(line.to_double()),
            "startColumn": Json::number(column.to_double()),
            "endLine": Json::number(line.to_double()),
            "endColumn": Json::number((column + 1).to_double()),
          },
        },
      }
      @bottom_panel.reply_diagnostics(reply)[0].location
    }
    @expect.expect(shown("elm-source-position-v1"), label="elm").to_equal(
      "line \{line}, column \{column}",
    )
    @expect.expect(shown("moonbit-parser-position-v1"), label="moonbit").to_equal(
      "line \{line}, column \{column + 1}",
    )
  })
}

///|
test "a placed problem carries its path, line and display column" {
  let reply = @json.parse(
    (
      #|{"success":false,"frontendDiagnostics":[{"path":"src/A/B.elm","problems":[{"code":"elm.parse","coordinateProfile":"elm-source-position-v1","detail":"x","path":"src/A/B.elm","source":{"startLine":4,"startColumn":9,"endLine":4,"endColumn":10}}]}]}
    ),
  ) catch {
    _ => abort("json")
  }
  let found = @bottom_panel.reply_diagnostics(reply)
  @expect.expect(found.map(d => d.place), label="place").to_equal([
    Some({ path: "src/A/B.elm", line: 4, column: 9, }),
  ])
}

///|
/// Property: the display column is the reported column for one-based profiles and one more for the MoonBit parser.
test "display_column follows the coordinate profile" {
  @expect.for_all((c : UInt32) => {
    let column = (c % 100000).reinterpret_as_int()
    @expect.expect_all(s => {
      s
      .expect(
        @bottom_panel.display_column("elm-source-position-v1", column),
        label="elm",
      )
      .to_equal(column)
      s
      .expect(
        @bottom_panel.display_column("moonbit-parser-position-v1", column),
        label="moonbit",
      )
      .to_equal(column + 1)
    })
  })
}

///|
test "a problem without its own path takes its file's path" {
  let reply = @json.parse(
    (
      #|{"success":false,"frontendDiagnostics":[{"path":"src/A/B.elm","problems":[{"code":"elm.parse","coordinateProfile":"elm-source-position-v1","detail":"x","source":{"startLine":2,"startColumn":3,"endLine":2,"endColumn":4}}]}]}
    ),
  ) catch {
    _ => abort("json")
  }
  @expect.expect(
    @bottom_panel.reply_diagnostics(reply).map(d => d.place),
    label="place",
  ).to_equal([Some({ path: "src/A/B.elm", line: 2, column: 3, })])
}

///|
let sample_failure : @bottom_panel.Failure = {
  job: 7,
  operation: "Compile",
  code: "workbench.internal_error",
  stage: "reply",
  message: "The workbench failed while preparing the compile result (missing_member: entries)",
  context: [
    ("Language", "Elm"),
    ("Profile", ""),
    ("Target", "elm"),
    ("Duration", "130 ms"),
  ],
  raw: "{\n  \"success\": false\n}",
}

///|
test "a failed job's report names its code, stage, context and reply" {
  let text = @bottom_panel.failure_text(sample_failure, "12:00:01")
  @expect.expect_all(s => {
    s
    .expect(text, label="report")
    .to_contain_substrings_in_order([
      "Messages can quote your source.",
      "Morphir Workbench failure",
      "Operation: Compile (job 7)",
      "Code: workbench.internal_error",
      "Stage: internal (reply)",
      "Message: The workbench failed",
      "Language: Elm",
      "Target: elm",
      "Duration: 130 ms",
      "Time: 12:00:01",
      "Reply (" + @bottom_panel.raw_note + "):",
      "\"success\": false",
    ])
    s.expect(text, label="empty context left out").not().to_contain("Profile:")
  })
}

///|
test "a diagnostic's report names its location and the job that reported it" {
  let frontend : Json = {
    "success": false,
    "message": "elm.parse: Unexpected token",
    "code": "elm.parse",
    "stage": "frontend",
    "frontendDiagnostics": [
      {
        "path": "src/Workbench/Main.elm",
        "problems": [
          {
            "code": "elm.parse",
            "coordinateProfile": "elm-source-position-v1",
            "detail": "Unexpected token",
            "source": {
              "startLine": 3,
              "startColumn": 7,
              "endLine": 3,
              "endColumn": 8,
            },
            "stage": "frontend",
          },
        ],
      },
    ],
  }
  let diagnostics = @bottom_panel.reply_diagnostics(frontend)
  let state = @bottom_panel.State::new().report(
    "12:00:02",
    "Compile",
    7,
    "source",
    3,
    diagnostics,
    failure=Some(sample_failure),
  )
  let report = state.reports[0]
  let text = @bottom_panel.diagnostic_text(report.diagnostics[0], report)
  let failed = @bottom_panel.reply_diagnostics({
    "success": false,
    "message": "The request is not valid (missing_member: operation)",
    "code": "workbench.invalid_request",
    "stage": "request",
  })
  @expect.expect_all(s => {
    s.expect(diagnostics[0].stage, label="stage").to_equal("frontend")
    s
    .expect(text, label="report")
    .to_contain_substrings_in_order([
      "Messages can quote your source.", "Morphir Workbench diagnostic", "Severity: Error",
      "Code: elm.parse", "Stage: frontend", "Location: src/Workbench/Main.elm line 3, column 7 (elm-source-position-v1 3:7–3:8)",
      "Message: Unexpected token", "Reported by: Compile (job 7, source revision 3) at 12:00:02",
      "Language: Elm",
    ])
    s
    .expect(
      failed.map(d => (d.code, d.stage)),
      label="failure keeps code and stage",
    )
    .to_equal([("workbench.invalid_request", "request")])
    s
    .expect(
      report.failure == Some(sample_failure),
      label="report keeps the job",
    )
    .to_be_true()
  })
}

///|
test "details open and close, and a raw reply is bounded" {
  let long = { ..sample_failure, raw: "x".repeat(@bottom_panel.max_raw + 10), }
  let state = @bottom_panel.State::new().log(
    "12:00:03",
    "Compile",
    Error,
    "Job 7 failed",
    failure=Some(long),
  )
  let (opened, _) = state.update(Toggle("log-1"))
  let (closed, _) = opened.update(Toggle("log-1"))
  let (copied, focus) = state.update(CopyDetails("report"))
  @expect.expect_all(s => {
    s.expect(opened.open, label="open").to_equal(["log-1"])
    s.expect(closed.open, label="closed").to_be_empty()
    s.expect(copied == state, label="copy leaves the state").to_be_true()
    s.expect(focus, label="no focus").to_be_none()
    s
    .expect(state.logs[0].failure.map(f => f.raw.length()), label="bounded raw")
    .to_satisfy(n => n is Some(length) && length < @bottom_panel.max_raw + 20)
    s
    .expect(state.logs[0].failure.map(f => f.raw), label="truncation noted")
    .to_satisfy(raw => raw is Some(text) && text.has_suffix("(truncated)"))
  })
}

///|
/// Property: at most `max_open` details stay open, whatever is toggled.
test "open details are bounded" {
  @expect.for_all((keys : Array[UInt32]) => {
    let state = keys.fold(init=@bottom_panel.State::new(), (state, key) => {
      state.update(Toggle("log-" + (key % 80).to_string())).0
    })
    @expect.expect(state.open.length(), label="open").to_be_less_than_or_equal(
      @bottom_panel.max_open,
    )
    @expect.expect(state.open, label="distinct").to_have_no_duplicates()
  })
}

///|
test "a raw reply keeps structure, codes and messages and omits source of any shape" {
  let long_message = "elm.parse: Unexpected token where a declaration was expected"
  let reply = @bottom_panel.redacted({
    "success": false,
    "code": "elm.parse",
    "message": long_message,
    "counts": { "errors": 1 },
    "project": {
      "files": [
        { "path": "src/A.elm", "content": ["module A", "exposing (..)"] },
      ],
    },
    "results": [{ "expression": "(+ 1 2)", "value": "3" }],
    "notes": "a member no list names, with a long text",
    "target": "elm",
    "problems": [
      { "code": "elm.parse", "source": "module Main exposing (main)" },
      {
        "code": "elm.parse",
        "source": {
          "startLine": 3,
          "startColumn": 7,
          "endLine": 3,
          "endColumn": 8,
        },
      },
      { "code": "elm.parse", "source": { "line": 3, "column": "x" } },
    ],
    "sourceUnitIon": { "unit": "a" },
  })
  @expect.expect(reply.stringify()).to_equal(
    (
      {
        "success": false,
        "code": "elm.parse",
        "message": long_message,
        "counts": { "errors": 1 },
        "project": {
          "files": [
            { "path": "src/A.elm", "content": "<omitted: 28 characters>" },
          ],
        },
        "results": [
          {
            "expression": "<omitted: 7 characters>",
            "value": "<omitted: 1 characters>",
          },
        ],
        "notes": "<omitted: 40 characters>",
        "target": "elm",
        "problems": [
          { "code": "elm.parse", "source": "<omitted: 27 characters>" },
          {
            "code": "elm.parse",
            "source": {
              "startLine": 3,
              "startColumn": 7,
              "endLine": 3,
              "endColumn": 8,
            },
          },
          { "code": "elm.parse", "source": "<omitted: 23 characters>" },
        ],
        "sourceUnitIon": "<omitted: 12 characters>",
      } : Json).stringify(),
  )
}

///|
/// Property: a long text under a member that no list keeps never reaches the raw reply, at any depth and in
/// arrays.
test "a raw reply never keeps long text under an unknown member" {
  let names = ["notes", "body", "sourceText", "source", "content", "expression"]
  @expect.for_all((case : (UInt32, UInt32)) => {
    let (pick, depth) = case
    let secret = "secret-" + pick.to_string() + "-" + "x".repeat(40)
    let mut value : Json = Json::string(secret)
    for level in 0..<(depth % 4).reinterpret_as_int() {
      value = if level % 2 == 0 {
        Json::array([value, Json::number(1)])
      } else {
        Json::object(Map([("nested", value)]))
      }
    }
    let name = names[(pick % names.length().reinterpret_as_uint()).reinterpret_as_int()]
    let reply = @bottom_panel.redacted(
      Json::object(Map([("success", Json::boolean(false)), (name, value)])),
    )
    @expect.expect(reply.stringify(), label=name).not().to_contain("secret-")
  })
}

///|
test "details ids are prefixed for the page" {
  @expect.expect([
    @bottom_panel.details_id("log-12"),
    @bottom_panel.details_id("diagnostic-4-0"),
    @bottom_panel.details_id("raw-log-12"),
    @bottom_panel.details_id("outcome-9"),
  ]).to_equal([
    "tool-details-log-12", "tool-details-diagnostic-4-0", "tool-raw-log-12", "tool-details-outcome-9",
  ])
}
