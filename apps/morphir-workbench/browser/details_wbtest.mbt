///|
test "a failed compile keeps its job context on the log, the output and the report" {
  let model = { ..ready_model(), panel: @bottom_panel.State::new(), }
  let reply : Json = {
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
    "irSource": "{\"secret\": \"model\"}",
  }
  let after = initialized_compile(model, reply)
  let failures = [
    after.panel.logs.last().bind(l => l.failure),
    after.panel.outcomes.last().bind(o => o.failure),
    after.panel.reports.last().bind(r => r.failure),
  ]
  @expect.expect_all(s => {
    for found in failures {
      match found {
        Some(failure) => {
          s.expect(failure.code, label="code").to_equal("elm.parse")
          s.expect(failure.stage, label="stage").to_equal("frontend")
          s.expect(failure.operation, label="operation").to_equal("Compile")
          s
          .expect(failure.context.map(pair => pair.0), label="context")
          .to_contain_all([
            "Language", "Profile", "Provider", "Target", "Project", "Source revision",
            "Duration",
          ])
          s
          .expect(
            failure.context
            .filter(pair => pair.0 == "Project")
            .map(pair => pair.1),
            label="project",
          )
          .to_equal(["Workbench (1 file)"])
          s
          .expect(failure.raw, label="raw keeps the code")
          .to_contain("elm.parse")
          s
          .expect(failure.raw, label="raw omits models")
          .not()
          .to_contain("secret")
          s
          .expect(failure.raw, label="raw says what it omitted")
          .to_contain("<omitted: ")
        }
        None =>
          s
          .expect(found is Some(_), label="every panel has the failure")
          .to_be_true()
      }
    }
  })
}

///|
test "a failed Ion decode reports its Ion code with the file it read" {
  let artifact : Json = {
    "path": "symbols.10n",
    "content": "4AEA6t6fgQ==",
    "binary": true,
    "encoding": "base64",
  }
  let model = {
    ..ready_model(language="moonbit"),
    output: { "success": true, "artifacts": [artifact] },
    target: "moonbit",
    busy: true,
    job: 9,
    generated_state: { ..@generated.State::new(), selected: "symbols.10n", },
    panel: @bottom_panel.State::new(),
  }
  let reply : Json = {
    "success": false,
    "message": "Ion: Unexpected end of input",
    "code": "ion.syntax",
    "stage": "decode",
  }
  let (after, _) = update(
    model,
    Receive(9, model.output_revision, "decode-ion", reply.stringify()),
    ignore_cmds(),
  )
  let failure = after.panel.logs.last().bind(log => log.failure)
  @expect.expect_all(s => {
    s.expect(after.busy, label="done").to_be_false()
    s
    .expect(failure.map(f => f.code), label="code")
    .to_equal(Some("ion.syntax"))
    s
    .expect(failure.map(f => f.operation), label="operation")
    .to_equal(Some("View as Ion text"))
    s
    .expect(
      failure.map(f => {
        f.context.filter(pair => pair.0 == "File").map(pair => pair.1)
      }),
      label="file",
    )
    .to_equal(Some(["symbols.10n"]))
    s.expect(after.output, label="output kept").to_equal(model.output)
  })
}

///|
test "a decoded file shows in the Generated tab; a decode waits for a running job" {
  let artifact : Json = {
    "path": "symbols.10n",
    "content": "4AEA6g8=",
    "binary": true,
    "encoding": "base64",
  }
  let model = {
    ..ready_model(language="moonbit"),
    output: { "success": true, "artifacts": [artifact] },
    target: "moonbit",
    generated_state: { ..@generated.State::new(), selected: "symbols.10n", },
  }
  let started = send(model, [RunCommand(ViewIonText)])
  let busy = send({ ..model, busy: true, job: 3, }, [RunCommand(ViewIonText)])
  let reply : Json = {
    "success": true,
    "operation": "decode-ion",
    "path": "symbols.10n",
    "text": "null",
    "values": 1,
    "bytes": 5,
  }
  let (shown, _) = update(
    started,
    Receive(
      started.job,
      started.output_revision,
      "decode-ion",
      reply.stringify(),
    ),
    ignore_cmds(),
  )
  @expect.expect_all(s => {
    s.expect(started.busy, label="a job").to_be_true()
    s.expect(started.job, label="new job").to_equal(model.job + 1)
    s.expect(busy.job, label="busy refuses").to_equal(3)
    s
    .expect(shown.generated_state.preview, label="decoded")
    .to_equal(IonText("symbols.10n", "null", 1))
    s.expect(shown.busy, label="done").to_be_false()
    s.expect(shown.output, label="output kept").to_equal(model.output)
  })
}

///|
/// Stubs the page's artifact download for one test; returns a function that restores the page.
extern "js" fn download_test_environment() -> () -> Unit =
  #|() => {
  #|  const workbench = globalThis.morphirWorkbench;
  #|  globalThis.morphirWorkbench = { connected: false, downloadArtifacts: () => "" };
  #|  return () => {
  #|    if (workbench === undefined) delete globalThis.morphirWorkbench; else globalThis.morphirWorkbench = workbench;
  #|  };
  #|}

///|
fn two_artifacts_model() -> Model {
  let artifact = fn(path : String) -> Json {
    {
      "path": path,
      "content": "4AEA6g8=",
      "binary": true,
      "encoding": "base64",
    }
  }
  {
    ..ready_model(language="moonbit"),
    output: {
      "success": true,
      "artifacts": [artifact("a.10n"), artifact("b.10n")],
    },
    target: "moonbit",
    generated_state: {
      ..@generated.State::new(),
      selected: "a.10n",
      preview: IonText("a.10n", "null", 1),
    },
  }
}

///|
test "Download from a file's menu leaves the selection and the preview" {
  let restore = download_test_environment()
  defer restore()
  let model = two_artifacts_model()
  let after = send(model, [
    Generated(OpenMenu("b.10n", 10, 10, 800, 600)),
    Generated(Choose(Download)),
  ])
  @expect.expect_all(s => {
    s
    .expect(after.generated_state.selected, label="selection")
    .to_equal("a.10n")
    s
    .expect(after.generated_state.preview, label="preview")
    .to_equal(IonText("a.10n", "null", 1))
    s.expect(after.generated_state.menu, label="menu closed").to_be_none()
    s
    .expect(after.panel.logs.last().map(log => log.message), label="downloaded")
    .to_equal(Some("Downloaded b.10n"))
  })
}

///|
test "a connected workbench does not send a decode to its host" {
  let model = { ..two_artifacts_model(), connected: true, }
  let from_palette = send(model, [RunCommand(ViewIonText)])
  let from_heading = send(model, [Generated(ViewIonTextOf("a.10n"))])
  @expect.expect_all(s => {
    s.expect(from_palette.job, label="palette").to_equal(model.job)
    s.expect(from_heading.job, label="heading").to_equal(model.job)
    s.expect(from_heading.busy, label="not busy").to_be_false()
    s
    .expect(from_heading.status, label="says why")
    .to_equal("Ion text is decoded by the browser-local worker only")
  })
}
