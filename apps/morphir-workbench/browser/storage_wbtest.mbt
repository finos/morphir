///|
test "restore accepts a valid project and refuses corrupt ones with a note" {
  let model = { ..scope_model(), catalog: catalog_fixture(), }
  let good = active_project({ ..model, language: "elm", }).to_json().stringify()
  let (ok, none) = restored(model, "elm", good)
  let wrong_language = active_project({ ..model, language: "scheme", })
    .to_json()
    .stringify()
  let (mismatch, mismatch_note) = restored(model, "elm", wrong_language)
  @expect.expect_all(s => {
    s.expect(none, label="no note").to_equal("")
    s
    .expect(
      ok.language_projects.get("elm").map(p => p.name.to_string()),
      label="restored",
    )
    .to_equal(Some("Workbench"))
    s
    .expect(
      mismatch.language_projects.contains("elm"),
      label="mismatch kept default",
    )
    .to_be_false()
    s
    .expect(mismatch_note, label="mismatch note")
    .to_contain("Could not restore the saved elm project")
    for
      text in [
        "{", "{\"version\":2}", "{\"version\":1,\"name\":\"A\",\"languageId\":\"elm\",\"files\":[{\"path\":\"../a.elm\",\"content\":\"\"}],\"active\":\"../a.elm\"}",
      ] {
      let (kept, note) = restored(model, "elm", text)
      s
      .expect(note, label=text)
      .to_contain("Could not restore the saved elm project")
      s
      .expect(
        kept.language_projects.contains("elm"),
        label=text + " kept default",
      )
      .to_be_false()
    }
    let (empty, quiet) = restored(model, "elm", "")
    s.expect(quiet, label="nothing stored").to_equal("")
    s
    .expect(empty.language_projects.contains("elm"), label="nothing restored")
    .to_be_false()
  })
}

///|
/// Property: whatever text storage returns, restore never raises and either restores, notes, or finds nothing stored.
test "restore is total over any stored text" {
  @expect.for_all((chars : Array[Char]) => {
    let model = { ..scope_model(), catalog: catalog_fixture(), }
    let text = String::from_array(chars)
    let (after, note) = restored(model, "elm", text)
    @expect.expect(
      after.language_projects.contains("elm") || note != "" || text == "",
      label="restored, noted or empty",
    ).to_be_true()
  })
}

///|
test "a change saves once, for the current revision only, and a failed save shows Not saved" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define a 1)"), emit)
  let (stale, _) = update(edited, SaveProject(edited.revision - 1), emit)
  let (current, _) = update(edited, SaveProject(edited.revision), emit)
  @expect.expect_all(s => {
    s.expect(stale.storage_ok, label="stale save ignored").to_be_true()
    s
    .expect(current.storage_ok, label="outside a browser the save fails")
    .to_be_false()
  })
}

///|
test "reset asks first, then restores the default project" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define a 1)"), emit)
  let (asked, _) = update(edited, RunCommand(ResetProject), emit)
  let (kept, _) = update(asked, CancelReset, emit)
  let (done, _) = update(asked, ConfirmReset, emit)
  @expect.expect_all(s => {
    s.expect(asked.reset_asking, label="asking").to_be_true()
    s.expect(active_text(asked), label="not yet").to_equal("(define a 1)")
    s.expect(kept.reset_asking, label="kept closes").to_be_false()
    s.expect(active_text(kept), label="kept text").to_equal("(define a 1)")
    s.expect(done.reset_asking, label="done closes").to_be_false()
    s
    .expect(active_text(done), label="default")
    .to_contain("(define (price quantity)")
  })
}

///|
test "a language switch inside the debounce window still saves the earlier edit" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define a 1)"), emit)
  let (switched, _) = update(edited, Language("moonbit"), emit)
  let (typed, _) = update(switched, Source("pub fn x() -> Bool { true }"), emit)
  let (first, _) = update(typed, SaveProject(edited.revision), emit)
  let (second, _) = update(typed, SaveProject(typed.revision), emit)
  @expect.expect_all(s => {
    s.expect(typed.dirty, label="both dirty").to_equal(["scheme", "moonbit"])
    s
    .expect(first.save_attempts, label="stale save writes nothing")
    .to_equal([])
    s
    .expect(second.save_attempts, label="current save writes both")
    .to_equal([legacy_key("scheme"), legacy_key("moonbit")])
    s
    .expect(second.dirty, label="failed writes stay dirty")
    .to_equal(["scheme", "moonbit"])
    s.expect(second.storage_ok, label="not saved").to_be_false()
  })
}

///|
test "a language change closes the reset question" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (asked, _) = update(model, RunCommand(ResetProject), emit)
  let (switched, _) = update(asked, Language("elm"), emit)
  @expect.expect(switched.reset_asking, label="closed").to_be_false()
}

///|
test "a save scheduled for an unedited language still writes the dirty one" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define a 1)"), emit)
  let (switched, _) = update(edited, Language("elm"), emit)
  let (saved, _) = update(switched, SaveProject(switched.revision), emit)
  @expect.expect_all(s => {
    s
    .expect(saved.save_attempts, label="scheme attempted")
    .to_equal([legacy_key("scheme")])
  })
}

///|
test "moving the active file marks the language dirty without a revision change" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = { ..scope_model(), catalog: catalog_fixture(), language: "elm", }
  let (added, _) = update(model, Files(StartAdd(Some(Root))), emit)
  let (drafted, _) = update(
    added,
    Files(Draft("src/Workbench/Extra.elm")),
    emit,
  )
  let (confirmed, _) = update(drafted, Files(Commit), emit)
  let clean = { ..confirmed, dirty: [], }
  let (opened, _) = update(
    clean,
    Files(Open(literal_path("src/Workbench/Main.elm"))),
    emit,
  )
  @expect.expect_all(s => {
    s.expect(opened.revision, label="revision").to_equal(clean.revision)
    s.expect(opened.dirty, label="dirty").to_equal(["elm"])
  })
}

