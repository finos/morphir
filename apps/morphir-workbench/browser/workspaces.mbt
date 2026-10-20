// Workbench workspaces in the page: the active workspace's state lives in the Model, the others' in `parked`.
// Opening, creating and switching park one slice and restore another; nothing is cancelled or discarded. Work that a
// workspace starts reports back through `Routed`, so a late reply changes the workspace that asked for it. Closing
// saves a workspace and drops its state from the page; a reply for the closed opening is ignored.

///|
enum Screen {
  GettingStarted
  Workspace
} derive(Eq)

///|
/// What a provisional workspace waits for.
enum Acquire {
  /// A model file, or a YAML tree when true.
  ModelFile(Bool)
  /// A source folder imported into the browser.
  SourceFolder
  /// A folder opened with the desktop host's read-only grant.
  HostFolder
} derive(Eq)

///|
/// A provisional workspace and the workspace that was active before it, which returns if the acquisition fails.
struct Acquisition {
  workspace : @workspace.WorkspaceId
  kind : Acquire
  previous : @workspace.WorkspaceId?
} derive(Eq)

///|
/// The getting-started choice the person opened.
enum StartPanel {
  Closed
  Idea
  OpenChoices
  CreateChoices
  ExploreChoices
} derive(Eq)

///|
/// The getting-started page's own state: the open choice, the create form, a pending removal and the result of the
/// last entry that did not open.
struct Start {
  panel : StartPanel
  name : String
  preset : @workspace.Preset
  name_error : String
  removing : @workspace.WorkspaceId?
  message : String
} derive(Eq)

///|
/// The generation completion notification. It shows how many files arrived and never takes the focus.
struct Notice {
  files : Int32
  target : String
} derive(Eq)

///|
/// One opening of a workspace in this page. Work started in it reports back to this opening; after the workspace
/// closes, a reply for it is ignored, also when the workspace opens again.
struct Visit {
  workspace : @workspace.WorkspaceId
  opening : Int32
} derive(Eq, Debug)

///|
/// One workspace's state while another is active: the same fields as the workspace part of `Model`.
struct Slice {
  opening : Int32
  history : Array[Location]
  doc : @workspace.Document
  layout : @shell.Layout
  intent : String
  concept : String
  draft_revision : Int32
  notice : Notice?
  worksheet : Bool
  language_projects : Map[String, @project.Project]
  worksheet_source : String
  files_edit : @project_files.State
  problem_counts : Map[String, Int32]
  problem_marks : Map[String, String]
  sample_request : Int32
  sample_base : @project.Project?
  storage_ok : Bool
  dirty : Array[String]
  removed_key : String
  save_attempts : Array[String]
  reset_asking : Bool
  reveal : String
  reveal_nonce : Int32
  source_profile : String
  model_format : @data.ModelFormat?
  profile_choices : Map[String, String]
  explorer_raw : Bool
  collapsed_modules : Array[String]
  query : String
  selected : String
  evaluation_runtime : @evaluation.Runtime
  evaluation_policy : @capabilities.CapabilityPolicy
  evaluation_host_execution : Bool
  evaluation_mode : @evaluation.InputMode
  result_mode : @result.Mode
  evaluation_arguments : String
  evaluation_result : Json
  evaluation_terminal : @outcomes.Projection
  evaluation_revision : Int32
  evaluation_result_revision : Int32
  evaluation_entry : String
  host_draft : EvaluationDraft?
  model_revision : Int32
  output : Json
  worksheet_capture : @worksheet.WorksheetRequest?
  worksheet_report : @worksheet.WorksheetReport?
  worksheet_reveal : String
  document : @document.State
  generated : Bool
  generated_state : @generated.State
  revision : Int32
  worksheet_revision : Int32
  output_revision : Int32
  host_execution : Json
  host_execution_revision : Int32
  host_submitting : Bool
  submission_unknown : Bool
  language : String
  target : String
  projects : Array[Json]
  panel : @bottom_panel.State
} derive(Eq)

///|
fn park(m : Model) -> Slice {
  {
    opening: m.opening,
    history: m.history,
    doc: m.doc,
    layout: m.layout,
    intent: m.intent,
    concept: m.concept,
    draft_revision: m.draft_revision,
    notice: m.notice,
    worksheet: m.worksheet,
    language_projects: m.language_projects,
    worksheet_source: m.worksheet_source,
    files_edit: m.files_edit,
    problem_counts: m.problem_counts,
    problem_marks: m.problem_marks,
    sample_request: m.sample_request,
    sample_base: m.sample_base,
    storage_ok: m.storage_ok,
    dirty: m.dirty,
    removed_key: m.removed_key,
    save_attempts: m.save_attempts,
    reset_asking: m.reset_asking,
    reveal: m.reveal,
    reveal_nonce: m.reveal_nonce,
    source_profile: m.source_profile,
    model_format: m.model_format,
    profile_choices: m.profile_choices,
    explorer_raw: m.explorer_raw,
    collapsed_modules: m.collapsed_modules,
    query: m.query,
    selected: m.selected,
    evaluation_runtime: m.evaluation_runtime,
    evaluation_policy: m.evaluation_policy,
    evaluation_host_execution: m.evaluation_host_execution,
    evaluation_mode: m.evaluation_mode,
    result_mode: m.result_mode,
    evaluation_arguments: m.evaluation_arguments,
    evaluation_result: m.evaluation_result,
    evaluation_terminal: m.evaluation_terminal,
    evaluation_revision: m.evaluation_revision,
    evaluation_result_revision: m.evaluation_result_revision,
    evaluation_entry: m.evaluation_entry,
    host_draft: m.host_draft,
    model_revision: m.model_revision,
    output: m.output,
    worksheet_capture: m.worksheet_capture,
    worksheet_report: m.worksheet_report,
    worksheet_reveal: m.worksheet_reveal,
    document: m.document,
    generated: m.generated,
    generated_state: m.generated_state,
    revision: m.revision,
    worksheet_revision: m.worksheet_revision,
    output_revision: m.output_revision,
    host_execution: m.host_execution,
    host_execution_revision: m.host_execution_revision,
    host_submitting: m.host_submitting,
    submission_unknown: m.submission_unknown,
    language: m.language,
    target: m.target,
    projects: m.projects,
    panel: m.panel,
  }
}

