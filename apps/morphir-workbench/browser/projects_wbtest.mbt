///|
fn catalog_fixture() -> Json {
  {
    "frontends": [
      {
        "languageId": "elm",
        "displayName": "Elm",
        "fileExtensions": [".elm"],
        "providerId": "morphir-elm",
        "defaultProfile": "library",
        "profiles": [{ "id": "library", "compileKind": "whole-project" }],
      },
      {
        "languageId": "moonbit",
        "displayName": "MoonBit",
        "fileExtensions": [".mbt"],
        "providerId": "morphir-moonbit",
        "defaultProfile": "moonbit-model-bool-v1",
        "profiles": [
          { "id": "moonbit-model-bool-v1", "compileKind": "each-file" },
          { "id": "moonbit-model-bool-library-v1", "compileKind": "each-file" },
        ],
      },
      {
        "languageId": "scheme",
        "displayName": "Scheme",
        "fileExtensions": [".scm"],
        "providerId": "morphir-scheme",
        "profiles": [],
      },
    ],
  }
}

///|
test "each language keeps its own project across language switches" {
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(
    model,
    Source("(define kept 1)"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  let (elm, _) = update(edited, Language("elm"), @cmd.Emit(fn(_) { @cmd.none }))
  let (back, _) = update(
    elm,
    Language("scheme"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  @expect.expect_all(s => {
    s
    .expect(active_text(elm), label="elm default")
    .to_contain("module Workbench.Main")
    s
    .expect(active_project(elm).active.to_string(), label="elm file")
    .to_equal("src/Workbench/Main.elm")
    s.expect(active_text(back), label="scheme kept").to_equal("(define kept 1)")
  })
}

///|
fn member_of(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
test "the offline request carries the project; connected mode carries source" {
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "elm",
    connected: false,
  }
  let offline = compile_request(model, "compile")
  let connected = compile_request({ ..model, connected: true, }, "compile")
  @expect.expect_all(s => {
    s
    .expect(offline, label="offline")
    .to_contain_json({
      "operation": "compile",
      "project": {
        "name": "Workbench",
        "languageId": "elm",
        "exposedModules": ["Main"],
      },
    })
    s.expect(member_of(offline, "source"), label="no source").to_be_none()
    s
    .expect(connected, label="connected")
    .to_contain_json({ "operation": "compile", "languageId": "elm" })
    s.expect(member_of(connected, "source"), label="source").to_be_some()
  })
}

///|
test "file rules follow the selected profile and the defaults follow the language" {
  let model = { ..scope_model(), catalog: catalog_fixture(), }
  let elm = file_rules(model, "elm")
  let moonbit = file_rules(model, "moonbit")
  let library = with_selection(
    model, "moonbit", "moonbit-model-bool-library-v1",
  )
  @expect.expect_all(s => {
    s.expect(elm.layout, label="elm layout").to_equal(ManyFiles)
    s
    .expect(elm.extensions.map(e => e.to_string()), label="elm extensions")
    .to_equal([".elm"])
    s.expect(moonbit.layout, label="moonbit layout").to_equal(OneFile)
    s
    .expect(
      default_project(model, "moonbit").active.to_string(),
      label="moonbit file",
    )
    .to_equal("src/main.mbt")
    s
    .expect(
      default_project(library, "moonbit").active_file().content,
      label="library example",
    )
    .to_contain("fn gate")
    s
    .expect(
      default_project(model, "scheme").active.to_string(),
      label="scheme file",
    )
    .to_equal("src/main.scm")
  })
}

///|
fn hostile_catalog() -> Json {
  {
    "frontends": [
      {
        "languageId": "Bad Language",
        "fileExtensions": ["not-an-extension", ".a/b"],
        "providerId": "BAD PROVIDER",
        "defaultProfile": "BAD PROFILE",
        "profiles": [{ "id": "BAD PROFILE", "compileKind": "each-file" }],
      },
      {
        "languageId": "odd",
        "fileExtensions": ["/../x"],
        "providerId": "p".repeat(1000),
        "defaultProfile": "BAD PROFILE",
        "profiles": [{ "id": "BAD PROFILE", "compileKind": "each-file" }],
      },
    ],
  }
}

///|
test "ids from the catalog that do not parse never abort" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = { ..scope_model(), catalog: hostile_catalog(), language: "odd", }
  let odd = default_project(model, "odd")
  let bad = default_project(model, "Bad Language")
  let (refused, _) = update(model, Language("Bad Language"), emit)
  let (switched, _) = update(model, Language("odd"), emit)
  let (profiled, _) = update(
    { ..switched, language_projects: Map([("odd", odd)]), },
    SourceProfile("BAD PROFILE"),
    emit,
  )
  @expect.expect_all(s => {
    s
    .expect(odd.active.to_string(), label="path falls back")
    .to_equal("src/main.txt")
    s.expect(odd.provider, label="provider skipped").to_be_none()
    s.expect(odd.profile, label="profile skipped").to_be_none()
    s
    .expect(bad.language.to_string(), label="language falls back")
    .to_equal("scheme")
    s.expect(refused.language, label="language kept").to_equal("odd")
    s.expect(refused.status, label="refusal said").to_contain("not valid")
    s
    .expect(active_project(profiled).profile, label="profile kept")
    .to_be_none()
  })
}

///|
test "a host session starts with empty sources" {
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    connected: true,
    language: "elm",
  }
  @expect.expect_all(s => {
    s.expect(active_text(model), label="elm").to_equal("")
    s
    .expect(active_text({ ..model, language: "scheme", }), label="scheme")
    .to_equal("")
  })
}

///|
fn initialized(model : Model, reply : Json) -> Model {
  let busy = { ..model, busy: true, job: 7, }
  let (after, _) = update(
    busy,
    Receive(7, busy.revision, "initialize", reply.stringify()),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  after
}

///|
test "initialize with only invalid language ids selects no language" {
  let after = initialized(scope_model(), {
    "success": true,
    "operation": "initialize",
    "catalog": hostile_catalog_invalid_only(),
    "message": "ready",
  })
  @expect.expect_all(s => {
    s.expect(after.language, label="language").to_equal("")
    s.expect(after.busy, label="not busy").to_equal(false)
  })
}

///|
fn hostile_catalog_invalid_only() -> Json {
  { "frontends": [{ "languageId": "Bad Language" }, { "languageId": "" }] }
}

///|
test "a connected initialize drops the stored local projects" {
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(
    model,
    Source("(define local 1)"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  let connected = initialized(edited, {
    "success": true,
    "operation": "initialize",
    "connected": true,
    "catalog": catalog_fixture(),
    "message": "connected",
  })
  let kept = initialized(edited, {
    "success": true,
    "operation": "initialize",
    "catalog": catalog_fixture(),
    "message": "ready",
  })
  @expect.expect_all(s => {
    s
    .expect(edited.language_projects.length(), label="stored before")
    .to_equal(1)
    s
    .expect(connected.language_projects.length(), label="gone when connected")
    .to_equal(0)
    s.expect(active_text(connected), label="empty").to_equal("")
    s
    .expect(kept.language_projects.length(), label="kept when local")
    .to_equal(1)
  })
}

///|
test "file actions edit the active project and a stale entry does not crash" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = { ..scope_model(), catalog: catalog_fixture(), language: "elm", }
  let (added, _) = update(model, Files(StartAdd(Some(Root))), emit)
  let (drafted, _) = update(
    added,
    Files(Draft("src/Workbench/Extra.elm")),
    emit,
  )
  let (confirmed, _) = update(drafted, Files(Commit), emit)
  let (stale, _) = update(
    confirmed,
    Files(Open(literal_path("src/Gone.elm"))),
    emit,
  )
  @expect.expect_all(s => {
    s
    .expect(active_project(confirmed).files.length(), label="files")
    .to_equal(2)
    s
    .expect(active_project(confirmed).active.to_string(), label="opened")
    .to_equal("src/Workbench/Extra.elm")
    s.expect(stale.files_edit.error, label="stale").to_contain("No file has")
    s
    .expect(active_project(stale), label="kept")
    .to_equal(active_project(confirmed))
  })
}

///|
test "a compile reply sets the problem counts per file" {
  let model = { ..scope_model(), catalog: catalog_fixture(), language: "elm", }
  let reply : Json = {
    "success": false,
    "operation": "compile",
    "message": "Frontend errors",
    "frontendDiagnostics": [
      { "path": "src/Workbench/Main.elm", "problems": [{}, {}] },
    ],
  }
  let after = initialized_compile(model, reply)
  @expect.expect_all(s => {
    s
    .expect(after.problem_counts.get("src/Workbench/Main.elm"), label="count")
    .to_equal(Some(2))
  })
}

///|
fn initialized_compile(model : Model, reply : Json) -> Model {
  let busy = { ..model, busy: true, job: 7, }
  let (after, _) = update(
    busy,
    Receive(7, busy.revision, "compile", reply.stringify()),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  after
}

///|
test "the revision changes only when the project changes" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = { ..scope_model(), catalog: catalog_fixture(), language: "elm", }
  let (added, _) = update(model, Files(StartAdd(Some(Root))), emit)
  let (drafted, _) = update(
    added,
    Files(Draft("src/Workbench/Extra.elm")),
    emit,
  )
  let (confirmed, _) = update(drafted, Files(Commit), emit)
  let (opened, _) = update(
    confirmed,
    Files(Open(literal_path("src/Workbench/Main.elm"))),
    emit,
  )
  let counted = {
    ..opened,
    problem_counts: Map([("src/Workbench/Main.elm", 1)]),
  }
  let (switched, _) = update(counted, Language("scheme"), emit)
  let (example, _) = update(counted, Example, emit)
  @expect.expect_all(s => {
    s.expect(added.revision, label="StartAdd").to_equal(model.revision)
    s.expect(drafted.revision, label="AddDraft").to_equal(model.revision)
    s
    .expect(confirmed.revision, label="ConfirmAdd")
    .to_equal(model.revision + 1)
    s.expect(opened.revision, label="Open").to_equal(confirmed.revision)
    s
    .expect(
      opened.language_projects.get("elm").map(p => p.active.to_string()),
      label="active moved",
    )
    .to_equal(Some("src/Workbench/Main.elm"))
    s
    .expect(switched.problem_counts.length(), label="language switch")
    .to_equal(0)
    s.expect(example.problem_counts.length(), label="example").to_equal(0)
  })
}

///|
test "revealing a problem opens its file without a revision change; a stale file is only noted" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = { ..scope_model(), catalog: catalog_fixture(), language: "elm", }
  let (added, _) = update(model, Files(StartAdd(Some(Root))), emit)
  let (drafted, _) = update(
    added,
    Files(Draft("src/Workbench/Extra.elm")),
    emit,
  )
  let (confirmed, _) = update(drafted, Files(Commit), emit)
  let (opened, _) = update(
    confirmed,
    Panel(Reveal({ path: "src/Workbench/Main.elm", line: 3, column: 5, })),
    emit,
  )
  let (stale, _) = update(
    opened,
    Panel(Reveal({ path: "src/Gone.elm", line: 1, column: 1, })),
    emit,
  )
  @expect.expect_all(s => {
    s
    .expect(active_project(opened).active.to_string(), label="opened")
    .to_equal("src/Workbench/Main.elm")
    s.expect(opened.revision, label="revision").to_equal(confirmed.revision)
    s.expect(opened.reveal, label="reveal").to_equal("3:5:1")
    s.expect(stale.reveal, label="stale reveal").to_equal(opened.reveal)
    s
    .expect(active_project(stale).active.to_string(), label="stale kept")
    .to_equal("src/Workbench/Main.elm")
  })
}

///|
test "problem marks use display columns per path" {
  let reply : Json = {
    "frontendDiagnostics": [
      {
        "path": "src/A.mbt",
        "problems": [
          {
            "path": "src/A.mbt",
            "detail": "bad",
            "coordinateProfile": "moonbit-parser-position-v1",
            "source": {
              "startLine": 2,
              "startColumn": 4,
              "endLine": 2,
              "endColumn": 6,
            },
          },
        ],
      },
    ],
  }
  @expect.expect(
    problem_marks(reply).get("src/A.mbt").map(m => m.contains("\"column\":5")),
    label="marks",
  ).to_equal(Some(true))
}

///|
fn sample_reply() -> String {
  let sample : Json = {
    "version": 1,
    "id": "tiny",
    "title": "Tiny",
    "languageId": "elm",
    "notice": "Apache-2.0.",
    "project": {
      "version": 1,
      "name": "Tiny.Pkg",
      "languageId": "elm",
      "exposedModules": ["Main"],
      "files": [
        {
          "path": "src/Tiny/Pkg/Main.elm",
          "content": "module Tiny.Pkg.Main exposing (..)\n",
        },
      ],
      "active": "src/Tiny/Pkg/Main.elm",
    },
  }
  ({ "ok": true, "text": sample.stringify() } : Json).stringify()
}

///|
test "a sample replaces the Elm project and clears the earlier problems; a failed one keeps it" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "elm",
    problem_counts: Map([("src/Workbench/Main.elm", 1)]),
    reveal: "1:1:1",
    samples: [("tiny", "Tiny"), ("gone", "Gone"), ("bad", "Bad")],
  }
  let (asked, _) = update(model, Sample("tiny"), emit)
  let (opened, _) = update(
    asked,
    SampleLoaded(asked.sample_request, "tiny", sample_reply()),
    emit,
  )
  let (asked_gone, _) = update(opened, Sample("gone"), emit)
  let (failed, _) = update(
    asked_gone,
    SampleLoaded(
      asked_gone.sample_request,
      "gone",
      ({ "ok": false, "message": "HTTP 404" } : Json).stringify(),
    ),
    emit,
  )
  let (asked_bad, _) = update(opened, Sample("bad"), emit)
  let (garbled, _) = update(
    asked_bad,
    SampleLoaded(
      asked_bad.sample_request,
      "bad",
      ({ "ok": true, "text": "{}" } : Json).stringify(),
    ),
    emit,
  )
  let (listed, _) = update(
    model,
    SampleIndex(
      (
        {
          "ok": true,
          "text": "{\"version\":1,\"samples\":[{\"id\":\"tiny\",\"title\":\"Tiny\"}]}",
        } : Json).stringify(),
    ),
    emit,
  )
  @expect.expect_all(s => {
    s
    .expect(active_project(opened).name.to_string(), label="name")
    .to_equal("Tiny.Pkg")
    s
    .expect(
      active_project(opened).profile.map(p => p.to_string()),
      label="default profile",
    )
    .to_equal(Some("library"))
    s.expect(opened.problem_counts.length(), label="counts").to_equal(0)
    s.expect(opened.reveal, label="reveal").to_equal("")
    s
    .expect(active_project(failed), label="failed keeps")
    .to_equal(active_project(opened))
    s
    .expect(active_project(garbled), label="garbled keeps")
    .to_equal(active_project(opened))
    s.expect(listed.samples, label="index").to_equal([("tiny", "Tiny")])
  })
}

///|
test "an imported folder replaces the Elm project and reports every note" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let reply : Json = {
    "success": true,
    "project": {
      "name": "Morphir.Example.App",
      "languageId": "elm",
      "exposedModules": ["Rentals", "Missing"],
      "files": [
        {
          "path": "src/Morphir/Example/App/Rentals.elm",
          "content": "module Morphir.Example.App.Rentals exposing (..)\n",
        },
      ],
    },
    "warnings": ["Ignoring morphir.json dependencies"],
    "skipped": 2,
  }
  let (done, _) = update(model, FolderImported(0, 1, reply.stringify()), emit)
  let (bad_name, _) = update(
    done,
    FolderImported(
      0,
      0,
      (
        {
          "success": true,
          "project": {
            "name": "a b",
            "languageId": "elm",
            "files": [{ "path": "src/A.elm", "content": "" }],
          },
        } : Json).stringify(),
    ),
    emit,
  )
  let (refused, _) = update(
    done,
    FolderImported(
      0,
      0,
      (
        {
          "success": false,
          "message": "workbench.folder_without_morphir_json: none",
        } : Json).stringify(),
    ),
    emit,
  )
  let logs = done.panel.logs.map(l => l.message)
  @expect.expect_all(s => {
    s.expect(done.language, label="language").to_equal("elm")
    s
    .expect(active_project(done).name.to_string(), label="name")
    .to_equal("Morphir.Example.App")
    s
    .expect(
      active_project(done).exposed.map(m => m.to_string()),
      label="exposed",
    )
    .to_equal(["Rentals"])
    s
    .expect(
      logs.contains("Ignoring morphir.json dependencies"),
      label="warning",
    )
    .to_be_true()
    s
    .expect(
      logs.contains("morphir.json exposes Missing, which has no source file"),
      label="dropped",
    )
    .to_be_true()
    s
    .expect(
      logs.iter().any(m => m.contains("skipped 3 other files")),
      label="skipped",
    )
    .to_be_true()
    s
    .expect(active_project(bad_name), label="bad_name kept")
    .to_equal(active_project(done))
    s.expect(bad_name.status, label="bad_name message").to_contain("not valid")
    s
    .expect(refused.status, label="refused")
    .to_contain("folder_without_morphir_json")
    s
    .expect(active_project(refused), label="refused kept")
    .to_equal(active_project(done))
  })
}