///|
fn stored_moonbit_library(model : Model) -> String {
  let library = with_selection(model, "moonbit", "moonbit-model-stable-v1")
  default_project(library, "moonbit").to_json().stringify()
}

///|
test "a restored profile survives the first visit to its language and is saved" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let stored = stored_moonbit_library(model)
  let loaded = restore_all_with(model, key => {
    if key == legacy_key("moonbit") {
      stored
    } else {
      ""
    }
  })
  let (visited, _) = update(loaded, Language("moonbit"), emit)
  let (edited, _) = update(visited, Source("pub fn x() -> Bool { true }"), emit)
  @expect.expect_all(s => {
    s
    .expect(
      active_project(visited).profile.map(p => p.to_string()),
      label="project profile",
    )
    .to_equal(Some("moonbit-model-stable-v1"))
    s
    .expect(visited.source_profile, label="selector")
    .to_equal("moonbit-model-stable-v1")
    s
    .expect(active_project(edited).to_json().stringify(), label="saved text")
    .to_contain("moonbit-model-stable-v1")
  })
}

///|
test "a restored profile the catalog does not list is dropped with a note" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let stored = stored_moonbit_library(model).replace_all(
    old="moonbit-model-stable-v1",
    new="gone-profile-v1",
  )
  let loaded = restore_all_with(model, key => {
    if key == legacy_key("moonbit") {
      stored
    } else {
      ""
    }
  })
  let (visited, _) = update(loaded, Language("moonbit"), emit)
  @expect.expect_all(s => {
    s
    .expect(
      loaded.panel.logs
      .map(l => l.message)
      .iter()
      .any(m => m.contains("no longer available")),
      label="note",
    )
    .to_be_true()
    s
    .expect(
      active_project(visited).profile.map(p => p.to_string()),
      label="default profile",
    )
    .to_equal(Some("moonbit-model-stable-v1"))
  })
}

///|
test "restore_all skips connected sessions and invalid languages" {
  let stored = stored_moonbit_library({
    ..scope_model(),
    catalog: catalog_fixture(),
  })
  let connected = restore_all_with(
    { ..scope_model(), catalog: catalog_fixture(), connected: true, },
    _ => stored,
  )
  let invalid = restore_all_with(
    { ..scope_model(), catalog: hostile_catalog(), },
    key => if key == legacy_key("Bad Language") { stored } else { "" },
  )
  @expect.expect_all(s => {
    s
    .expect(connected.language_projects.length(), label="connected")
    .to_equal(0)
    s
    .expect(invalid.language_projects.length(), label="invalid language")
    .to_equal(0)
  })
}

///|
test "reset removes the stored key of its language" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (asked, _) = update(model, RunCommand(ResetProject), emit)
  let (done, _) = update(asked, ConfirmReset, emit)
  @expect.expect(done.removed_key, label="removed").to_equal(
    legacy_key("scheme"),
  )
}

///|
test "a folder picked while another execution runs is refused; a stale import reply is ignored" {
  let emit = @cmd.Emit(fn(_) { @cmd.none })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    busy: true,
    request_id: 4,
  }
  let picked = ({ "ok": true, "files": [], "skipped": 0 } : Json).stringify()
  let (refused, _) = update(model, FolderPicked(picked), emit)
  let idle = { ..model, busy: false, }
  let (started, _) = update(idle, FolderPicked(picked), emit)
  let (stale, _) = update(started, FolderImported(3, 0, "{}"), emit)
  let (current, _) = update(
    started,
    FolderImported(started.request_id, 0, "{}"),
    emit,
  )
  @expect.expect_all(s => {
    s.expect(refused.busy, label="busy kept").to_be_true()
    s.expect(refused.request_id, label="execution kept").to_equal(4)
    s
    .expect(
      refused.panel.logs.length() > model.panel.logs.length(),
      label="noted",
    )
    .to_be_true()
    s.expect(started.busy, label="started busy").to_be_true()
    s.expect(started.request_id, label="execution").to_equal(5)
    s.expect(stale.busy, label="stale ignored").to_be_true()
    s.expect(current.busy, label="current clears busy").to_be_false()
  })
}

///|
test "a reset inside another language's debounce still schedules that language's save" {
  let sent : Array[Msg] = []
  let record = @cmd.Emit(fn(msg) {
    sent.push(msg)
    @cmd.none
  })
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(model, Source("(define kept 1)"), record)
  let (elm, _) = update(edited, Language("elm"), record)
  let (asked, _) = update(elm, RunCommand(ResetProject), record)
  sent.clear()
  let (reset, _) = update(asked, ConfirmReset, record)
  let scheduled = sent.filter_map(msg => {
    // Work that a workspace schedules comes back routed to that workspace.
    match msg {
      SaveProject(revision) | Routed(_, SaveProject(revision)) => Some(revision)
      _ => None
    }
  })
  let (saved, _) = update(reset, SaveProject(reset.revision), record)
  @expect.expect_all(s => {
    s.expect(reset.dirty, label="scheme still dirty").to_equal(["scheme"])
    s
    .expect(scheduled, label="save for the new revision")
    .to_equal([reset.revision])
    s
    .expect(saved.save_attempts, label="scheme written")
    .to_contain_element(legacy_key("scheme"))
    s
    .expect(saved.save_attempts, label="reset language not written back")
    .to_contain_none_of([legacy_key("elm")])
  })
}

///|
/// The key a source project of `language` had before workspaces; the test workspace keeps it.
fn legacy_key(language : String) -> String {
  "morphir-workbench.project." + language + ".v1"
}