///|
fn unpark(m : Model, s : Slice) -> Model {
  {
    ..m,
    opening: s.opening,
    history: s.history,
    doc: s.doc,
    layout: s.layout,
    intent: s.intent,
    concept: s.concept,
    draft_revision: s.draft_revision,
    notice: s.notice,
    worksheet: s.worksheet,
    language_projects: s.language_projects,
    worksheet_source: s.worksheet_source,
    files_edit: s.files_edit,
    problem_counts: s.problem_counts,
    problem_marks: s.problem_marks,
    sample_request: s.sample_request,
    sample_base: s.sample_base,
    storage_ok: s.storage_ok,
    dirty: s.dirty,
    removed_key: s.removed_key,
    save_attempts: s.save_attempts,
    reset_asking: s.reset_asking,
    reveal: s.reveal,
    reveal_nonce: s.reveal_nonce,
    source_profile: s.source_profile,
    model_format: s.model_format,
    profile_choices: s.profile_choices,
    explorer_raw: s.explorer_raw,
    collapsed_modules: s.collapsed_modules,
    query: s.query,
    selected: s.selected,
    evaluation_runtime: s.evaluation_runtime,
    evaluation_policy: s.evaluation_policy,
    evaluation_host_execution: s.evaluation_host_execution,
    evaluation_mode: s.evaluation_mode,
    result_mode: s.result_mode,
    evaluation_arguments: s.evaluation_arguments,
    evaluation_result: s.evaluation_result,
    evaluation_terminal: s.evaluation_terminal,
    evaluation_revision: s.evaluation_revision,
    evaluation_result_revision: s.evaluation_result_revision,
    evaluation_entry: s.evaluation_entry,
    host_draft: s.host_draft,
    model_revision: s.model_revision,
    output: s.output,
    worksheet_capture: s.worksheet_capture,
    worksheet_report: s.worksheet_report,
    worksheet_reveal: s.worksheet_reveal,
    document: s.document,
    generated: s.generated,
    generated_state: s.generated_state,
    revision: s.revision,
    worksheet_revision: s.worksheet_revision,
    output_revision: s.output_revision,
    host_execution: s.host_execution,
    host_execution_revision: s.host_execution_revision,
    host_submitting: s.host_submitting,
    submission_unknown: s.submission_unknown,
    language: s.language,
    target: s.target,
    projects: s.projects,
    panel: s.panel,
  }
}

///|
/// The language a new workspace starts with: Scheme when the catalog has it, else its first valid language.
fn default_language(catalog : Json) -> String {
  let ids = items(field(catalog, "frontends"))
    .map(f => text(f, "languageId"))
    .filter(valid_language)
  if ids.contains("scheme") {
    "scheme"
  } else {
    ids.get(0).unwrap_or("")
  }
}

///|
/// The state of a new workspace: the catalog's defaults, no projects yet, the default layout and an empty tool panel.
/// It takes the page's next opening number.
fn fresh(
  m : Model,
  panel~ : @bottom_panel.State = @bottom_panel.State::new(),
) -> Slice {
  {
    opening: m.openings + 1,
    history: [],
    doc: Source,
    layout: @shell.Layout::default(narrow=m.narrow),
    intent: "",
    concept: "",
    draft_revision: 0,
    notice: None,
    worksheet: false,
    language_projects: Map([]),
    worksheet_source: worksheet_example,
    files_edit: @project_files.State::new(),
    problem_counts: Map([]),
    problem_marks: Map([]),
    sample_request: 0,
    sample_base: None,
    storage_ok: true,
    dirty: [],
    removed_key: "",
    save_attempts: [],
    reset_asking: false,
    reveal: "",
    reveal_nonce: 0,
    source_profile: "",
    model_format: None,
    profile_choices: Map([]),
    explorer_raw: false,
    collapsed_modules: [],
    query: "",
    selected: "",
    evaluation_runtime: if m.connected && m.executions_available {
      @evaluation.TypedInvocation
    } else {
      @evaluation.LocalScheme
    },
    evaluation_policy: @capabilities.CapabilityPolicy::Strict,
    evaluation_host_execution: false,
    evaluation_mode: @evaluation.Fields,
    result_mode: @result.Value,
    evaluation_arguments: "[]",
    evaluation_result: Json::null(),
    evaluation_terminal: @outcomes.Absent,
    evaluation_revision: 0,
    evaluation_result_revision: -1,
    evaluation_entry: "",
    host_draft: None,
    model_revision: 0,
    output: Json::null(),
    worksheet_capture: None,
    worksheet_report: None,
    worksheet_reveal: "",
    document: @document.State::new(),
    generated: false,
    generated_state: @generated.State::new(),
    revision: 0,
    worksheet_revision: 0,
    output_revision: -1,
    host_execution: Json::null(),
    host_execution_revision: 0,
    host_submitting: false,
    submission_unknown: false,
    language: default_language(m.catalog),
    target: if m.connected {
      ""
    } else {
      "scheme"
    },
    projects: [],
    panel,
  }
}

///|
fn active_entry(model : Model) -> @workspace.Entry? {
  match model.active {
    Some(id) => model.registry.get(id)
    None => None
  }
}

///|
/// What the active workspace holds.
fn held(model : Model) -> Array[@workspace.Content] {
  match active_entry(model) {
    Some(entry) => entry.contents
    None => []
  }
}

///|
fn holds(model : Model, content : @workspace.Content) -> Bool {
  held(model).contains(content)
}

///|
fn documents_of(model : Model) -> Array[@workspace.Document] {
  @workspace.documents(held(model), connected=model.connected)
}

///|
fn views_of(model : Model) -> Array[@shell.View] {
  @workspace.views(held(model), connected=model.connected)
}