///|
test "a sample reply for an earlier choice, or after an edit, does not replace the project" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "elm",
    samples: [("tiny", "Tiny"), ("other", "Other")],
  }
  let (first, _) = update(model, Sample("tiny"), emit)
  let (second, _) = update(first, Sample("other"), emit)
  let (late, _) = update(
    second,
    SampleLoaded(first.sample_request, "tiny", sample_reply()),
    emit,
  )
  let (edited, _) = update(
    first,
    Source("module Workbench.Main exposing (..)\n\nkept = 1"),
    emit,
  )
  let (after_edit, _) = update(
    edited,
    SampleLoaded(first.sample_request, "tiny", sample_reply()),
    emit,
  )
  let (moved, _) = update(
    first,
    Files(Open(literal_path("src/Workbench/Main.elm"))),
    emit,
  )
  let (after_open, _) = update(
    moved,
    SampleLoaded(first.sample_request, "tiny", sample_reply()),
    emit,
  )
  @expect.expect_all(s => {
    s
    .expect(second.sample_request, label="counted")
    .to_equal(first.sample_request + 1)
    s
    .expect(active_project(late), label="late reply dropped")
    .to_equal(active_project(second))
    s
    .expect(
      late.panel.logs.length() > second.panel.logs.length(),
      label="noted",
    )
    .to_be_true()
    s.expect(active_text(after_edit), label="edit kept").to_contain("kept = 1")
    s
    .expect(
      active_project(after_open).name.to_string(),
      label="opening a file is no edit",
    )
    .to_equal("Tiny.Pkg")
  })
}

