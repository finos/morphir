///|
fn multiple_projects() -> Model {
  let files = known(() => {
    @workspace_files.Files::new(
      Map([
        (
          "morphir.toml", "# Keep\n[workspace]\nmembers=['packages/*']\n[frontend]\nlanguage='scheme'\n[pipeline]\nbackend='scheme'\n",
        ),
        ("packages/one/morphir.toml", "# One\n[project]\nname='One'\n"),
        ("packages/one/src/main.scm", "11"),
        ("packages/two/morphir.toml", "[project]\nname='Two'\n"),
        ("packages/two/src/main.scm", "22"),
      ]),
    )
  })
  with_workspace_files({ ..source_model("scheme"), available: true, }, files)
}

///|
test "idea presets create a root project and retain their ordinary files" {
  let idea = run_all(starting_model(), [TryIdea(Intent), IntentText("Orders")])
  assert_eq(discovered_projects(idea).length(), 1)
  assert_eq(
    current_project_path(idea),
    known(() => @discovery.ProjectPath::parse(".")),
  )
  assert_eq(idea.workspace_files.read("intent.md"), Some("Orders"))
  let added = run_all(idea, [
    AddContent(ConceptualModel),
    ConceptText("concept"),
    AddContent(Worksheet),
    Source("(+ 1 2)"),
  ])
  assert_eq(discovered_projects(added).length(), 1)
  let restored = with_workspace_files(starting_model(), added.workspace_files)
  assert_eq(restored.intent, "Orders")
  assert_eq(restored.concept, "concept")
  assert_eq(restored.worksheet_source, "(+ 1 2)")
  assert_eq(idea.doc, IntentDraft)
  assert_eq(first_document(idea), IntentDraft)
  assert_eq(idea.workspace_files.opened(), Some("intent.md"))
  let conceptual = run_all(starting_model(), [TryIdea(ConceptualModel)])
  assert_eq(discovered_projects(conceptual).length(), 1)
  assert_eq(conceptual.workspace_files.read("intent.md"), Some(""))
  assert_eq(conceptual.workspace_files.read("src/model.mfs"), Some(""))
  assert_eq(conceptual.doc, ConceptDraft)
  assert_eq(first_document(conceptual), ConceptDraft)
}

///|
test "opening projectless drafts does not synthesize a source project" {
  let files = known(() => {
    @workspace_files.migrate(
      [],
      "scheme",
      intent=Some("Orders"),
      concept=Some("concept"),
      worksheet=Some("(+ 1 2)"),
    )
  })
  let empty = run_all(starting_model(), [StartPreset(Empty), CreateWorkspace])
  let restored = with_workspace_files(empty, files)
  assert_eq(discovered_projects(restored).length(), 0)
  assert_eq(restored.intent, "Orders")
  assert_eq(restored.concept, "concept")
  assert_eq(restored.worksheet_source, "(+ 1 2)")
}

///|
test "same-project source selection carries that unit's inspection and typed source" {
  let model = source_model("moonbit")
  let files = known(() => {
    model.workspace_files
    .configure(
      @discovery.ProjectPath::parse("."),
      @workspace_files.Provider,
      None,
    )
    .write("src/second.mbt", "pub fn second() -> Int { 7 }")
  })
  let before = with_workspace_files(model, files)
  let reply = @pipeline.execute(compile_request(before, "compile"))
  @expect.expect(reply).to_contain_json({ "success": true })
  let compiled = run_all({ ..before, request_id: 8, busy: true, }, [
    Receive(8, before.revision, "compile-workspace", reply.stringify()),
  ])
  let first = compiled.document.inspection()
  let second = run_all(compiled, [OpenWorkspaceFile("src/second.mbt")])
  let inspected = second.document.inspection()
  assert_true(text(inspected, "sourceUnitIon") != "")
  assert_true(text(inspected, "sourceUnitIon") != text(first, "sourceUnitIon"))
  assert_true(inspected.stringify().contains("second"))
  assert_eq(text(second.output, "source"), "src/second.mbt")
  assert_eq(field(second.output, "ir"), field(inspected, "ir"))
  let selected = project_model_result(
    second,
    field(items(field(second.output, "workspaceProjects"))[0], "result"),
  )
  assert_eq(text(inspected, "sourceUnitIon"), text(selected, "sourceUnitIon"))
}