///|
/// The key of the active workspace's source project for `language`. Without a workspace, the earlier key.
fn storage_key(model : Model, language : String) -> String {
  match active_entry(model) {
    Some(entry) => entry.project_key(language)
    None => "morphir-workbench.project." + language + ".v1"
  }
}

///|
/// The stored keys that start with `prefix`.
extern "js" fn storage_keys_json(prefix : String) -> String =
  #|(prefix) => { try { return JSON.stringify(globalThis.morphirWorkbench.projectIo.storage.keys(prefix) ?? []); } catch { return "[]"; } }

///|
fn stored_keys(prefix : String) -> Array[String] {
  let parsed = @json.parse(storage_keys_json(prefix)) catch { _ => return [] }
  match parsed {
    Array(keys) =>
      keys.filter_map(key => {
        match key {
          String(text) => Some(text)
          _ => None
        }
      })
    _ => []
  }
}

///|
/// The workspace list another page of this browser may have saved since this page read it.
fn stored_registry(load : (String) -> String) -> @workspace.Registry? {
  match load(@workspace.registry_key) {
    "" => None
    saved =>
      Some(@workspace.Registry::from_json(@json.parse(saved)).0) catch {
        _ => None
      }
  }
}

///|
/// This page's registry with the workspaces other pages saved since, numbered after every workspace key this
/// browser holds, so a new workspace never shares another's keys.
fn refreshed(model : Model) -> @workspace.Registry {
  if model.connected {
    return model.registry
  }
  let merged = match stored_registry(storage_load) {
    Some(stored) => model.registry.merge(stored, removed=model.removed)
    None => model.registry
  }
  merged.reserve(
    @workspace.numbers_in_keys(stored_keys("morphir-workbench.workspace.w")),
  )
}

///|
/// Writes the saved workspaces, keeping those another page saved meanwhile. A connected host's page keeps nothing
/// in browser storage.
fn persist_registry(model : Model) -> Model {
  if model.connected {
    return model
  }
  let model = { ..model, registry: refreshed(model), }
  if storage_save(@workspace.registry_key, model.registry.to_json().stringify()) {
    model
  } else {
    note(
      model,
      "Workspaces",
      @bottom_panel.Warning,
      "This browser did not keep the workspace list; it stays in this page until you leave",
    )
  }
}

///|
/// Reads the saved workspaces when the page starts. A list that cannot be read is kept under a backup key, never
/// overwritten unread, and new workspaces are numbered after every workspace key already stored.
fn read_registry(
  model : Model,
  load : (String) -> String,
  keys : (String) -> Array[String],
) -> Model {
  let saved = load(@workspace.registry_key)
  let (registry, problems) = if saved == "" {
    (@workspace.Registry::new(), [])
  } else {
    @workspace.Registry::from_json(@json.parse(saved)) catch {
      _ =>
        (
          @workspace.Registry::new(),
          ["The saved workspace list is not valid JSON"],
        )
    }
  }
  // Anything left unread (invalid JSON, another version, a workspace that does not decode) is copied aside before a
  // later save writes this page's list over it.
  let problems = if problems.is_empty() {
    problems
  } else {
    let backup = @workspace.registry_key + ".unreadable"
    ignore(storage_save(backup, saved))
    [..problems, "The saved workspace list as it was is kept as " + backup]
  }
  let registry = registry.reserve(
    @workspace.numbers_in_keys(keys("morphir-workbench.workspace.w")),
  )
  let mut loaded = { ..model, registry, }
  for problem in problems {
    loaded = note(loaded, "Workspaces", @bottom_panel.Warning, problem)
  }
  loaded
}

///|
/// Adds "My project" for source projects saved before workspaces existed, once the catalog names the languages.
fn adopt_legacy_projects(model : Model, load : (String) -> String) -> Model {
  let legacy = items(field(model.catalog, "frontends")).any(entry => {
    let language = text(entry, "languageId")
    valid_language(language) &&
    load("morphir-workbench.project." + language + ".v1") != ""
  })
  if legacy && !model.registry.entries.iter().any(e => e.storage is Legacy) {
    let (registry, _) = model.registry.adopt_legacy()
    persist_registry({ ..model, registry, })
  } else {
    model
  }
}

///|
/// The document a workspace shows first: its source, else its model, else its first draft.
fn first_document(model : Model) -> @workspace.Document {
  match documents_of(model) {
    [first, ..] => first
    [] => Source
  }
}

///|
/// Makes `id` the active workspace. Its parked state returns; a saved workspace not opened in this page starts fresh
/// and reads its projects and drafts from browser storage. The active workspace is parked, never discarded.
fn activate(model : Model, id : @workspace.WorkspaceId) -> Model {
  if model.active == Some(id) {
    return {
      ..model,
      screen: Workspace,
      picker: false,
      registry: model.registry.touch(id),
    }
  }
  let parked = model.parked.copy()
  match model.active {
    Some(current) if model.registry.get(current) is Some(_) =>
      parked[current] = park(model)
    _ => ()
  }
  let restored = parked.get(id)
  parked.remove(id)
  let base = {
    ..model,
    active: Some(id),
    parked,
    screen: Workspace,
    picker: false,
    build_menu: false,
    registry: model.registry.touch(id),
  }
  match restored {
    Some(slice) => unpark(base, slice)
    None => {
      let entry = base.registry.get(id)
      let opened = unpark({ ..base, openings: base.openings + 1, }, {
        ..fresh(base),
        layout: entry
        .map(e => e.layout)
        .unwrap_or(@shell.Layout::default(narrow=base.narrow)),
      })
      let opened = restore_drafts(restore_all(opened))
      // The workspace reopens on the language it had selected.
      let opened = match entry.bind(e => e.language) {
        Some(language) if valid_language(language.to_string()) &&
          language.to_string() != opened.language =>
          with_language(opened, language.to_string())
        _ => opened
      }
      { ..opened, doc: first_document(opened), }
    }
  }
}