///|
test "fresh MoonBit projects prefer the supported union while explicit profiles stay pinned" {
  let catalog = catalog_fixture()
  guard catalog is Object(fields) &&
    fields["frontends"] is Array(frontends) &&
    frontends[1] is Object(moonbit) &&
    moonbit["profiles"] is Array(profiles) else {
    fail("catalog fixture")
  }
  moonbit["profiles"] = Json::array(
    profiles +
    [{ "id": "moonbit-model-library-v1", "compileKind": "each-file" }],
  )
  let model = { ..scope_model(), catalog, }
  assert_eq(selected_profile(model, "moonbit"), "moonbit-model-library-v1")
  assert_true(
    default_project(model, "moonbit").active_file().content.contains(
      "choose_for",
    ),
  )
  assert_false(
    default_project(model, "moonbit").active_file().content.contains("precedes"),
  )
  moonbit["profiles"] = Json::array(
    profiles +
    [
      { "id": "moonbit-model-library-v1", "compileKind": "each-file" },
      { "id": "moonbit-model-library-v2", "compileKind": "each-file" },
    ],
  )
  assert_eq(selected_profile(model, "moonbit"), "moonbit-model-library-v2")
  assert_true(
    default_project(model, "moonbit").active_file().content.contains("precedes"),
  )
  moonbit["profiles"] = Json::array(
    profiles +
    [
      { "id": "moonbit-model-library-v2", "compileKind": "each-file" },
      { "id": "moonbit-model-library-2026-10-17", "compileKind": "each-file" },
    ],
  )
  assert_eq(
    selected_profile(model, "moonbit"),
    "moonbit-model-library-2026-10-17",
  )
  let example = default_project(model, "moonbit").active_file().content
  for
    feature in [
      "/// Build a greeting", "choose_earlier", "in_name_range", "should_welcome",
      "unicode_sample", "compare_names",
    ] {
    assert_true(example.contains(feature))
  }
  assert_eq(
    selected_profile(
      with_selection(model, "moonbit", "moonbit-model-library-v2"),
      "moonbit",
    ),
    "moonbit-model-library-v2",
  )
  assert_eq(
    selected_profile(
      with_selection(model, "moonbit", "moonbit-model-library-v1"),
      "moonbit",
    ),
    "moonbit-model-library-v1",
  )
  let pinned = with_selection(model, "moonbit", "moonbit-model-bool-library-v1")
  assert_eq(
    selected_profile(pinned, "moonbit"),
    "moonbit-model-bool-library-v1",
  )
  assert_eq(selected_profile({ ..model, connected: true, }, "moonbit"), "")
  assert_eq(
    selected_profile({ ..model, catalog: catalog_fixture(), }, "moonbit"),
    "moonbit-model-bool-v1",
  )
}