///|
test "workspace generation refusal retains the compiled model for inspection" {
  let model = source_model("elm")
  let files = known(() => {
    let path = @discovery.ProjectPath::parse(".")
    model.workspace_files
    .configure(path, @workspace_files.Provider, None)
    .configure(path, @workspace_files.Generation, Some("moonbit"))
    .write(
      "src/Workbench/Main.elm", "module Workbench.Main exposing (answer, readX)\n\nanswer = 42\n\nreadX : { a | x : Int } -> Int\nreadX r = r.x\n",
    )
    .open("src/Workbench/Main.elm")
  })
  let before = with_workspace_files(model, files)
  let reply = @pipeline.execute(compile_request(before, "compile"))
  @expect.expect(reply).to_contain_json({ "success": false })
  let received = run_all({ ..before, request_id: 9, busy: true, }, [
    Receive(9, before.revision, "compile-workspace", reply.stringify()),
  ])
  assert_true(field(received.document.inspection(), "ir") != Json::null())
  assert_true(received.document.inspection().stringify().contains("readX"))
  assert_true(received.status.contains("MoonBit generation failed"))
}

///|
test "opening a project selects its compiled model and invalidates an earlier revision" {
  let before = run_all(multiple_projects(), [
    OpenWorkspaceFile("packages/one/src/main.scm"),
  ])
  let reply = @pipeline.execute(compile_request(before, "compile"))
  let compiled = run_all({ ..before, request_id: 8, busy: true, }, [
    Receive(8, before.revision, "compile-workspace", reply.stringify()),
  ])
  assert_eq(text(compiled.document.inspection(), "package"), "one")
  let two = run_all(compiled, [OpenWorkspaceFile("packages/two/src/main.scm")])
  assert_eq(text(two.document.inspection(), "package"), "two")
  let edited = run_all(two, [
    Source("33"),
    OpenWorkspaceFile("packages/one/src/main.scm"),
  ])
  assert_eq(edited.document.inspection(), Json::null())
}

///|
test "a default member result never becomes the model of a different current project" {
  let files = known(() => {
    multiple_projects().workspace_files
    .configure_workspace(@workspace_files.DefaultMember, Some("packages/one"))
    .open("packages/two/src/main.scm")
  })
  let before = with_workspace_files(multiple_projects(), files)
  let reply = @pipeline.execute(compile_request(before, "compile"))
  let received = run_all({ ..before, request_id: 9, busy: true, }, [
    Receive(9, before.revision, "compile-workspace", reply.stringify()),
  ])
  assert_eq(received.document.inspection(), Json::null())
  assert_eq(current_project_path(received).to_string(), "packages/two")
  let selected = run_all(received, [
    OpenWorkspaceFile("packages/one/src/main.scm"),
  ])
  assert_eq(text(selected.document.inspection(), "package"), "one")
}

///|
test "add and remove use shared scaffolding and allow two projects of the same language" {
  let before = multiple_projects()
  let added = run_all(before, [
    AddWorkspaceProject,
    EditNewProject(Name, "Three"),
    EditNewProject(Folder, "packages/three"),
    CreateWorkspaceProject,
  ])
  assert_eq(discovered_projects(added).length(), 3)
  assert_eq(current_project_path(added).to_string(), "packages/three")
  assert_eq(
    added.workspace_files.read("morphir.toml"),
    before.workspace_files.read("morphir.toml"),
  )
  let path = known(() => @discovery.ProjectPath::parse("packages/three"))
  let removed = run_all(added, [AskRemoveProject(path), RemoveWorkspaceProject])
  assert_eq(discovered_projects(removed).length(), 2)
  assert_true(
    removed.workspace_files.read("packages/three/src/main.scm") is Some(_),
  )
  let deleted = run_all(added, [
    AskRemoveProject(path),
    DeleteProjectFiles(true),
    RemoveWorkspaceProject,
  ])
  assert_eq(deleted.workspace_files.read("packages/three/src/main.scm"), None)
}