///|
/// Reads the active workspace's intent, conceptual model and worksheet drafts from browser storage.
fn restore_drafts(model : Model) -> Model {
  guard active_entry(model) is Some(entry) && !model.connected else {
    return model
  }
  let worksheet = entry.draft_key(Worksheet)
  {
    ..model,
    intent: storage_load(entry.draft_key(Intent)),
    concept: storage_load(entry.draft_key(ConceptualModel)),
    // A saved empty worksheet stays empty; only a worksheet never saved starts from the example.
    worksheet_source: if storage_stored(worksheet) {
      storage_load(worksheet)
    } else {
      model.worksheet_source
    },
  }
}

///|
/// True when browser storage holds `key`, even with empty text.
extern "js" fn storage_stored(key : String) -> Bool =
  #|(key) => { try { return globalThis.morphirWorkbench.projectIo.storage.load(key) !== null; } catch { return false; } }

///|
/// Adds a workspace and opens it. Without an active workspace, the new one keeps the tool panel's startup records.
fn create(
  model : Model,
  preset : @workspace.Preset,
  contents~ : Array[@workspace.Content],
  name? : @workspace.WorkspaceName,
  saved~ : Bool = true,
) -> Model {
  let (registry, entry) = refreshed(model).create(
    preset,
    name?,
    contents~,
    saved~,
    layout=@shell.Layout::default(narrow=model.narrow),
  )
  let parked = model.parked.copy()
  match model.active {
    Some(current) if model.registry.get(current) is Some(_) =>
      parked[current] = park(model)
    _ => ()
  }
  let panel = if model.active is None {
    model.panel
  } else {
    @bottom_panel.State::new()
  }
  let created = unpark(
    {
      ..model,
      registry,
      parked,
      openings: model.openings + 1,
      active: Some(entry.id),
      screen: Workspace,
      picker: false,
      build_menu: false,
      start: {
        ..model.start,
        panel: Closed,
        message: "",
        name: "",
        name_error: "",
      },
    },
    fresh(model, panel~),
  )
  let created = { ..created, doc: first_document(created), }
  if saved {
    persist_registry(created)
  } else {
    created
  }
}

///|
/// Starts an acquisition from getting started: a provisional workspace becomes active while the page stays on
/// getting started, and the host flow begins.
fn acquire(
  model : Model,
  preset : @workspace.Preset,
  kind : Acquire,
  start : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if model.busy {
    return (
      { ..model, start: { ..model.start, message: busy_reason, }, },
      @cmd.none,
    )
  }
  let previous = model.active
  let created = create(model, preset, contents=[], saved=false)
  let waiting = {
    ..created,
    screen: GettingStarted,
    acquiring: Some({ workspace: created.active.unwrap(), kind, previous, }),
  }
  update_core(waiting, start, routed(waiting, emit))
}

///|
/// The name a workspace gets from what arrived: the model's file or package, the folder's package, or the host
/// folder's first project.
fn acquired_name(model : Model, kind : Acquire) -> String {
  let base = match kind {
    ModelFile(_) =>
      match model.document.original() {
        Some(original) => original.filename.to_string()
        None =>
          match text(model.document.inspection(), "package") {
            "" => "Model"
            name => name
          }
      }
    SourceFolder => active_project(model).name.to_string()
    HostFolder =>
      match model.projects {
        [first, ..] if text(first, "name") != "" => text(first, "name")
        _ => "Workspace folder"
      }
  }
  if base.trim() == "" {
    "Workspace"
  } else {
    base
  }
}

///|
/// Finishes an acquisition once its outcome is known: a success keeps and opens the workspace; a cancellation or
/// failure removes it, returns to the earlier workspace and says why on getting started.
fn settle(before : Model, msg : Msg, after : Model) -> Model {
  guard after.acquiring is Some(acquisition) &&
    after.active == Some(acquisition.workspace) else {
    return after
  }
  let outcome : Bool? = match acquisition.kind {
    ModelFile(_) =>
      if after.document.opening() is None && !after.busy {
        Some(after.document.document() is Some(_))
      } else {
        None
      }
    SourceFolder =>
      match msg {
        FolderPicked(_) if !after.busy => Some(false)
        FolderImported(_, _, _) => Some(after.revision != before.revision)
        _ => None
      }
    HostFolder =>
      if !after.busy {
        Some(!after.projects.is_empty())
      } else {
        None
      }
  }
  match outcome {
    None => after
    Some(true) => {
      let id = acquisition.workspace
      let content : @workspace.Content = match acquisition.kind {
        SourceFolder => SourceProject
        ModelFile(_) | HostFolder => ModelDocument
      }
      let name = after.registry.unique_name(
        acquired_name(after, acquisition.kind),
      )
      let registry = after.registry
        .save(id)
        .add(id, content)
        .rename(id, name)
        .touch(id)
      let kept = {
        ..after,
        registry,
        acquiring: None,
        screen: Workspace,
        doc: match content {
          SourceProject => Source
          _ => Model
        },
        start: { ..after.start, panel: Closed, message: "", },
      }
      persist_registry(kept)
    }
    Some(false) =>
      abandon(
        after,
        acquisition,
        match after.status {
          "" | "Working…" => "The workspace did not open"
          status => status
        },
      )
  }
}

///|
/// Removes a provisional workspace, returns to the workspace that was active before it and says why on getting
/// started. Nothing the earlier workspace held changes. When that workspace closed meanwhile, the most recently used
/// open workspace returns instead.
fn abandon(after : Model, acquisition : Acquisition, message : String) -> Model {
  let registry = after.registry.remove(acquisition.workspace)
  let parked = after.parked.copy()
  let previous = match acquisition.previous {
    Some(previous) if parked.contains(previous) => Some(previous)
    Some(_) => most_recent_open(after).map(e => e.id)
    None => None
  }
  let back = match
    previous.bind(id => parked.get(id).map(slice => (id, slice))) {
    Some((id, slice)) => {
      parked.remove(id)
      unpark({ ..after, registry, parked, active: Some(id), }, slice)
    }
    None => { ..after, registry, parked, active: None, }
  }
  {
    ..back,
    acquiring: None,
    screen: GettingStarted,
    start: { ..back.start, message, },
  }
}

///|
/// Stops waiting for a folder, model or grant: running work is cancelled first, then the provisional workspace goes.
fn stop_acquiring(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  guard model.acquiring is Some(acquisition) &&
    model.active == Some(acquisition.workspace) else {
    return (model, @cmd.none)
  }
  let (cancelled, cmd) = if model.busy || model.document.opening() is Some(_) {
    update_core(model, Cancel, emit)
  } else {
    (model, @cmd.none)
  }
  if cancelled.acquiring is Some(_) {
    (
      abandon(cancelled, acquisition, "Stopped waiting; nothing was opened"),
      cmd,
    )
  } else {
    (cancelled, cmd)
  }
}

///|
/// The emitter for work that the active workspace starts: its messages come back routed to it.
fn routed(model : Model, emit : @cmd.Emit[Msg]) -> @cmd.Emit[Msg] {
  match visit_of(model) {
    Some(visit) =>
      emit.map(msg => {
        match msg {
          Routed(_, _) => msg
          _ => Routed(visit, msg)
        }
      })
    None => emit
  }
}

///|
/// The active workspace's opening.
fn visit_of(model : Model) -> Visit? {
  model.active.map(workspace => { workspace, opening: model.opening, })
}

///|
/// Remembers which opening made the shared runtime busy: the one a routed message came back to, else the workspace
/// active after the message. Freeing the runtime forgets it.
fn track_busy_origin(before : Model, msg : Msg, after : Model) -> Model {
  if !after.busy {
    { ..after, busy_origin: None, }
  } else if before.busy {
    after
  } else {
    let origin = match msg {
      Routed(visit, _) => Some(visit)
      _ => visit_of(after)
    }
    { ..after, busy_origin: origin, }
  }
}

///|
/// Applies a routed message to its workspace. For an inactive workspace, its parked state is restored for the
/// message and parked again, so the active workspace and the screen stay as they are.
fn in_workspace(
  model : Model,
  visit : Visit,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let id = visit.workspace
  if visit_of(model) == Some(visit) {
    return update_here(model, msg, emit)
  }
  guard model.parked.get(id) is Some(slice) && slice.opening == visit.opening else {
    // A save that the closed opening scheduled has nothing left to write: closing wrote it.
    if msg is (SaveProject(_) | SaveDrafts(_)) {
      return (model, @cmd.none)
    }
    // The workspace was removed, closed or never kept: its late reply only frees the shared runtime.
    return (
      {
        ..note(
          model,
          "Workspaces",
          @bottom_panel.Info,
          "Ignored a reply for a workspace that is no longer open",
        ),
        busy: if msg
          is (Receive(request_id, _, _, _)
          | ReceiveModel(_, request_id, _, _, _)) &&
          request_id == model.request_id {
          false
        } else {
          model.busy
        },
      },
      @cmd.none,
    )
  }
  let home = park(model)
  let parked = model.parked.copy()
  parked.remove(id)
  let away = unpark({ ..model, active: Some(id), parked, }, slice)
  let (after, cmd) = update_here(away, msg, emit)
  let parked = after.parked.copy()
  if after.registry.get(id) is Some(_) {
    parked[id] = park(after)
  }
  let back = unpark(
    { ..after, active: model.active, parked, screen: after.screen, },
    home,
  )
  (back, cmd)
}

///|
/// Keeps the registry in step with the active workspace: its layout, and content that arrived (a compiled or
/// imported model, a worksheet run).
fn sync_registry(before : Model, msg : Msg, after : Model) -> Model {
  guard after.active is Some(id) &&
    after.registry.get(id) is Some(entry) &&
    after.acquiring.map(a => a.workspace) != Some(id) else {
    return after
  }
  let mut registry = after.registry
  if entry.layout != after.layout {
    registry = registry.set_layout(id, after.layout)
  }
  if after.document.document() is Some(_) && !entry.holds(ModelDocument) {
    registry = registry.add(id, ModelDocument)
  }
  if after.worksheet && !entry.holds(Worksheet) {
    registry = registry.add(id, Worksheet)
  }
  if after.language != before.language &&
    (Some(@ids.LanguageId::parse(after.language)) catch { _ => None })
    is Some(language) {
    registry = registry.set_language(id, language)
  }
  // A pointer drag saves its width once, when it ends.
  let dragging = msg is (Shell(Resize(_, _)) | Routed(_, Shell(Resize(_, _))))
  let ended = msg is (Shell(EndResize(_)) | Routed(_, Shell(EndResize(_))))
  if ended && entry.saved {
    persist_registry({ ..after, registry, })
  } else if registry == after.registry {
    after
  } else if entry.saved && !dragging {
    persist_registry({ ..after, registry, })
  } else {
    { ..after, registry, }
  }
}

///|
/// Writes every source project changed since its last successful save, not only the one that scheduled the save.
/// Languages that were not written stay dirty.
fn write_projects(model : Model) -> Model {
  let attempts : Array[String] = []
  let still_dirty : Array[String] = []
  for dirty_language in model.dirty {
    match model.language_projects.get(dirty_language) {
      Some(project) => {
        attempts.push(storage_key(model, dirty_language))
        if !storage_save(
            storage_key(model, dirty_language),
            project.to_json().stringify(),
          ) {
          still_dirty.push(dirty_language)
        }
      }
      None => ()
    }
  }
  {
    ..model,
    dirty: still_dirty,
    save_attempts: attempts,
    storage_ok: still_dirty.is_empty(),
  }
}