///|
test "file commands preserve bytes and refuse outside paths and collisions" {
  let model = multiple_projects()
  let created = run_all(model, [
    AskWorkspaceFile(Create, ""),
    WorkspaceFilePath("notes.md"),
    CommitWorkspaceFile,
    Source("Keep λ😀\n"),
  ])
  let invalid = run_all(created, [
    AskWorkspaceFile(Rename, "notes.md"),
    WorkspaceFilePath("../escape"),
    CommitWorkspaceFile,
  ])
  assert_eq(invalid.workspace_files, created.workspace_files)
  let collision = run_all(created, [
    AskWorkspaceFile(Rename, "notes.md"),
    WorkspaceFilePath("morphir.toml"),
    CommitWorkspaceFile,
  ])
  assert_eq(collision.workspace_files, created.workspace_files)
  let moved = run_all(created, [
    AskWorkspaceFile(Rename, "notes.md"),
    WorkspaceFilePath("docs/notes.md"),
    CommitWorkspaceFile,
  ])
  assert_eq(moved.workspace_files.read("notes.md"), None)
  assert_eq(moved.workspace_files.read("docs/notes.md"), Some("Keep λ😀\n"))
  let removed = run_all(moved, [
    AskWorkspaceFile(Delete, "docs/notes.md"),
    CommitWorkspaceFile,
  ])
  assert_eq(removed.workspace_files.read("docs/notes.md"), None)
}

///|
test "project settings edit the selected manifest and leave inherited settings intact" {
  let model = multiple_projects()
  let path = known(() => @discovery.ProjectPath::parse("packages/one"))
  let changed = run_all(model, [
    ProjectSetting("packages/one", @workspace_files.Generation, "elm"),
  ])
  assert_eq(
    changed.workspace_files.setting(path, @workspace_files.Generation).effective,
    Some("elm"),
  )
  assert_true(
    changed.workspace_files
    .read("packages/one/morphir.toml")
    .unwrap()
    .has_prefix("# One\n[project]\nname='One'\n"),
  )
  let inherited = run_all(changed, [
    ProjectSetting("packages/one", @workspace_files.Generation, ""),
  ])
  assert_eq(
    inherited.workspace_files.setting(path, @workspace_files.Generation).effective,
    Some("scheme"),
  )
  assert_eq(
    inherited.workspace_files.setting(path, @workspace_files.Generation).override_value,
    None,
  )
  assert_eq(
    inherited.workspace_files.read("morphir.toml"),
    model.workspace_files.read("morphir.toml"),
  )
}

///|
test "a read-only location refuses edits even when a message bypasses disabled controls" {
  let model = { ..multiple_projects(), connected: true, project_dialog: None, }
  for
    message in [
      Source("overwrite"),
      AddWorkspaceProject,
      AskWorkspaceFile(Create, ""),
      ProjectSetting("packages/one", @workspace_files.Generation, "elm"),
    ] {
    let after = run_all(model, [message])
    assert_eq(after.workspace_files, model.workspace_files)
    assert_true(after.project_dialog is None)
  }
}

///|
test "file saves commit a complete generation and collect only obsolete workspace records" {
  let restore = storage_test_environment("")
  defer restore()
  let model = multiple_projects()
  let first = write_projects(model)
  assert_true(first.storage_ok)
  ignore(storage_save("unrelated.files.keep", "keep"))
  let pending_key = workspace_prefix(model) + ".files.another-tab.0"
  ignore(storage_save(pending_key, "uncommitted record from another tab"))
  let edited = run_all(first, [
    OpenWorkspaceFile("packages/one/src/main.scm"),
    Source("33"),
  ])
  let written = write_projects(edited)
  assert_true(written.storage_ok)
  assert_eq(
    stored_keys(workspace_prefix(written) + ".files.").length(),
    written.workspace_files.paths().length() + 1,
  )
  assert_eq(storage_load(pending_key), "uncommitted record from another tab")
  let loaded = restore_all(written)
  assert_eq(loaded.workspace_files, written.workspace_files)
  assert_eq(storage_load("unrelated.files.keep"), "keep")
}

///|
test "ordinary drafts are files of their project or workspace" {
  let model = run_all(multiple_projects(), [
    OpenWorkspaceFile("packages/two/src/main.scm"),
    AddContent(Intent),
    IntentText("Price orders"),
    AddContent(ConceptualModel),
    ConceptText("concept"),
    AddContent(Worksheet),
    Source("(+ 1 2)"),
  ])
  assert_eq(
    model.workspace_files.read("packages/two/intent.md"),
    Some("Price orders"),
  )
  assert_eq(
    model.workspace_files.read("packages/two/src/model.mfs"),
    Some("concept"),
  )
  assert_eq(model.workspace_files.read("worksheet.scm"), Some("(+ 1 2)"))
}

///|
test "quick open lists every workspace file and selects a same-language project" {
  let model = multiple_projects()
  let opened = run_all(model, [
    RunCommand(GoToFile),
    Palette(Query("two/src/main")),
    Palette(Key(@keys.Chord::plain("Enter"))),
  ])
  assert_eq(opened.workspace_files.opened(), Some("packages/two/src/main.scm"))
  assert_eq(current_project_path(opened).to_string(), "packages/two")
}

///|
test "reset keeps project identity settings and a custom source directory" {
  let model = run_all(multiple_projects(), [
    ProjectSetting("packages/one", @workspace_files.SourceDirectory, "lib"),
    OpenWorkspaceFile("packages/one/morphir.toml"),
  ])
  let reset = run_all(model, [ConfirmReset])
  assert_eq(reset.workspace_files.discover().projects[0].name, "One")
  assert_true(
    reset.workspace_files.paths().any(p => p.has_prefix("packages/one/lib/")),
  )
  assert_eq(reset.workspace_files.read("packages/two/src/main.scm"), Some("22"))
  assert_eq(reset.workspace_files.read("packages/one/src/main.scm"), Some("11"))
  let path = known(() => @discovery.ProjectPath::parse("packages/one"))
  assert_eq(
    reset.workspace_files.setting(path, @workspace_files.SourceDirectory).effective,
    Some("lib"),
  )
}

///|
test "imported model bytes become files and a colliding name retains both originals" {
  let before = multiple_projects()
  let received = send(before, [
    Receive(
      before.request_id,
      before.revision,
      "inspect",
      (
        {
          "success": true,
          "ir": { "formatVersion": 4 },
          "sourceFormatVersion": "4.0.0",
          "sourceUnitIon": "unit",
          "modelSource": {
            "kind": "original-file",
            "filename": "model.ionb",
            "codec": "ion-binary",
            "formatVersion": "4.0.0",
            "contentBase64": "AP/DRQo=",
          },
        } : Json).stringify(),
    ),
  ])
  assert_eq(
    file_bytes(received.workspace_files, "models/model.ionb"),
    Some(b"\x00\xff\xc3E\n"),
  )
  let (opening, attempt) = match received.document.begin(Idle) {
    Started(doc, attempt) => (doc, attempt)
    _ => abort("begin")
  }
  let next = send({ ..received, document: opening, }, [
    ReceiveModel(
      attempt,
      received.request_id,
      received.revision,
      "inspect",
      (
        {
          "success": true,
          "ir": { "formatVersion": 4 },
          "sourceFormatVersion": "4.0.0",
          "sourceUnitIon": "unit",
          "modelSource": {
            "kind": "original-file",
            "filename": "model.ionb",
            "codec": "ion-binary",
            "formatVersion": "4.0.0",
            "contentBase64": "AQID",
          },
        } : Json).stringify(),
    ),
  ])
  assert_eq(
    file_bytes(next.workspace_files, "models/model.ionb"),
    Some(b"\x00\xff\xc3E\n"),
  )
  assert_eq(
    file_bytes(next.workspace_files, "models/import-2/model.ionb"),
    Some(b"\x01\x02\x03"),
  )
  assert_eq(
    stored_models(next.workspace_files).files.get("models/import-2/model.ionb"),
    Some(@document.SourceCodec::IonBinary),
  )
  let renamed = send(next, [
    AskWorkspaceFile(Rename, "models/import-2/model.ionb"),
    WorkspaceFilePath("models/renamed.data"),
    CommitWorkspaceFile,
  ])
  assert_eq(
    file_bytes(renamed.workspace_files, "models/renamed.data"),
    Some(b"\x01\x02\x03"),
  )
  assert_eq(
    stored_models(renamed.workspace_files).files.get("models/renamed.data"),
    Some(@document.SourceCodec::IonBinary),
  )
  let refused = send(renamed, [Source("overwrite")])
  assert_eq(refused.workspace_files, renamed.workspace_files)
  let reopened = send({ ..renamed, document: @document.State::new(), }, [
    OpenWorkspaceFile("models/renamed.data"),
  ])
  assert_true(reopened.busy)
  assert_true(reopened.document.opening() is Some(_))
}