///|
/// Writes the drafts the workspace holds: its intent, conceptual model and worksheet. False when one was not written.
fn write_drafts(model : Model, entry : @workspace.Entry) -> Bool {
  [
    (entry.draft_key(Intent), model.intent, entry.holds(Intent)),
    (
      entry.draft_key(ConceptualModel),
      model.concept,
      entry.holds(ConceptualModel),
    ),
    (entry.draft_key(Worksheet), model.worksheet_source, entry.holds(Worksheet)),
  ]
  .iter()
  .all(draft => !draft.2 || storage_save(draft.0, draft.1))
}

///|
/// Why the open workspace that `view` shows as active cannot close now, or `None` when it can: an operation it
/// started still runs, or the host keeps an execution it started.
fn close_refusal(model : Model, view : Model) -> String? {
  guard view.active is Some(id) && view.registry.get(id) is Some(entry) else {
    return Some("The workspace is not open")
  }
  if model.connected {
    return Some("A connected host provides this workspace; it cannot be closed")
  }
  if model.busy && model.busy_origin == visit_of(view) {
    return Some(
      "Wait for the running operation in " +
      entry.name.to_string() +
      " to finish before closing it",
    )
  }
  if host_execution_blocks_replacement(view) {
    return Some(
      "Resume or finish the retained host execution before closing " +
      entry.name.to_string(),
    )
  }
  if !entry.saved {
    return Some(
      "This workspace is not saved in this browser, so it cannot close",
    )
  }
  None
}

///|
/// `id` shown as the active workspace: the page as it is when `id` is active, else with `id`'s parked state.
fn viewing(model : Model, id : @workspace.WorkspaceId) -> Model? {
  if model.active == Some(id) {
    Some(model)
  } else {
    model.parked
    .get(id)
    .map(slice => unpark({ ..model, active: Some(id), }, slice))
  }
}

///|
/// Why `id` cannot close now, or `None` when it can. A provisional workspace that still waits can always close.
fn closing_blocked(model : Model, id : @workspace.WorkspaceId) -> String? {
  if model.acquiring.map(a => a.workspace) == Some(id) {
    return None
  }
  match viewing(model, id) {
    Some(view) => close_refusal(model, view)
    None => Some("The workspace is not open")
  }
}

///|
/// Shows why a workspace did not close: on getting started, or in the status line and the tool panel.
/// The picker closes, so the focus returns to its button.
fn close_refused(model : Model, reason : String) -> (Model, @cmd.Cmd) {
  let noted = note(model, "Workspaces", @bottom_panel.Warning, reason)
  if model.screen is GettingStarted {
    (
      { ..noted, picker: false, start: { ..noted.start, message: reason, }, },
      @cmd.none,
    )
  } else {
    (
      { ..noted, picker: false, status: reason, },
      @cmd.custom_cmd(
        _ => focus_if_lost("workspace-picker"),
        kind=@cmd.after_render,
      ),
    )
  }
}

///|
/// The parked workspace used most recently: the highest registry opening order.
fn most_recent_open(model : Model) -> @workspace.Entry? {
  model.parked
  .keys()
  .filter_map(other => model.registry.get(other))
  .fold(init=None, (best : @workspace.Entry?, e) => {
    match best {
      Some(b) if b.opened >= e.opened => best
      _ => Some(e)
    }
  })
}

///|
/// Saves an open workspace's source projects and drafts, then drops its state from the page. It stays saved and
/// listed under Recent workspaces. Closing the active workspace opens the most recently used workspace still open
/// in the page, else getting started. A provisional workspace that still waits closes like Stop waiting.
fn close_workspace(
  model : Model,
  id : @workspace.WorkspaceId,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if model.acquiring.map(a => a.workspace) == Some(id) && !model.connected {
    return stop_acquiring({ ..model, picker: false, }, emit)
  }
  guard viewing(model, id) is Some(view) else { return (model, @cmd.none) }
  if close_refusal(model, view) is Some(reason) {
    return close_refused(model, reason)
  }
  let entry = view.registry.get(id).unwrap()
  let written = write_projects(view)
  let drafts = write_drafts(view, entry)
  // The workspace list must keep the entry too, or the closed workspace could not reopen after a reload.
  let listed = refreshed(model)
  let registry_saved = storage_save(
    @workspace.registry_key,
    listed.to_json().stringify(),
  )
  if !written.dirty.is_empty() || !drafts || !registry_saved {
    return close_refused(
      model,
      "This browser did not save " +
      entry.name.to_string() +
      ", so it stays open",
    )
  }
  let name = entry.name.to_string()
  let parked = model.parked.copy()
  parked.remove(id)
  let closed = {
    ..model,
    parked,
    picker: false,
    build_menu: false,
    start: { ..model.start, removing: None, message: "Closed " + name, },
  }
  if model.active != Some(id) {
    // A parked workspace closes in place; the focus stays on its row under Recent workspaces.
    return (
      persist_registry(closed),
      if model.screen is GettingStarted {
        focus_after_render("recent-open-" + id.to_string())
      } else {
        @cmd.custom_cmd(
          _ => focus_if_lost("workspace-picker"),
          kind=@cmd.after_render,
        )
      },
    )
  }
  let next = most_recent_open(closed)
  // The closed workspace's state goes; a new opening of it starts from browser storage.
  let cleared = unpark({ ..closed, active: None, }, {
    ..fresh(closed),
    opening: 0,
  })
  match next {
    // Closed from getting started, the page stays there and the focus on the closed workspace's row.
    Some(other) if model.screen is GettingStarted => {
      let opened = { ..activate(cleared, other.id), screen: GettingStarted, }
      (
        persist_registry(opened),
        focus_after_render("recent-open-" + id.to_string()),
      )
    }
    Some(other) => {
      let opened = activate(cleared, other.id)
      (persist_registry(opened), focus_after_render("workspace-picker"))
    }
    None if model.screen is GettingStarted =>
      (
        persist_registry({ ..cleared, screen: GettingStarted, }),
        focus_after_render("recent-open-" + id.to_string()),
      )
    None =>
      (
        persist_registry({ ..cleared, screen: GettingStarted, }),
        focus_after_render("start-heading"),
      )
  }
}

///|
fn sample_label(model : Model, id : String) -> String {
  match
    sample_entries({ ..model, worksheet: false, language: "elm", })
    .iter()
    .find_first(entry => entry.0 == id) {
    Some((_, label)) => label
    None => "Example"
  }
}

///|
/// The getting-started and workspace messages.
fn update_workspaces(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let connected_reason = "A connected host provides one workspace. Use Browser local to try ideas or create workspaces."
  // Workspaces need the catalog for their languages; nothing opens before the session starts.
  if msg
    is (CreateWorkspace
    | TryIdea(_)
    | OpenExample(_)
    | OpenWorkspace(_)
    | OpenFolder
    | OpenHostFolder
    | ExploreModel(_)) &&
    model.catalog == Json::null() {
    return (
      {
        ..model,
        start: {
          ..model.start,
          message: if model.busy {
            "The Workbench is still starting; try again in a moment"
          } else {
            "The Workbench did not start: " + model.status
          },
        },
      },
      @cmd.none,
    )
  }
  // Entering another workspace first gives up a pending acquisition, so the provisional workspace never outlives it.
  if msg
    is (CreateWorkspace
    | TryIdea(_)
    | OpenExample(_)
    | OpenWorkspace(_)
    | OpenFolder
    | OpenHostFolder
    | ExploreModel(_)) &&
    model.acquiring is Some(_) {
    let (stopped, stop) = stop_acquiring(model, emit)
    if stopped.acquiring is None {
      let (next, cmd) = update_workspaces(
        { ..stopped, start: { ..stopped.start, message: "", }, },
        msg,
        emit,
      )
      return (next, @cmd.batch([stop, cmd]))
    }
  }
  match msg {
    ShowStart =>
      (
        { ..model, screen: GettingStarted, picker: false, build_menu: false, },
        focus_after_render("start-heading"),
      )
    StartPanel(panel) => {
      let panel = if model.start.panel == panel { Closed } else { panel }
      (
        {
          ..model,
          start: { ..model.start, panel, name_error: "", message: "", },
        },
        if panel == CreateChoices {
          focus_after_render("create-name")
        } else {
          @cmd.none
        },
      )
    }
    StartName(name) =>
      ({ ..model, start: { ..model.start, name, name_error: "", }, }, @cmd.none)
    StartPreset(preset) =>
      ({ ..model, start: { ..model.start, preset, }, }, @cmd.none)
    CreateWorkspace => {
      if model.connected {
        return (
          { ..model, start: { ..model.start, message: connected_reason, }, },
          @cmd.none,
        )
      }
      let name = if model.start.name.trim() == "" {
        Ok(model.registry.unique_name(model.start.preset.base_name()))
      } else {
        @workspace.WorkspaceName::parse(model.start.name)
      }
      match name {
        Err(problem) =>
          (
            { ..model, start: { ..model.start, name_error: problem, }, },
            focus_after_render("create-name"),
          )
        Ok(name) => {
          let preset = model.start.preset
          let contents : Array[@workspace.Content] = match preset {
            SourceProject => [SourceProject]
            Sandbox => [Intent]
            ModelExploration => [ModelDocument]
            Empty => []
          }
          let created = create(model, preset, contents~, name~)
          (created, focus_after_render("workspace-picker"))
        }
      }
    }
    TryIdea(content) => {
      if model.connected {
        return (
          { ..model, start: { ..model.start, message: connected_reason, }, },
          @cmd.none,
        )
      }
      let created = create(model, Sandbox, contents=[content])
      let created = match content {
        Intent => { ..created, doc: IntentDraft, }
        ConceptualModel => { ..created, doc: ConceptDraft, }
        _ => { ..created, doc: Source, worksheet: true, }
      }
      (
        created,
        focus_after_render(
          match content {
            Intent => "intent-text"
            ConceptualModel => "concept-text"
            _ => "workspace-picker"
          },
        ),
      )
    }
    OpenExample(id) => {
      if model.connected {
        return (
          { ..model, start: { ..model.start, message: connected_reason, }, },
          @cmd.none,
        )
      }
      let name = model.registry.unique_name(sample_label(model, id))
      let created = create(
        model,
        SourceProject,
        contents=[SourceProject],
        name~,
      )
      let created = { ..created, doc: Source, }
      let into = routed(created, emit)
      let (opened, cmd) = update_core(created, Sample(id), into)
      // A built-in example replaces the project at once: save it under the new workspace's keys.
      let dirty = opened.language_projects.keys().collect()
      (
        { ..opened, dirty, },
        @cmd.batch([cmd, @cmd.delay(into(SaveProject(opened.revision)), 600)]),
      )
    }
    OpenFolder =>
      if model.connected {
        (
          { ..model, start: { ..model.start, message: connected_reason, }, },
          @cmd.none,
        )
      } else {
        acquire(model, SourceProject, SourceFolder, PickFolder, emit)
      }
    OpenHostFolder =>
      if model.workspace_available {
        acquire(model, ModelExploration, HostFolder, Request("workspace"), emit)
      } else {
        (model, @cmd.none)
      }
    ExploreModel(tree) =>
      if model.connected {
        (
          { ..model, start: { ..model.start, message: connected_reason, }, },
          @cmd.none,
        )
      } else {
        acquire(
          model,
          ModelExploration,
          ModelFile(tree),
          if tree {
            ImportTree
          } else {
            Import
          },
          emit,
        )
      }
    OpenWorkspace(id) =>
      if model.registry.get(id) is Some(_) {
        let opened = activate(model, id)
        (persist_registry(opened), focus_after_render("workspace-picker"))
      } else {
        (model, @cmd.none)
      }
    AskRemove(None) => {
      let kept = model.start.removing
      (
        { ..model, start: { ..model.start, removing: None, }, },
        match kept {
          Some(id) => focus_after_render("recent-open-" + id.to_string())
          None => @cmd.none
        },
      )
    }
    AskRemove(id) =>
      (
        { ..model, start: { ..model.start, removing: id, }, },
        focus_after_render("recent-remove-confirm"),
      )
    RemoveWorkspace(id) => {
      if model.active == Some(id) || model.parked.contains(id) {
        return (
          {
            ..model,
            start: {
              ..model.start,
              removing: None,
              message: "Close the workspace before you remove it from this browser",
            },
          },
          @cmd.none,
        )
      }
      match model.registry.get(id) {
        Some(entry) => {
          let languages = items(field(model.catalog, "frontends")).map(f => {
            text(f, "languageId")
          })
          for key in entry.keys(languages) {
            ignore(storage_remove(key))
          }
          let removed = persist_registry({
            ..model,
            registry: model.registry.remove(id),
            removed: [..model.removed, id],
            start: {
              ..model.start,
              removing: None,
              message: "Removed " +
              entry.name.to_string() +
              " from this browser",
            },
          })
          (removed, focus_after_render("recent-heading"))
        }
        None => (model, @cmd.none)
      }
    }
    AddContent(content) => {
      guard model.active is Some(id) else { return (model, @cmd.none) }
      let registry = model.registry.add(id, content)
      let added = { ..model, registry, }
      let added = if active_entry(added).map(e => e.saved).unwrap_or(false) {
        persist_registry(added)
      } else {
        added
      }
      match content {
        Intent =>
          ({ ..added, doc: IntentDraft, }, focus_after_render("intent-text"))
        ConceptualModel =>
          ({ ..added, doc: ConceptDraft, }, focus_after_render("concept-text"))
        Worksheet => ({ ..added, doc: Source, worksheet: true, }, @cmd.none)
        SourceProject =>
          (
            {
              ..added,
              doc: Source,
              worksheet: false,
              layout: added.layout.apply(Reveal(Files)),
            },
            @cmd.none,
          )
        ModelDocument => update_core({ ..added, doc: Model, }, Import, emit)
      }
    }
    // An opened menu takes the focus, so arrows and Escape work at once.
    Picker(open) =>
      (
        { ..model, picker: open, },
        if open {
          @cmd.custom_cmd(
            _ => focus_first(".picker-menu"),
            kind=@cmd.after_render,
          )
        } else {
          @cmd.none
        },
      )
    ShowDocument(doc) =>
      (
        remember(model, {
          ..model,
          doc,
          screen: Workspace,
          worksheet: if doc == Source &&
            !holds(model, SourceProject) &&
            !model.connected {
            true
          } else {
            model.worksheet
          },
        }),
        @cmd.none,
      )
    IntentText(intent) => {
      let draft_revision = model.draft_revision + 1
      (
        { ..model, intent, draft_revision, },
        @cmd.delay(emit(SaveDrafts(draft_revision)), 400),
      )
    }
    ConceptText(concept) => {
      let draft_revision = model.draft_revision + 1
      (
        { ..model, concept, draft_revision, },
        @cmd.delay(emit(SaveDrafts(draft_revision)), 400),
      )
    }
    SaveDrafts(revision) =>
      match active_entry(model) {
        Some(entry) if revision == model.draft_revision &&
          entry.saved &&
          !model.connected => {
          let ok = write_drafts(model, entry)
          ({ ..model, storage_ok: ok && model.dirty.is_empty(), }, @cmd.none)
        }
        _ => (model, @cmd.none)
      }
    CloseWorkspace(id) => close_workspace(model, id, emit)
    Shell(action) => {
      let layout = model.layout.apply(action)
      let focus = match action {
        // Closing a sidebar that held the focus returns it to the rail or the toggle, so it is never lost; a
        // shortcut pressed in the editor leaves the focus there.
        SetOpen(Primary, false) | Toggle(Primary) if !layout.is_open(Primary) =>
          @cmd.custom_cmd(
            _ => focus_if_lost("rail-explorer"),
            kind=@cmd.after_render,
          )
        SetOpen(Secondary, false) | Toggle(Secondary) if !layout.is_open(
            Secondary,
          ) =>
          @cmd.custom_cmd(
            _ => focus_if_lost("toggle-secondary"),
            kind=@cmd.after_render,
          )
        Move(view, _) => focus_after_render(@shell.section_id(view))
        _ => @cmd.none
      }
      ({ ..model, layout, }, focus)
    }
    ShowGenerated =>
      (
        {
          ..model,
          layout: model.layout.apply(Reveal(Generated)),
          notice: None,
          doc: Source,
          worksheet: false,
          generated: true,
        },
        focus_after_render(@shell.section_id(Generated)),
      )
    DismissNotice => ({ ..model, notice: None, }, @cmd.none)
    BuildMenu(open) =>
      (
        { ..model, build_menu: open, },
        if open {
          @cmd.custom_cmd(
            _ => focus_first(".build-menu"),
            kind=@cmd.after_render,
          )
        } else {
          @cmd.none
        },
      )
    StopAcquiring => stop_acquiring(model, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// After `initialize`: a connected host's page opens its one workspace; a local page reads its saved workspaces and
/// shows getting started.
fn start_session(model : Model) -> Model {
  if model.connected {
    let name = @workspace.WorkspaceName::parse("Connected host").unwrap_or(
      model.registry.unique_name("Workspace"),
    )
    let opened = create(model, Empty, contents=[], name~, saved=false)
    { ..opened, projects: model.projects, doc: Source, }
  } else {
    adopt_legacy_projects(model, storage_load)
  }
}

///|
/// Focuses the element with `id` when the focus was lost: nothing has it, or the element that has it was hidden or
/// removed (browsers move the focus to the body only after the render).
extern "js" fn focus_if_lost(id : String) =
  #|(id) => { const active = document.activeElement; if (!active || active === document.body || !active.isConnected || active.getClientRects().length === 0) document.getElementById(id)?.focus(); }

///|
/// Focuses the first enabled entry of the menu that `selector` names.
extern "js" fn focus_first(selector : String) =
  #|(selector) => document.querySelector(selector)?.querySelector('[role^="menuitem"]:not(:disabled)')?.focus()