///|
test "intent and conceptual files open their project documents" {
  let model = send(multiple_projects(), [
    OpenWorkspaceFile("packages/two/src/main.scm"),
    AddContent(Intent),
    IntentText("Orders"),
    AddContent(ConceptualModel),
    ConceptText("model"),
  ])
  let intent = send(model, [OpenWorkspaceFile("packages/two/intent.md")])
  assert_eq(intent.doc, IntentDraft)
  assert_eq(intent.intent, "Orders")
  let concept = send(intent, [OpenWorkspaceFile("packages/two/src/model.mfs")])
  assert_eq(concept.doc, ConceptDraft)
  assert_eq(concept.concept, "model")
}

///|
test "a refused model capture retains previous files and model and retires the pending open" {
  let before = with_workspace_files(
    lifecycle_model(),
    known(() => {
      @workspace_files.Files::new(
        Map([
          ("morphir.toml", "[workspace]\nmembers=[]\n"),
          (model_index_path, "not JSON"),
        ]),
      )
    }),
  )
  let (document, attempt) = match before.document.begin(Idle) {
    Started(doc, attempt) => (doc, attempt)
    _ => abort("begin")
  }
  let received = send({ ..before, document, }, [
    ReceiveModel(
      attempt,
      before.request_id,
      before.revision,
      "inspect",
      (
        {
          "success": true,
          "ir": { "formatVersion": 4 },
          "sourceFormatVersion": "4.0.0",
          "sourceUnitIon": "unit",
          "modelSource": {
            "kind": "original-file",
            "filename": "new.ionb",
            "codec": "ion-binary",
            "formatVersion": "4.0.0",
            "contentBase64": "AQID",
          },
        } : Json).stringify(),
    ),
  ])
  assert_eq(received.workspace_files, before.workspace_files)
  assert_eq(received.document.original(), before.document.original())
  assert_true(received.document.opening() is None)
  assert_false(received.busy)
  assert_true(received.status.contains("could not be added"))
}

///|
test "deleting the current original model closes its owned views and removes its content kind" {
  let files = known(() => {
    @workspace_files.Files::new(
      Map([("morphir.toml", "[workspace]\nmembers=[]\n")]),
    ).write_content("models/first.json", @data.Binary(b"\x01\x02\x03"))
  })
  let index = StoredModels::{
    files: Map([("models/first.json", @document.SourceCodec::MorphirJson)]),
    trees: [],
  }
  let model = with_workspace_files(
    lifecycle_model(),
    known(() => index.save(files).open("models/first.json")),
  )
  let removed = send(model, [
    AskWorkspaceFile(Delete, "models/first.json"),
    CommitWorkspaceFile,
  ])
  assert_true(removed.document.original() is None)
  assert_false(held(removed).contains(ModelDocument))
  assert_eq(removed.workspace_files.content("models/first.json"), None)
}
