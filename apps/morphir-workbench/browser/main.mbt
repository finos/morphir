///|
extern "js" fn host_request(request : String, receive : (String) -> Unit) =
  #| (request, receive) => globalThis.morphirWorkbench.request(JSON.parse(request), receive)

///|
extern "js" fn fetch_text(path : String, receive : (String) -> Unit) =
  #| (path, receive) => globalThis.morphirWorkbench.projectIo.fetchText(path, receive)

///|
extern "js" fn pick_folder(receive : (String) -> Unit) =
  #| (receive) => globalThis.morphirWorkbench.projectIo.pickFolder(receive)

///|
extern "js" fn watch_drop(selector : String, receive : (String) -> Unit) =
  #| (selector, receive) => globalThis.morphirWorkbench.projectIo.watchDrop(selector, receive)

///|
extern "js" fn storage_load(key : String) -> String =
  #| (key) => { try { return globalThis.morphirWorkbench.projectIo.storage.load(key) ?? "" } catch { return "" } }

///|
extern "js" fn storage_save(key : String, text : String) -> Bool =
  #| (key, text) => { try { return globalThis.morphirWorkbench.projectIo.storage.save(key, text) } catch { return false } }

///|
extern "js" fn storage_remove(key : String) -> Bool =
  #| (key) => { try { return globalThis.morphirWorkbench.projectIo.storage.remove(key) } catch { return false } }

///|
extern "js" fn cancel_host() =
  #| () => globalThis.morphirWorkbench.cancel()

///|
extern "js" fn invalidate_artifacts() =
  #| () => globalThis.morphirWorkbench.invalidateArtifacts()

///|
extern "js" fn import_model_tree(attempt : String, receive : (String) -> Unit) =
  #| (attempt, receive) => globalThis.morphirWorkbench.importModelTree(attempt, receive)

///|
extern "js" fn import_model(
  attempt : String,
  format : String,
  receive : (String) -> Unit,
) =
  #| (attempt, format, receive) => globalThis.morphirWorkbench.importModel(attempt, format, receive)

///|
extern "js" fn cancel_model_open(attempt : String) =
  #| (attempt) => globalThis.morphirWorkbench.cancelModelOpen(attempt)

///|
extern "js" fn release_model() =
  #| () => globalThis.morphirWorkbench.releaseModel()

///|
extern "js" fn download_ir(text : String) =
  #| (text) => globalThis.morphirWorkbench.download(text)

///|
extern "js" fn download_generated(files : String, project : Bool) -> String =
  #| (files, project) => globalThis.morphirWorkbench.downloadArtifacts(JSON.parse(files), project)

///|
fn pretty(text : String) -> String {
  @json.parse(text).stringify(indent=2) catch {
    _ => text
  }
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
fn items(value : Json) -> Array[Json] {
  match value {
    Array(values) => values
    _ => []
  }
}

///|
fn object(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
let example : String =
  #|; A small, portable Morphir model
  #|(define (price quantity) (* quantity 12))
  #|(define (total quantity) (+ (price quantity) 5))
  #|(total 3)

///|
let moonbit_example : String =
  #|// One public function in the Boolean model profile
  #|pub fn eligible(active : Bool, vip : Bool) -> Bool {
  #|  active && !vip
  #|}

///|
let elm_example : String =
  #|module Workbench.Main exposing (answer, total)
  #|
  #|answer : Int
  #|answer =
  #|    42
  #|
  #|total : Int -> Int -> Int
  #|total price quantity =
  #|    price * quantity

///|
let moonbit_library_example : String =
  #|fn gate(active : Bool) -> Bool { active }
  #|pub fn eligible(activeUser : Bool, vipMember : Bool) -> Bool {
  #|  let allowed = gate(activeUser)
  #|  allowed && !vipMember
  #|}
  #|pub fn welcome() -> Bool { eligible(true, false) }

///|
let moonbit_string_example : String =
  #|fn prefix() -> String { "Hello, " }
  #|pub fn greet(name : String) -> String {
  #|  let greeting : String = prefix()
  #|  greeting + name
  #|}
  #|pub fn welcome(name : String, enabled : Bool) -> String {
  #|  if enabled { greet(name) } else { "" }
  #|}
  #|pub fn is_morphir(name : String) -> Bool { name == "Morphir" }

///|
let moonbit_supported_example : String =
  #|fn prefix() -> String { "Hello, " }
  #|pub fn greet(name : String) -> String { prefix() + name }
  #|pub fn welcome(name : String, enabled : Bool) -> String {
  #|  if enabled { greet(name) } else { "" }
  #|}
  #|pub fn choose_for(name : String, enabled : Bool, first : Int32, second : Int) -> Int32 {
  #|  let greeting : String = welcome(name, enabled)
  #|  if greeting == "Hello, Morphir" { identity(first) } else { identity(second) }
  #|}
  #|fn identity(value : Int32) -> Int { value }

///|
let moonbit_ordered_example : String = moonbit_supported_example +
  "\npub fn precedes(left : String, right : String) -> Bool { left < right }"

///|
let moonbit_current_example : String =
  #|/// Build a greeting while preserving the supplied name.
  #|pub fn greet(name : String) -> String {
  #|  let greeting : String = prefix()
  #|  greeting + name
  #|}
  #|
  #|/// Return the greeting when enabled, or empty text otherwise.
  #|pub fn welcome(name : String, enabled : Bool) -> String {
  #|  if enabled { greet(name) } else { "" }
  #|}
  #|
  #|/// Select the first Int32 for an enabled Morphir greeting.
  #|/// Otherwise preserve the second value, including Int32 extremes.
  #|pub fn choose_for(name : String, enabled : Bool, first : Int32, second : Int) -> Int32 {
  #|  let greeting : String = welcome(name, enabled)
  #|  let selected : Int = if greeting == "Hello, Morphir" { first } else { second }
  #|  identity(selected)
  #|}
  #|
  #|/// Compare names by UTF-16 length first, then code units for ties.
  #|/// For example, "b" precedes "aa".
  #|pub fn precedes(left : String, right : String) -> Bool { left < right }
  #|
  #|/// Describe whether the left name sorts before, after, or with the right.
  #|pub fn compare_names(left : String, right : String) -> String {
  #|  if precedes(left, right) { "before" } else {
  #|    if left > right { "after" } else { "same" }
  #|  }
  #|}
  #|
  #|/// Include both endpoints of the shortlex name range.
  #|pub fn in_name_range(name : String, first : String, last : String) -> Bool {
  #|  name >= first && name <= last
  #|}
  #|
  #|/// Welcome nonempty names when enabled and not blocked.
  #|pub fn should_welcome(name : String, enabled : Bool, blocked : Bool) -> Bool {
  #|  enabled && !blocked && name != ""
  #|}
  #|
  #|/// Preserve the first value when its name sorts first or both names match.
  #|pub fn choose_earlier(left : String, right : String, first : Int32, second : Int) -> Int32 {
  #|  let keep_first : Bool = precedes(left, right) || left == right
  #|  let selected : Int = if keep_first { first } else { second }
  #|  identity((selected : Int32))
  #|}
  #|
  #|/// Preserve supplementary and combining text exactly, without normalization.
  #|pub fn unicode_sample() -> String { "\u{1f600}" + "e\u0301" }
  #|
  #|/// Shared greeting prefix, kept private to this library.
  #|fn prefix() -> String { "Hello, " }
  #|
  #|/// Int and Int32 spellings share the same signed boundary representation.
  #|fn identity(value : Int32) -> Int { value }

///|
let worksheet_example : String =
  #|; Definitions live for this run
  #|(define (square x) (* x x))
  #|(square 7)
  #|(map square '(1 2 3 4))
  #|(+ 1/3 2/3)

///|
struct Location {
  doc : @workspace.Document
  worksheet : Bool
  selected : String
  query : String
  explorer_raw : Bool
} derive(Eq)

///|
struct EvaluationDraft {
  arguments : String
  mode : @evaluation.InputMode
  revision : Int32
} derive(Eq)

///|
enum CapabilityRuntime {
  Unavailable
  Standalone(@capabilities.Evaluator)
  Native(@capabilities.Evaluator)
  Connected(@capabilities.Evaluator)
} derive(Eq)

///|
struct Model {
  /// Getting started, or the active workspace.
  screen : Screen
  /// The workspace whose state the fields after `parked` hold; `None` before any workspace opens.
  active : @workspace.WorkspaceId?
  registry : @workspace.Registry
  /// The state of the other workspaces opened in this page.
  parked : Map[@workspace.WorkspaceId, Slice]
  /// A workspace waiting for its folder, model or grant; it is removed if that does not arrive.
  acquiring : Acquisition?
  /// Workspaces removed in this page; a list another page saved does not bring them back.
  removed : Array[@workspace.WorkspaceId]
  start : Start
  /// The workspace picker in the header is open.
  picker : Bool
  /// The source header's build menu is open.
  build_menu : Bool
  /// The window was narrow when the page started, so new workspaces start with closed sidebars.
  narrow : Bool
  /// The number of workspace openings in this page; the next opening takes the next number.
  openings : Int32
  /// The opening whose operation keeps the shared runtime busy.
  busy_origin : Visit?
  // The active workspace's state follows; `Slice` lists the same fields.
  /// The active workspace's opening. A reply for an earlier opening is ignored.
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
  palette : @palette.State
  /// macOS uses Command for shortcuts; other systems use Control.
  mac : Bool
  problem_counts : Map[String, Int32]
  problem_marks : Map[String, String]
  samples : Array[(String, String)]
  samples_requested : Bool
  /// The last sample asked for, and the Elm project when it was asked for. A reply for an earlier request, or one
  /// that arrives after the Elm project changed, is dropped.
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
  capability_runtime : CapabilityRuntime
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
  status : String
  busy : Bool
  request_id : Int32
  revision : Int32
  worksheet_revision : Int32
  output_revision : Int32
  connected : Bool
  executions_available : Bool
  workspace_available : Bool
  host_execution : Json
  host_execution_revision : Int32
  host_submitting : Bool
  submission_unknown : Bool
  available : Bool
  catalog : Json
  language : String
  target : String
  projects : Array[Json]
  panel : @bottom_panel.State
  started : Double
  site_home : String?
} derive(Eq)

///|
enum Msg {
  /// A message from work that a workspace started; it applies to that workspace even when another is active.
  Routed(Visit, Msg)
  ShowStart
  StartPanel(StartPanel)
  StartName(String)
  StartPreset(@workspace.Preset)
  CreateWorkspace
  TryIdea(@workspace.Content)
  OpenExample(String)
  OpenFolder
  OpenHostFolder
  ExploreModel(Bool)
  OpenWorkspace(@workspace.WorkspaceId)
  AskRemove(@workspace.WorkspaceId?)
  RemoveWorkspace(@workspace.WorkspaceId)
  /// Saves an open workspace and closes it; it stays saved and listed under Recent workspaces.
  CloseWorkspace(@workspace.WorkspaceId)
  AddContent(@workspace.Content)
  Picker(Bool)
  ShowDocument(@workspace.Document)
  IntentText(String)
  ConceptText(String)
  SaveDrafts(Int32)
  Shell(@shell.Action)
  ShowGenerated
  DismissNotice
  BuildMenu(Bool)
  StopAcquiring
  Back
  Layout(Bool)
  Source(String)
  Files(@project_files.Action)
  Palette(@palette.Action)
  RunCommand(@keys.CommandId)
  Copied(String, Bool)
  DetailsCopied(Bool)
  PickFolder
  FolderPicked(String)
  FolderImported(Int32, Int32, String)
  SampleIndex(String)
  SaveProject(Int32)
  ConfirmReset
  CancelReset
  Sample(String)
  SampleLoaded(Int32, String, String)
  EvaluationRuntime(@evaluation.Runtime)
  EvaluationPolicy(@capabilities.CapabilityPolicy)
  EvaluationMode(@evaluation.InputMode)
  ResultMode(@result.Mode)
  Worksheet(@worksheet_view.Action)
  EvaluationEdit(@arguments.Edit)
  EvaluationArguments(String)
  Evaluate
  ExplorerRaw(Bool)
  ToggleModule(String)
  Query(String)
  Select(String)
  OutputTab(Bool)
  Generated(@generated.Action)
  DownloadGenerated(Bool)
  Language(String)
  SourceProfile(String)
  Target(String)
  Example
  ElmExample
  MoonBitExample
  MoonBitLibraryExample
  MoonBitSupportedExample
  MoonBitStringExample
  DownloadSourceUnit(@document.DocumentRevision)
  DownloadOriginal(@document.DocumentRevision)
  CloseModel
  Request(String)
  Receive(Int32, Int32, String, String)
  Cancel
  ResumeExecution
  Import
  ImportTree
  ImportFormat(String)
  Imported(@document.OpenAttempt, String)
  ReceiveModel(@document.OpenAttempt, Int32, Int32, String, String)
  Export
  Project(String)
  Panel(@bottom_panel.Action)
}

///|
extern "js" fn connected_mode() -> Bool = "() => globalThis.morphirWorkbench.connected"

///|
extern "js" fn local_runtime_label() -> String = "() => globalThis.morphirWorkbench.runtimeLabel || 'Browser local'"

///|
/// The site that hosts this copy of the workbench, from `<meta name="morphir-site-home">`; empty when there is none.
extern "js" fn site_home_href() -> String =
  #|() => document.querySelector('meta[name="morphir-site-home"]')?.getAttribute("content") ?? ""

///|
/// True when the window is too narrow for sidebars beside the documents.
extern "js" fn narrow_window() -> Bool =
  #|() => { try { return innerWidth <= 900; } catch { return false; } }

///|
extern "js" fn clock() -> String = "() => new Date().toTimeString().slice(0, 8)"

///|
extern "js" fn now_ms() -> Double = "() => performance.now()"

///|
extern "js" fn focus_element(id : String) =
  #|(id) => requestAnimationFrame(() => document.getElementById(id)?.focus())

///|
extern "js" fn mac_platform() -> Bool =
  #|() => { try { return /Mac|iPhone|iPad|iPod/.test(globalThis.navigator?.platform ?? ''); } catch { return false; } }

///|
/// Listens for shortcuts before the page and the editor see them. `handle` gets the key, Control, Meta, Shift, Alt
/// and whether the person is typing, and returns true when it ran a command; the browser then does nothing more, so
/// Ctrl+P opens the palette and not the print dialog.
extern "js" fn watch_keys(
  handle : (String, Bool, Bool, Bool, Bool, Bool) -> Bool,
) =
  #|(handle) => window.addEventListener('keydown', (event) => {
  #|  if (event.defaultPrevented || event.isComposing) return;
  #|  const path = event.composedPath();
  #|  const editing = path.some(node => node instanceof Element &&
  #|    (node.matches('input, textarea, select, morphir-code-editor') || node.isContentEditable));
  #|  if (handle(event.key ?? '', event.ctrlKey, event.metaKey, event.shiftKey, event.altKey, editing)) {
  #|    event.preventDefault();
  #|    event.stopPropagation();
  #|  }
  #|}, true)

///|
/// Focuses an element after the render that made it; an element not there yet gets one more frame.
extern "js" fn focus_now(id : String) =
  #|(id) => { const el = document.getElementById(id); if (el) el.focus(); else requestAnimationFrame(() => document.getElementById(id)?.focus()); }

///|
extern "js" fn focus_selecting(id : String, start : Int32, end : Int32) =
  #|(id, start, end) => { const el = document.getElementById(id); if (el) { el.focus(); try { el.setSelectionRange(start, end); } catch {} } }

///|
extern "js" fn focus_editor() =
  #|() => requestAnimationFrame(() => document.getElementById('source')?.view?.focus?.())

///|
/// Keeps the element with the focus, inside shadow roots too, so closing the palette can return to it.
extern "js" fn remember_focus() =
  #|() => { let el = document.activeElement; while (el?.shadowRoot?.activeElement) el = el.shadowRoot.activeElement; globalThis.morphirWorkbenchFocus = { el, id: el?.id ?? '' }; }

///|
/// Returns the focus to the element kept by `remember_focus`, or to a new element with its id when a render replaced
/// it, once the palette is gone. Only lost focus is restored: when the palette opened again, or a command moved the
/// focus to its own input or button, nothing happens.
extern "js" fn restore_focus() =
  #|() => requestAnimationFrame(() => requestAnimationFrame(() => {
  #|  const kept = globalThis.morphirWorkbenchFocus; globalThis.morphirWorkbenchFocus = null;
  #|  if (!kept || document.getElementById('palette-input')) return;
  #|  const active = document.activeElement;
  #|  if (active && active !== document.body) return;
  #|  const el = kept.el?.isConnected ? kept.el : (kept.id ? document.getElementById(kept.id) : null);
  #|  el?.focus();
  #|}))

///|
/// Scrolls the palette's selected option into its list; the input keeps the focus, so the browser does not.
extern "js" fn scroll_into_view(id : String) =
  #|(id) => document.getElementById(id)?.scrollIntoView({ block: 'nearest' })

///|
extern "js" fn copy_text(text : String, done : (Bool) -> Unit) =
  #|(text, done) => { try { navigator.clipboard.writeText(text).then(() => done(true), () => done(false)); } catch { done(false); } }

///|
fn initial() -> Model {
  let narrow = narrow_window()
  let model : Model = {
    screen: GettingStarted,
    active: None,
    registry: @workspace.Registry::new(),
    parked: Map([]),
    acquiring: None,
    removed: [],
    start: {
      panel: Closed,
      name: "",
      preset: Empty,
      name_error: "",
      removing: None,
      message: "",
    },
    picker: false,
    build_menu: false,
    narrow,
    openings: 0,
    busy_origin: None,
    opening: 0,
    history: [],
    doc: Source,
    layout: @shell.Layout::default(narrow~),
    intent: "",
    concept: "",
    draft_revision: 0,
    notice: None,
    worksheet: false,
    language_projects: Map([]),
    worksheet_source: worksheet_example,
    files_edit: @project_files.State::new(),
    palette: @palette.State::new(),
    mac: mac_platform(),
    problem_counts: Map([]),
    problem_marks: Map([]),
    samples: [],
    samples_requested: false,
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
    evaluation_runtime: @evaluation.LocalScheme,
    evaluation_policy: @capabilities.CapabilityPolicy::Strict,
    capability_runtime: Unavailable,
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
    status: "Initializing…",
    busy: true,
    request_id: 0,
    revision: 0,
    worksheet_revision: 0,
    output_revision: -1,
    connected: connected_mode(),
    executions_available: false,
    workspace_available: false,
    host_execution: Json::null(),
    host_execution_revision: 0,
    host_submitting: false,
    submission_unknown: false,
    available: false,
    catalog: Json::null(),
    language: "scheme",
    target: "",
    projects: [],
    panel: @bottom_panel.State::new().log(
      clock(),
      "Initialize",
      @bottom_panel.Info,
      if connected_mode() {
        "Connecting to the same-origin Morphir host"
      } else {
        "Starting the local compiler worker"
      },
    ),
    started: now_ms(),
    site_home: match site_home_href() {
      "" => None
      href => Some(href)
    },
  }
  // The saved workspaces are read at once, so nothing created before the worker starts overwrites them.
  read_registry(model, storage_load, stored_keys)
}

// Tool panel records: what the application did, what hosts reported and what
// runs produced. Only existing operations and replies feed these helpers.

///|
fn note(
  model : Model,
  operation : String,
  severity : @bottom_panel.Severity,
  message : String,
  failure? : @bottom_panel.Failure,
) -> Model {
  {
    ..model,
    panel: model.panel.log(clock(), operation, severity, message, failure~),
  }
}

///|
fn reported(
  model : Model,
  operation : String,
  scope : String,
  revision : Int32,
  diagnostics : Array[@bottom_panel.Diagnostic],
  failure? : @bottom_panel.Failure,
) -> Model {
  {
    ..model,
    panel: model.panel.report(
      clock(),
      operation,
      model.request_id,
      scope,
      revision,
      diagnostics,
      failure~,
    ),
  }
}

///|
fn produced(
  model : Model,
  operation : String,
  severity : @bottom_panel.Severity,
  title : String,
  lines : Array[String],
  failure? : @bottom_panel.Failure,
) -> Model {
  {
    ..model,
    panel: model.panel.outcome(
      clock(),
      operation,
      severity,
      title,
      lines,
      failure~,
    ),
  }
}

///|
fn input_problem(model : Model, message : String) -> Model {
  let model = reported(
    model,
    "Evaluation inputs",
    "inputs",
    model.evaluation_revision,
    [
      {
        severity: @bottom_panel.Error,
        code: "",
        message,
        location: entry_label(model, model.selected),
        coordinates: "",
        related: [],
        fix: "",
        stage: "",
        place: None,
      },
    ],
  )
  note(model, "Evaluate", @bottom_panel.Warning, message)
}

///|
fn operation_label(operation : String) -> String {
  match operation {
    "compile" => "Compile"
    "run" => "Compile & run"
    "worksheet" => "Worksheet"
    "evaluate" => "Evaluate"
    "inspect" => "Import"
    "project" => "Open project"
    "workspace" => "Open workspace"
    "initialize" => "Initialize"
    "decode-ion" => "View as Ion text"
    other => other
  }
}

///|
fn entry_name(selected : String) -> String {
  match selected.rev_find("#") {
    Some(index) => selected[index + 1:].to_owned()
    None => selected
  }
}

///|
/// The declaration's source spelling when the loaded model has it.
fn entry_label(model : Model, key : String) -> String {
  match
    items(field(model.document.inspection(), "nodes"))
    .iter()
    .find_first(node => text(node, "key") == key) {
    Some(node) if text(node, "label") != "" => text(node, "label")
    _ => entry_name(key)
  }
}

///|
fn elapsed(model : Model) -> String {
  (now_ms() - model.started).to_int().to_string() + " ms"
}

///|
fn model_summary(result : Json) -> String {
  let nodes = items(field(result, "nodes"))
  fn count(kind : String) -> String {
    nodes.filter(node => text(node, "kind") == kind).length().to_string()
  }
  let name = text(result, "package")
  (if name == "" { "" } else { name + " · " }) +
  count("module") +
  " modules, " +
  count("type") +
  " types, " +
  count("value") +
  " values"
}

///|
fn frontend(model : Model, language : String) -> Json {
  items(field(model.catalog, "frontends"))
  .filter(item => text(item, "languageId") == language)
  .get(0)
  .unwrap_or(Json::null())
}

///|
/// A value that is known to parse because the code spells it: a literal path, package or module name.
/// Never use it for a value from the catalog or a host.
fn[T] known(parsed : () -> T raise Error) -> T {
  parsed() catch {
    error => abort("The workbench built an invalid id: " + error.to_string())
  }
}

///|
/// Explicit project choices stay pinned. Fresh local MoonBit projects use the
/// complete qualified source subset when the provider offers it.
fn selected_profile(model : Model, language : String) -> String {
  if model.connected {
    return ""
  }
  if model.profile_choices.get(language) is Some(profile) {
    return profile
  }
  let entry = frontend(model, language)
  if language == "moonbit" &&
    items(field(entry, "profiles")).any(p => {
      text(p, "id") == "moonbit-model-library-2026-10-17"
    }) {
    return "moonbit-model-library-2026-10-17"
  }
  if language == "moonbit" &&
    items(field(entry, "profiles")).any(p => {
      text(p, "id") == "moonbit-model-library-v2"
    }) {
    return "moonbit-model-library-v2"
  }
  if language == "moonbit" &&
    items(field(entry, "profiles")).any(p => {
      text(p, "id") == "moonbit-model-library-v1"
    }) {
    "moonbit-model-library-v1"
  } else {
    text(entry, "defaultProfile")
  }
}

///|
/// The file rules of a language, from its catalog entry. The file list reads them.
fn file_rules(model : Model, language : String) -> @project.FileRules {
  let entry = frontend(model, language)
  let profile = selected_profile(model, language)
  let kind = items(field(entry, "profiles"))
    .iter()
    .find_first(item => text(item, "id") == profile)
    .map(item => text(item, "compileKind"))
    .unwrap_or("")
  {
    extensions: items(field(entry, "fileExtensions")).filter_map(item => {
      match item {
        String(extension) =>
          Some(@ids.FileExtension::parse(extension)) catch {
            _ => None
          }
        _ => None
      }
    }),
    layout: if kind == "whole-project" {
      ManyFiles
    } else {
      OneFile
    },
  }
}

///|
fn literal_path(text : String) -> @ids.SourcePath {
  known(() => @ids.SourcePath::parse(text))
}

///|
/// The project a language starts with, before the person edits it.
fn default_project(model : Model, language : String) -> @project.Project {
  let entry = frontend(model, language)
  let profile = selected_profile(model, language)
  let has_profiles = !items(field(entry, "profiles")).is_empty()
  let provider = if has_profiles && text(entry, "providerId") != "" {
    Some(@ids.ProviderId::parse(text(entry, "providerId"))) catch {
      _ => None
    }
  } else {
    None
  }
  let profile_id = if has_profiles && profile != "" {
    Some(@ids.ProfileId::parse(profile)) catch {
      _ => None
    }
  } else {
    None
  }
  // A language id that does not parse cannot name a project: use the Scheme default.
  let language_id = @ids.LanguageId::parse(language) catch {
    _ => return default_project(model, "scheme")
  }
  fn single(
    name : String,
    path : @ids.SourcePath,
    content : String,
    exposed : Array[String],
  ) -> @project.Project {
    @project.Project::single(
      language_id,
      known(() => @ids.SourcePackageName::parse(name)),
      path,
      if model.connected {
        ""
      } else {
        content
      },
      provider~,
      profile=profile_id,
      exposed=exposed.map(m => known(() => @ids.SourceModuleName::parse(m))),
    )
  }

  match language {
    "scheme" => single("user", literal_path("src/main.scm"), example, [])
    "moonbit" =>
      single(
        "user",
        literal_path("src/main.mbt"),
        if profile == "moonbit-model-library-2026-10-17" {
          moonbit_current_example
        } else if profile == "moonbit-model-library-v2" {
          moonbit_ordered_example
        } else if profile == "moonbit-model-library-v1" {
          moonbit_supported_example
        } else if profile == "moonbit-model-string-library-v1" {
          moonbit_string_example
        } else if profile == "moonbit-model-bool-library-v1" {
          moonbit_library_example
        } else {
          moonbit_example
        },
        [],
      )
    "elm" =>
      single("Workbench", literal_path("src/Workbench/Main.elm"), elm_example, [
        "Main",
      ])
    _ => {
      let extension = match items(field(entry, "fileExtensions")).get(0) {
        Some(String(extension)) => extension
        _ => ".txt"
      }
      // An extension that gives no valid path falls back to `.txt`.
      let path = @ids.SourcePath::parse("src/main" + extension) catch {
        _ => literal_path("src/main.txt")
      }
      single("user", path, "", [])
    }
  }
}

///|
fn active_project(model : Model) -> @project.Project {
  active_project_of(model, model.language)
}

///|
fn active_project_of(model : Model, language : String) -> @project.Project {
  model.language_projects
  .get(language)
  .unwrap_or_else(() => default_project(model, language))
}

///|
fn active_text(model : Model) -> String {
  active_project(model).active_file().content
}

///|
/// The path of the file in the editor.
fn source_name(model : Model) -> String {
  active_project(model).active.to_string()
}

///|
/// Stores `project` as its language's project. The revision changes only when what a request sends
/// changes (files, name, exposure, provider, profile); moving the active file does not.
fn with_project(model : Model, project : @project.Project) -> Model {
  let before = active_project_of(model, project.language.to_string())
  let language_projects = model.language_projects.copy()
  language_projects[project.language.to_string()] = project
  let changed = before.files != project.files ||
    before.name != project.name ||
    before.exposed != project.exposed ||
    before.provider != project.provider ||
    before.profile != project.profile
  {
    ..model,
    language_projects,
    revision: if changed {
      model.revision + 1
    } else {
      model.revision
    },
  }
}

///|
/// The editor marks of each file with frontend problems, as the JSON the editor reads:
/// `[{line, column, endLine, endColumn, message}]` with one-based display columns.
fn problem_marks(reply : Json) -> Map[String, String] {
  let marks : Map[String, Array[Json]] = Map([])
  for file in items(field(reply, "frontendDiagnostics")) {
    for problem in items(field(file, "problems")) {
      let source = field(problem, "source")
      let profile = text(problem, "coordinateProfile")
      let path = match text(problem, "path") {
        "" => text(file, "path")
        path => path
      }
      match
        (
          field(source, "startLine"),
          field(source, "startColumn"),
          field(source, "endLine"),
          field(source, "endColumn"),
        ) {
        (
          Number(line, ..),
          Number(column, ..),
          Number(end_line, ..),
          Number(end_column, ..),
        ) if path != "" => {
          let list = marks.get(path).unwrap_or([])
          list.push(
            object([
              ("line", Json::number(line)),
              (
                "column",
                Json::number(
                  @bottom_panel.display_column(profile, column.to_int()).to_double(),
                ),
              ),
              ("endLine", Json::number(end_line)),
              (
                "endColumn",
                Json::number(
                  @bottom_panel.display_column(profile, end_column.to_int()).to_double(),
                ),
              ),
              ("message", Json::string(text(problem, "detail"))),
            ]),
          )
          marks[path] = list
        }
        _ => ()
      }
    }
  }
  let found : Map[String, String] = Map([])
  for path, list in marks {
    found[path] = Json::array(list).stringify()
  }
  found
}

///|
/// Opens the file of a problem and asks the editor to show its place. Opening a file does not change the
/// revision. A file the project no longer has is only noted.
fn reveal(model : Model, place : @bottom_panel.Place) -> Model {
  let project = active_project(model)
  let found = project.files.search_by(f => f.path.to_string() == place.path)
  match found {
    None =>
      note(
        model,
        "Problems",
        @bottom_panel.Warning,
        "This file is no longer in the project: " + place.path,
      )
    Some(index) =>
      {
        ..with_project(model, { ..project, active: project.files[index].path, }),
        reveal: place.line.to_string() +
        ":" +
        place.column.to_string() +
        ":" +
        (model.reveal_nonce + 1).to_string(),
        reveal_nonce: model.reveal_nonce + 1,
      }
  }
}

///|
/// A loaded project that names no provider or profile gets the catalog defaults of its language.
fn with_defaults(model : Model, project : @project.Project) -> @project.Project {
  let fresh = default_project(model, project.language.to_string())
  {
    ..project,
    provider: if project.provider is None {
      fresh.provider
    } else {
      project.provider
    },
    profile: if project.profile is None {
      fresh.profile
    } else {
      project.profile
    },
  }
}

///|
/// Puts the stored project of `language` into the model. Nothing stored changes nothing; text that is not a valid
/// project of this language keeps the default and gives the note to show.
fn restored(model : Model, language : String, text : String) -> (Model, String) {
  if text == "" {
    return (model, "")
  }
  let failure = "Could not restore the saved " + language + " project"
  try {
    let project = @project.Project::from_json(@json.parse(text))
    if project.language.to_string() != language {
      return (model, failure + ": it belongs to another language")
    }
    let language_projects = model.language_projects.copy()
    language_projects[language] = project
    ({ ..model, language_projects, }, "")
  } catch {
    @project.ProjectError(_, message) => (model, failure + ": " + message)
    _ => (model, failure)
  }
}

///|
/// After `initialize`: the stored project of each catalog language, in local mode only.
fn restore_all(model : Model) -> Model {
  restore_all_with(model, storage_load)
}

///|
/// `restore_all` with the storage read passed in, so tests need no browser. A restored profile that the catalog
/// lists becomes the language's profile choice; one it does not list is dropped with a note.
fn restore_all_with(model : Model, load : (String) -> String) -> Model {
  if model.connected {
    return model
  }
  let mut restored_model = model
  for entry in items(field(model.catalog, "frontends")) {
    let language = text(entry, "languageId")
    if !valid_language(language) {
      continue
    }
    let (next, message) = restored(
      restored_model,
      language,
      load(storage_key(restored_model, language)),
    )
    restored_model = if message != "" {
      note(next, "Restore", @bottom_panel.Warning, message)
    } else {
      match next.language_projects.get(language) {
        Some({ profile: Some(profile), .. } as project) if next.language_projects.get(
            language,
          ) !=
          restored_model.language_projects.get(language) => {
          let id = profile.to_string()
          if items(field(entry, "profiles"))
            .iter()
            .any(item => text(item, "id") == id) {
            let profile_choices = next.profile_choices.copy()
            profile_choices[language] = id
            {
              ..next,
              profile_choices,
              source_profile: if language == next.language {
                id
              } else {
                next.source_profile
              },
            }
          } else {
            let language_projects = next.language_projects.copy()
            language_projects[language] = { ..project, profile: None, }
            note(
              { ..next, language_projects, },
              "Restore",
              @bottom_panel.Warning,
              "The saved " +
              language +
              " project used the profile " +
              id +
              ", which is no longer available; the default profile is used",
            )
          }
        }
        _ => next
      }
    }
  }
  restored_model
}

///|
/// The text of a `fetchText` reply, or why there is none.
fn reply_text(reply : String) -> Result[String, String] {
  let json = @json.parse(reply) catch {
    _ => return Err("the reply is not JSON")
  }
  if field(json, "ok") == Json::boolean(true) {
    Ok(text(json, "text"))
  } else {
    Err(text(json, "message"))
  }
}

///|
fn parse_index(body : String) -> Result[Array[(String, String)], String] {
  Ok(@project.sample_index(@json.parse(body))) catch {
    @project.ProjectError(_, message) => Err(message)
    _ => Err("the sample list is not JSON")
  }
}

///|
fn parse_sample(body : String) -> Result[@project.Sample, String] {
  Ok(@project.Sample::from_json(@json.parse(body))) catch {
    @project.ProjectError(_, message) => Err(message)
    _ => Err("the sample is not JSON")
  }
}

///|
/// The examples and samples the person can open, as `(id, label)`: the one list that the command palette ("Open
/// sample: …") and the explorer's project menu ("New from sample") both read. The built-in examples come first; each
/// opens its own language, so they are listed for every language. The worksheet opens only its own example. The Elm
/// corpus samples load into the Elm project, so they are listed while Elm is selected and the index has arrived.
fn sample_entries(model : Model) -> Array[(String, String)] {
  let pricing = ("builtin:scheme", "Pricing & arithmetic")
  if model.worksheet {
    return [pricing]
  }
  let builtins = [
    pricing,
    ("builtin:scheme-elm", "Elm constant"),
    ("builtin:moonbit", "MoonBit Boolean"),
    ("builtin:moonbit-supported", "MoonBit library"),
    ("builtin:moonbit-library", "MoonBit Boolean library"),
    ("builtin:moonbit-string", "MoonBit String library"),
  ]
  if model.language == "elm" {
    builtins + model.samples
  } else {
    builtins
  }
}

///|
/// Why no sample can open now; empty when one can. Samples replace local projects, so a host session has none.
fn sample_reason(model : Model) -> String {
  if model.connected {
    "Samples open in local mode; a connected host edits its own sources"
  } else if model.busy {
    busy_reason
  } else {
    ""
  }
}

///|
/// True when `now` has the files, package name and exposure of `base`; opening another file does not count.
fn same_sources(base : @project.Project?, now : @project.Project) -> Bool {
  match base {
    Some(base) =>
      base.files == now.files &&
      base.name == now.name &&
      base.exposed == now.exposed
    None => false
  }
}

///|
/// Replaces a language's project wholesale (an example, a sample, an import): the revision changes and the
/// per-file problems of the earlier project and any inline edit are dropped.
fn replace_project(model : Model, project : @project.Project) -> Model {
  let language_projects = model.language_projects.copy()
  language_projects[project.language.to_string()] = project
  {
    ..model,
    language_projects,
    revision: model.revision + 1,
    problem_counts: Map([]),
    problem_marks: Map([]),
    reveal: "",
    files_edit: @project_files.State::new(),
  }
}

///|
/// The editor language of a file, from its extension.
fn editor_language(model : Model) -> String {
  let path = active_project(model).active.to_string()
  if path.has_suffix(".elm") {
    "elm"
  } else if path.has_suffix(".mbt") {
    "moonbit"
  } else if path.has_suffix(".scm") {
    "scheme"
  } else {
    model.language
  }
}

///|
/// The worker or host request of an operation. The local worker gets the active project; a
/// Morphir host and the worksheet get the text of one source.
fn compile_request(model : Model, operation : String) -> Json {
  let fields : Array[(String, Json)] = [("operation", Json::string(operation))]
  if operation == "worksheet" {
    fields.push(
      (
        "worksheetRequest",
        Json::string(
          (
            {
              "profile": @worksheet.PROFILE,
              "contractVersion": @worksheet.CONTRACT_VERSION,
              "source": {
                "id": "worksheet-source",
                "revision": model.worksheet_revision,
                "text": model.worksheet_source,
              },
            } : Json).stringify(),
        ),
      ),
    )
  }
  if model.worksheet || model.connected {
    fields.push(
      (
        "source",
        Json::string(
          if model.worksheet {
            model.worksheet_source
          } else {
            active_text(model)
          },
        ),
      ),
    )
  } else {
    fields.push(("project", active_project(model).to_request()))
  }
  fields.push(
    (
      "languageId",
      Json::string(if model.worksheet { "scheme" } else { model.language }),
    ),
  )
  fields.push(("target", Json::string(model.target)))
  object(fields)
}

///|
fn worksheet_matches(
  model : Model,
  source : @worksheet.CapturedWorksheetSource,
) -> Bool {
  source.to_json() ==
  (
    {
      "id": "worksheet-source",
      "revision": model.worksheet_revision,
      "text": model.worksheet_source,
    } : Json)
}

///|
/// Replaces the project of `language` with its default project holding `content`.
fn with_example(
  model : Model,
  language : String,
  profile : String,
  content : String,
) -> Model {
  let selected = with_selection(model, language, profile)
  let fresh = default_project(selected, language)
  replace_project(selected, fresh.set_content(fresh.active, content))
}

///|
fn with_selection(model : Model, language : String, profile : String) -> Model {
  let profile_choices = model.profile_choices.copy()
  profile_choices[language] = profile
  let language_projects = model.language_projects.copy()
  if language_projects.get(language) is Some(project) {
    language_projects[language] = {
      ..project,
      // A profile id that does not parse leaves the project's profile as it is.
      profile: if profile == "" {
        project.profile
      } else {
        Some(@ids.ProfileId::parse(profile)) catch {
          _ => project.profile
        }
      },
    }
  }
  {
    ..model,
    language,
    source_profile: profile,
    language_projects,
    profile_choices,
    revision: model.revision + 1,
    problem_counts: if language == model.language {
      model.problem_counts
    } else {
      Map([])
    },
    problem_marks: if language == model.language {
      model.problem_marks
    } else {
      Map([])
    },
    files_edit: if language == model.language {
      model.files_edit
    } else {
      @project_files.State::new()
    },
  }
}

///|
fn valid_language(language : String) -> Bool {
  try {
    ignore(@ids.LanguageId::parse(language))
    true
  } catch {
    _ => false
  }
}

///|
/// A language id that does not parse cannot name a project: the current project stays and the person is told.
fn refuse_language(model : Model, language : String) -> (Model, @cmd.Cmd) {
  let message = "The language id is not valid and was not selected: " + language
  (
    {
      ..note(model, "Language", @bottom_panel.Warning, message),
      status: message,
    },
    @cmd.none,
  )
}

///|
fn with_language(model : Model, language : String) -> Model {
  with_selection(model, language, selected_profile(model, language))
}

///|
fn request_cmd(
  emit : @cmd.Emit[Msg],
  request_id : Int32,
  revision : Int32,
  request : Json,
  opening~ : @document.OpenAttempt? = None,
) -> @cmd.Cmd {
  let request = match (opening, request) {
    (Some(attempt), Object(fields)) => {
      let fields = fields.copy()
      fields["modelOpenAttempt"] = Json::string(attempt.to_string())
      Json::object(fields)
    }
    _ => request
  }
  @cmd.custom_cmd(scheduler => {
    host_request(request.stringify(), reply => {
      scheduler.add(
        emit(
          match opening {
            Some(attempt) =>
              ReceiveModel(
                attempt,
                request_id,
                revision,
                text(request, "operation"),
                reply,
              )
            None =>
              Receive(request_id, revision, text(request, "operation"), reply)
          },
        ),
      )
    })
  })
}

///|
fn location(model : Model) -> Location {
  {
    doc: model.doc,
    worksheet: model.worksheet,
    selected: model.selected,
    query: model.query,
    explorer_raw: model.explorer_raw,
  }
}

///|
fn remember(model : Model, next : Model) -> Model {
  if location(model) == location(next) {
    return next
  }
  let history = model.history.copy()
  if history.length() == 100 {
    history.remove(0) |> ignore
  }
  history.push(location(model))
  { ..next, history, }
}

///|
fn select(model : Model, selected : String) -> Model {
  if selected == model.selected {
    return model
  }
  // Retain only the current host entry. Other declarations keep their normal
  // default inputs; navigating does not discard this request's draft or evidence.
  let host_draft = if model.evaluation_host_execution &&
    model.selected == model.evaluation_entry {
    Some({
      arguments: model.evaluation_arguments,
      mode: model.evaluation_mode,
      revision: model.evaluation_revision,
    })
  } else {
    model.host_draft
  }
  let restored = if model.evaluation_host_execution &&
    selected == model.evaluation_entry {
    host_draft
  } else {
    None
  }
  let profile = evaluation_profile(
    model.document.inspection(),
    selected,
    model.evaluation_runtime.is_typed(),
    capabilities=capability_descriptions(model),
  )
  {
    ..model,
    selected,
    host_draft,
    evaluation_arguments: match restored {
      Some(draft) => draft.arguments
      None =>
        default_arguments(
          profile,
          model.evaluation_mode,
          model.evaluation_runtime.is_typed(),
        )
    },
    evaluation_mode: match restored {
      Some(draft) => draft.mode
      None => model.evaluation_mode
    },
    evaluation_result: if model.evaluation_host_execution {
      model.evaluation_result
    } else {
      Json::null()
    },
    evaluation_terminal: if model.evaluation_host_execution {
      model.evaluation_terminal
    } else {
      @outcomes.Absent
    },
    evaluation_revision: match restored {
      Some(draft) => draft.revision
      None => model.evaluation_revision + 1
    },
  }
}

// A replacement IR invalidates declaration destinations, but experience history
// still lets the user return to the editor. Coalesce destinations after resetting.

///|
fn replacement_history(model : Model) -> Array[Location] {
  let history : Array[Location] = []
  for entry in model.history {
    let entry = { ..entry, selected: "", query: "", }
    if history.last() != Some(entry) {
      history.push(entry)
    }
  }
  let current = { ..location(model), selected: "", query: "", }
  if history.last() == Some(current) {
    history.pop() |> ignore
  }
  history
}

///|
fn update(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let (next, cmd) = match msg {
    Routed(visit, inner) => in_workspace(model, visit, inner, emit)
    _ => update_here(model, msg, emit)
  }
  (track_busy_origin(model, msg, next), cmd)
}

///|
/// Applies a message to the active workspace. Work it starts reports back routed to it; a provisional workspace
/// settles when its folder or model arrives or fails; the registry follows the workspace's layout and contents.
fn update_here(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (next, cmd) = update_saving(model, msg, routed(model, emit))
  (sync_registry(model, msg, settle(model, msg, next)), cmd)
}

///|
/// Schedules saves of the source projects that changed. Opening another workspace saves nothing: each workspace
/// saves its own projects under its own keys.
fn update_saving(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (next, cmd) = update_core(model, msg, emit)
  if next.active != model.active {
    return (next, cmd)
  }
  let cmd = if next.connected && next.revision != model.revision {
    @cmd.batch([@cmd.custom_cmd(_ => invalidate_artifacts()), cmd])
  } else {
    cmd
  }
  if next.connected || msg is SaveProject(_) {
    return (next, cmd)
  }
  // A reset removes its own language's stored copy, so it does not mark that language dirty. The revision it bumps
  // makes every save already scheduled stale, so other dirty languages need a save for the new revision.
  if msg is ConfirmReset {
    return if next.dirty.is_empty() {
      (next, cmd)
    } else {
      (
        next,
        @cmd.batch([cmd, @cmd.delay(emit(SaveProject(next.revision)), 600)]),
      )
    }
  }
  // Languages whose stored project changed (the active file included) stay dirty until a save writes them. A
  // change schedules one debounced save; the save runs only if no later revision change followed.
  let dirty = next.dirty.copy()
  for language, project in next.language_projects {
    if model.language_projects.get(language) != Some(project) &&
      !dirty.contains(language) {
      dirty.push(language)
    }
  }
  if next.revision != model.revision || dirty.length() != next.dirty.length() {
    (
      { ..next, dirty, },
      @cmd.batch([cmd, @cmd.delay(emit(SaveProject(next.revision)), 600)]),
    )
  } else {
    (next, cmd)
  }
}

///|
fn update_core(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    Routed(visit, inner) => in_workspace(model, visit, inner, emit)
    ShowStart
    | StartPanel(_)
    | StartName(_)
    | StartPreset(_)
    | CreateWorkspace
    | TryIdea(_)
    | OpenExample(_)
    | OpenFolder
    | OpenHostFolder
    | ExploreModel(_)
    | OpenWorkspace(_)
    | AskRemove(_)
    | RemoveWorkspace(_)
    | CloseWorkspace(_)
    | AddContent(_)
    | Picker(_)
    | ShowDocument(_)
    | IntentText(_)
    | ConceptText(_)
    | SaveDrafts(_)
    | Shell(_)
    | ShowGenerated
    | DismissNotice
    | BuildMenu(_)
    | StopAcquiring => update_workspaces(model, msg, emit)
    Back => {
      let history = model.history.copy()
      match history.pop() {
        None => (model, @cmd.none)
        Some(previous) => {
          let restored = select(model, previous.selected)
          (
            {
              ..restored,
              history,
              doc: previous.doc,
              worksheet: previous.worksheet,
              query: previous.query,
              explorer_raw: previous.explorer_raw,
            },
            @cmd.none,
          )
        }
      }
    }
    Layout(worksheet) => (remember(model, { ..model, worksheet, }), @cmd.none)
    Source(source) =>
      if model.worksheet {
        // The worksheet is a workspace draft: it is saved with the intent and conceptual model.
        let draft_revision = model.draft_revision + 1
        (
          {
            ..model,
            worksheet_source: source,
            worksheet_revision: model.worksheet_revision + 1,
            worksheet_reveal: "",
            draft_revision,
          },
          @cmd.delay(emit(SaveDrafts(draft_revision)), 400),
        )
      } else {
        let project = active_project(model)
        (
          with_project(model, project.set_content(project.active, source)),
          @cmd.none,
        )
      }
    Files(action) => {
      let before = active_project(model)
      let (files_edit, project, effects) = @project_files.apply(
        model.files_edit,
        explorer_env(model),
        action,
      )
      // A change of the file set makes earlier counts unreliable: the next compile counts again.
      let (problem_counts, problem_marks) = if before.files.map(f => f.path) !=
        project.files.map(f => f.path) {
        (Map([]), Map([]))
      } else {
        (model.problem_counts, model.problem_marks)
      }
      explorer_effects(
        {
          ..with_project(model, project),
          files_edit,
          problem_counts,
          problem_marks,
        },
        effects,
        emit,
      )
    }
    Palette(action) => {
      let (palette, outcome) = model.palette.update(
        action,
        palette_entries(model),
      )
      let model = { ..model, palette, }
      match outcome {
        Stay => {
          let focus = if action is (Show(_) | Ask(_, _)) {
            focus_after_render(@palette.input_id)
          } else {
            @cmd.none
          }
          // A pointer hover selects what is already in view; keys and queries can move past the visible list.
          let scroll = if action is Hover(_) {
            @cmd.none
          } else {
            let selected = @palette.option_id(palette.index)
            @cmd.custom_cmd(
              _ => scroll_into_view(selected),
              kind=@cmd.after_render,
            )
          }
          (model, @cmd.batch([focus, scroll]))
        }
        Closed => (model, @cmd.custom_cmd(_ => restore_focus()))
        Opened(path) => {
          let (opened, cmd) = in_project_view(model, Open(path), emit)
          (opened, @cmd.batch([cmd, @cmd.custom_cmd(_ => focus_editor())]))
        }
        Run(command) => {
          let (ran, cmd) = run_command(model, command, emit, from_palette=true)
          (ran, @cmd.batch([@cmd.custom_cmd(_ => restore_focus()), cmd]))
        }
        Chose(command, value) => {
          let (chosen, cmd) = match command {
            SwitchLanguage => update_core(model, Language(value), emit)
            SetTarget => update_core(model, Target(value), emit)
            SelectProfile => update_core(model, SourceProfile(value), emit)
            SwitchWorkspace =>
              match @workspace.WorkspaceId::parse(value) {
                Some(id) => update_core(model, OpenWorkspace(id), emit)
                None => (model, @cmd.none)
              }
            _ => (model, @cmd.none)
          }
          (chosen, @cmd.batch([@cmd.custom_cmd(_ => restore_focus()), cmd]))
        }
      }
    }
    // The palette is modal: a compile chord does not run behind it.
    RunCommand(Compile) if model.palette.open => (model, @cmd.none)
    // In the worksheet, the compile chord runs the worksheet.
    RunCommand(Compile) if model.worksheet => run_command(model, Run, emit)
    RunCommand(command) => run_command(model, command, emit)
    Copied(path, copied) => {
      let message = if copied {
        "Copied " + path
      } else {
        "This browser did not allow copying " + path
      }
      (
        {
          ..note(
            model,
            "Copy path",
            if copied {
              @bottom_panel.Info
            } else {
              @bottom_panel.Warning
            },
            message,
          ),
          status: message,
        },
        @cmd.none,
      )
    }
    ExplorerRaw(raw) => ({ ..model, explorer_raw: raw, }, @cmd.none)
    ToggleModule(id) => {
      let collapsed_modules = if model.collapsed_modules.contains(id) {
        model.collapsed_modules.filter(module_id => module_id != id)
      } else {
        let modules = model.collapsed_modules.copy()
        modules.push(id)
        modules
      }
      ({ ..model, collapsed_modules, }, @cmd.none)
    }
    Query(query) => ({ ..model, query, }, @cmd.none)
    Select(selected) =>
      (remember(model, { ..select(model, selected), doc: Model, }), @cmd.none)
    EvaluationRuntime(evaluation_runtime) => {
      if model.connected ||
        host_execution_pending(model) ||
        host_execution_disconnected(model) ||
        model.submission_unknown {
        return (model, @cmd.none)
      }
      if evaluation_runtime == model.evaluation_runtime {
        return (model, @cmd.none)
      }
      let profile = evaluation_profile(
        model.document.inspection(),
        model.selected,
        evaluation_runtime.is_typed(),
        capabilities=capability_descriptions(model),
      )
      // Invalidate the request ID as well as resetting the argument document.
      // A held reply from the previous runtime must not replace this result.
      let model = note(
        model,
        "Evaluate",
        @bottom_panel.Info,
        (if model.busy {
          "Cancelled request " + model.request_id.to_string() + ". "
        } else {
          ""
        }) +
        "Evaluation runtime set to " +
        (if evaluation_runtime.is_typed() {
          "typed invocation"
        } else {
          "local Scheme"
        }),
      )
      (
        {
          ..model,
          evaluation_runtime,
          evaluation_host_execution: false,
          host_draft: None,
          evaluation_arguments: default_arguments(
            profile,
            model.evaluation_mode,
            evaluation_runtime.is_typed(),
          ),
          evaluation_result: Json::null(),
          evaluation_terminal: @outcomes.Absent,
          evaluation_revision: model.evaluation_revision + 1,
          request_id: model.request_id + 1,
          busy: false,
          status: "Evaluation mode changed",
        },
        @cmd.custom_cmd(_ => cancel_host()),
      )
    }
    EvaluationPolicy(policy) => {
      if policy == model.evaluation_policy ||
        (
          policy == @capabilities.CapabilityPolicy::Permissive &&
          !checking_available(model)
        ) ||
        host_execution_pending(model) ||
        host_execution_disconnected(model) ||
        model.submission_unknown {
        return (model, @cmd.none)
      }
      // Editing a selection never changes an in-flight request or its result.
      (
        {
          ..model,
          evaluation_policy: policy,
          evaluation_revision: model.evaluation_revision + 1,
          status: "Checking policy changed",
        },
        @cmd.none,
      )
    }
    EvaluationMode(evaluation_mode) => {
      let profile = evaluation_profile(
        model.document.inspection(),
        model.selected,
        model.evaluation_runtime.is_typed(),
        capabilities=capability_descriptions(model),
      )
      let evaluation_arguments = @arguments.convert_inputs(
        profile,
        model.evaluation_arguments,
        model.evaluation_mode == @evaluation.Ion,
        evaluation_mode == @evaluation.Ion,
        model.evaluation_runtime.is_typed(),
      ) catch {
        error => {
          let status = "Cannot switch inputs: " + @arguments.input_error(error)
          return ({ ..input_problem(model, status), status, }, @cmd.none)
        }
      }
      ({ ..model, evaluation_mode, evaluation_arguments, }, @cmd.none)
    }
    ResultMode(result_mode) => ({ ..model, result_mode, }, @cmd.none)
    EvaluationEdit(edit) => {
      let evaluation_arguments = @arguments.edit(
        model.evaluation_arguments,
        edit,
      ) catch {
        _ => {
          let status = "Input fields could not apply this edit. Check JSON inputs."
          return ({ ..input_problem(model, status), status, }, @cmd.none)
        }
      }
      (
        {
          ..model,
          evaluation_arguments,
          evaluation_revision: model.evaluation_revision + 1,
        },
        @cmd.none,
      )
    }
    EvaluationArguments(evaluation_arguments) =>
      (
        {
          ..model,
          evaluation_arguments,
          evaluation_revision: model.evaluation_revision + 1,
        },
        @cmd.none,
      )
    Evaluate => {
      let profile = evaluation_profile(
        model.document.inspection(),
        model.selected,
        model.evaluation_runtime.is_typed(),
        capabilities=capability_descriptions(model),
      )
      if (
          model.evaluation_runtime.is_typed() &&
          model.evaluation_policy == @capabilities.CapabilityPolicy::Permissive &&
          !checking_available(model)
        ) ||
        model.busy ||
        host_execution_pending(model) ||
        host_execution_disconnected(model) ||
        model.submission_unknown ||
        (model.connected && !model.executions_available) ||
        field(profile, "supported") != Json::boolean(true) {
        return (model, @cmd.none)
      }
      if model.evaluation_arguments.length() > 16 * 1024 * 1024 {
        let status = "Function arguments exceed the 16-MiB limit"
        return ({ ..input_problem(model, status), status, }, @cmd.none)
      }
      let arguments = try {
        if model.evaluation_mode == @evaluation.Ion {
          Json::null()
        } else {
          @json.parse(model.evaluation_arguments)
        }
      } catch {
        _ =>
          return (
            {
              ..input_problem(model, "Arguments must be a valid JSON array"),
              evaluation_result: object([
                ("success", Json::boolean(false)),
                (
                  "message",
                  Json::string("Arguments must be a valid JSON array"),
                ),
              ]),
              evaluation_terminal: @outcomes.Absent,
              status: "Invalid evaluation inputs",
              evaluation_result_revision: model.evaluation_revision,
            },
            @cmd.none,
          )
      }
      let request_id = model.request_id + 1
      let model = note(
        model,
        "Evaluate",
        @bottom_panel.Info,
        "Started request " +
        request_id.to_string() +
        " · " +
        entry_label(model, model.selected) +
        " · " +
        (if model.executions_available && model.evaluation_runtime.is_typed() {
          "host typed invocation"
        } else if model.evaluation_runtime.is_typed() {
          "typed invocation"
        } else {
          "local Scheme"
        }) +
        " · inputs revision " +
        model.evaluation_revision.to_string(),
      )
      (
        {
          ..model,
          request_id,
          busy: true,
          started: now_ms(),
          evaluation_entry: model.selected,
          evaluation_host_execution: model.executions_available &&
          model.evaluation_runtime.is_typed(),
          host_draft: if model.executions_available &&
            model.evaluation_runtime.is_typed() {
            Some({
              arguments: model.evaluation_arguments,
              mode: model.evaluation_mode,
              revision: model.evaluation_revision,
            })
          } else {
            None
          },
          evaluation_result: if model.executions_available &&
            model.evaluation_runtime.is_typed() {
            Json::null()
          } else {
            model.evaluation_result
          },
          evaluation_terminal: if model.executions_available &&
            model.evaluation_runtime.is_typed() {
            @outcomes.Absent
          } else {
            model.evaluation_terminal
          },
          host_execution_revision: model.evaluation_revision,
          host_submitting: model.executions_available &&
          model.evaluation_runtime.is_typed(),
          status: "Evaluating function…",
        },
        request_cmd(
          emit,
          request_id,
          model.evaluation_revision,
          object([
            ("operation", Json::string("evaluate")),
            ("source", Json::string(model_source(model.document.inspection()))),
            (
              "entry",
              Json::string(
                model.selected
                .strip_prefix("value|")
                .unwrap_or(model.selected[:])
                .to_owned(),
              ),
            ),
            ("arguments", arguments),
            (
              "admission",
              if model.evaluation_runtime.is_typed() &&
                checking_available(model) {
                @capabilities.selection_to_json(model.evaluation_policy)
              } else {
                Json::null()
              },
            ),
            (
              "argumentsIon",
              if model.evaluation_mode == @evaluation.Ion {
                Json::string(model.evaluation_arguments)
              } else {
                Json::null()
              },
            ),
            (
              "executionMode",
              Json::string(
                if model.evaluation_runtime.is_typed() &&
                  checking_available(model) {
                  "capability"
                } else if model.evaluation_runtime.is_typed() {
                  "typed"
                } else {
                  "local"
                },
              ),
            ),
          ]),
        ),
      )
    }
    OutputTab(generated) => ({ ..model, generated, }, @cmd.none)
    Generated(action) => {
      let (generated_state, effects) = model.generated_state.apply(
        @generated.artifacts(model.output),
        action,
      )
      // Choosing a generated file shows it in the editor area, wherever the Generated explorer is.
      let shown = if action is Select(_) {
        {
          ..model,
          generated_state,
          doc: Source,
          worksheet: false,
          generated: true,
        }
      } else {
        { ..model, generated_state, }
      }
      generated_effects(shown, effects, emit)
    }
    DownloadGenerated(project) =>
      start_download(
        model,
        if project {
          @generated.artifacts(model.output)
        } else {
          [@generated.selected(model.output, model.generated_state.selected)]
        },
        project,
      )
    PickFolder =>
      (
        model,
        @cmd.custom_cmd(scheduler => {
          pick_folder(reply => scheduler.add(emit(FolderPicked(reply))))
        }),
      )
    FolderPicked(_) if model.busy =>
      (
        {
          ..note(
            model,
            "Import folder",
            @bottom_panel.Warning,
            "Another operation is running; import the folder when it finishes",
          ),
          status: "Another operation is running; import the folder when it finishes",
        },
        @cmd.none,
      )
    FolderPicked(reply) => {
      let picked = @json.parse(reply) catch { _ => Json::null() }
      if field(picked, "ok") != Json::boolean(true) {
        let message = match text(picked, "message") {
          "" => "The folder could not be read"
          message => message
        }
        return (
          {
            ..note(model, "Import folder", @bottom_panel.Warning, message),
            status: message,
          },
          @cmd.none,
        )
      }
      let skipped = match field(picked, "skipped") {
        Number(n, ..) => n.to_int()
        _ => 0
      }
      let request = object([
        ("operation", Json::string("import-folder")),
        ("files", field(picked, "files")),
      ])
      let request_id = model.request_id + 1
      (
        { ..model, busy: true, request_id, status: "Importing the folder…", },
        @cmd.custom_cmd(scheduler => {
          host_request(request.stringify(), reply => {
            scheduler.add(emit(FolderImported(request_id, skipped, reply)))
          })
        }),
      )
    }
    FolderImported(request_id, _, _) if request_id != model.request_id =>
      (model, @cmd.none)
    FolderImported(_, client_skipped, reply) => {
      let model = { ..model, busy: false, }
      let result = @json.parse(reply) catch { _ => Json::null() }
      let refuse = fn(message : String) {
        (
          {
            ..note(model, "Import folder", @bottom_panel.Warning, message),
            status: message,
          },
          @cmd.none,
        )
      }
      if field(result, "success") != Json::boolean(true) {
        return refuse(
          match text(result, "message") {
            "" => "The folder could not be imported"
            message => message
          },
        )
      }
      let project = @project.Project::from_request(field(result, "project")) catch {
        @project.ProjectError(_, message) => return refuse(message)
      }
      let mut loaded = replace_project(
        with_language(model, "elm"),
        with_defaults(model, project),
      )
      let notes : Array[String] = []
      for warning in items(field(result, "warnings")) {
        if warning is String(text) {
          notes.push(text)
        }
      }
      for name in items(field(field(result, "project"), "exposedModules")) {
        if name is String(module_name) &&
          !project.exposed.iter().any(m => m.to_string() == module_name) {
          notes.push(
            "morphir.json exposes " + module_name + ", which has no source file",
          )
        }
      }
      let skipped = client_skipped +
        (match field(result, "skipped") {
          Number(n, ..) => n.to_int()
          _ => 0
        })
      notes.push(
        "Imported " +
        project.files.length().to_string() +
        " files as " +
        project.name.to_string() +
        (if skipped > 0 {
          "; skipped " + skipped.to_string() + " other files"
        } else {
          ""
        }),
      )
      for message in notes {
        loaded = note(loaded, "Import folder", @bottom_panel.Info, message)
      }
      ({ ..loaded, status: "Folder imported", }, @cmd.none)
    }
    SaveProject(revision) =>
      if revision != model.revision || model.connected || model.dirty.is_empty() {
        (model, @cmd.none)
      } else {
        (write_projects(model), @cmd.none)
      }
    CancelReset => ({ ..model, reset_asking: false, }, @cmd.none)
    ConfirmReset => {
      let fresh = replace_project(model, default_project(model, model.language))
      let removed = storage_remove(storage_key(model, model.language))
      (
        {
          ..fresh,
          reset_asking: false,
          removed_key: storage_key(model, model.language),
          dirty: fresh.dirty.filter(l => l != model.language),
          storage_ok: removed && fresh.storage_ok,
        },
        @cmd.none,
      )
    }
    SampleIndex(reply) =>
      match reply_text(reply).bind(text => parse_index(text)) {
        Ok(samples) => ({ ..model, samples, }, @cmd.none)
        Err(message) =>
          (
            {
              ..note(
                model,
                "Samples",
                @bottom_panel.Warning,
                "The sample list is not available: " + message,
              ),
              samples_requested: false,
            },
            @cmd.none,
          )
      }
    Sample("") => (model, @cmd.none)
    Sample(id) => {
      // Every choice is a new request, so a reply for an earlier Elm sample is dropped whatever came after it.
      let model = { ..model, sample_request: model.sample_request + 1, }
      match id {
        "builtin:scheme" => update_core(model, Example, emit)
        "builtin:scheme-elm" => update_core(model, ElmExample, emit)
        "builtin:moonbit" => update_core(model, MoonBitExample, emit)
        "builtin:moonbit-string" =>
          update_core(model, MoonBitStringExample, emit)
        "builtin:moonbit-supported" =>
          update_core(model, MoonBitSupportedExample, emit)
        "builtin:moonbit-library" =>
          update_core(model, MoonBitLibraryExample, emit)
        _ =>
          if model.samples.iter().any(entry => entry.0 == id) {
            let request = model.sample_request
            (
              { ..model, sample_base: Some(active_project_of(model, "elm")), },
              @cmd.custom_cmd(scheduler => {
                fetch_text("samples/elm/" + id + ".json", reply => {
                  scheduler.add(emit(SampleLoaded(request, id, reply)))
                })
              }),
            )
          } else {
            (model, @cmd.none)
          }
      }
    }
    SampleLoaded(request, id, _) if request != model.sample_request =>
      (
        note(
          model,
          "Samples",
          @bottom_panel.Info,
          "The sample " +
          id +
          " was not opened: another sample was chosen after it",
        ),
        @cmd.none,
      )
    SampleLoaded(_, id, _) if !same_sources(
        model.sample_base,
        active_project_of(model, "elm"),
      ) =>
      (
        {
          ..note(
            model,
            "Samples",
            @bottom_panel.Warning,
            "The sample " +
            id +
            " was not opened: the Elm project changed while it loaded, and opening it would replace those edits",
          ),
          sample_base: None,
        },
        @cmd.none,
      )
    SampleLoaded(_, id, reply) =>
      match reply_text(reply).bind(text => parse_sample(text)) {
        Ok(sample) => {
          let loaded = replace_project(
            model,
            with_defaults(model, sample.project),
          )
          (
            note(
              loaded,
              "Samples",
              @bottom_panel.Info,
              "Opened the sample " + sample.title + ". " + sample.notice,
            ),
            @cmd.none,
          )
        }
        Err(message) =>
          (
            note(
              model,
              "Samples",
              @bottom_panel.Warning,
              "The sample " + id + " was not opened: " + message,
            ),
            @cmd.none,
          )
      }
    Language(language) =>
      if valid_language(language) {
        let switched = {
          ..with_language(model, language),
          reset_asking: false,
        }
        // The sample list is fetched once, when Elm is first selected.
        if language == "elm" && !model.connected && !model.samples_requested {
          (
            { ..switched, samples_requested: true, },
            @cmd.custom_cmd(scheduler => {
              fetch_text("samples/elm/index.json", reply => {
                scheduler.add(emit(SampleIndex(reply)))
              })
            }),
          )
        } else {
          (switched, @cmd.none)
        }
      } else {
        refuse_language(model, language)
      }
    SourceProfile(profile) =>
      (with_selection(model, model.language, profile), @cmd.none)
    Target(target) =>
      ({ ..model, target, revision: model.revision + 1, }, @cmd.none)
    Example =>
      (
        {
          ..with_example(
            model,
            "scheme",
            selected_profile(model, "scheme"),
            example,
          ),
          worksheet_source: worksheet_example,
          worksheet_revision: model.worksheet_revision + 1,
        },
        @cmd.none,
      )
    ElmExample =>
      (
        {
          ..with_example(
            model,
            "scheme",
            selected_profile(model, "scheme"),
            "; Generate an Elm library with Compile\n(define answer 42)",
          ),
          target: "elm",
        },
        @cmd.none,
      )
    MoonBitExample =>
      (
        {
          ..with_example(
            model, "moonbit", "moonbit-model-bool-v1", moonbit_example,
          ),
          target: "moonbit",
        },
        @cmd.none,
      )
    MoonBitLibraryExample =>
      (
        {
          ..with_example(
            model, "moonbit", "moonbit-model-bool-library-v1", moonbit_library_example,
          ),
          target: "moonbit",
        },
        @cmd.none,
      )
    MoonBitSupportedExample =>
      (
        {
          ..with_example(
            model, "moonbit", "moonbit-model-library-2026-10-17", moonbit_current_example,
          ),
          target: "moonbit",
        },
        @cmd.none,
      )
    MoonBitStringExample =>
      (
        {
          ..with_example(
            model, "moonbit", "moonbit-model-library-2026-10-17", moonbit_string_example,
          ),
          target: "moonbit",
        },
        @cmd.none,
      )
    DownloadOriginal(revision) => {
      let (artifacts, project) = match
        (
          model.document.original_for(revision),
          model.document.original_tree_for(revision),
        ) {
        (Some(original), _) => (Json::array([original.download()]), false)
        (_, Some(tree)) => (tree.download(), true)
        _ => return (model, @cmd.none)
      }
      let error = download_generated(artifacts.stringify(), project)
      let message = if error == "" {
        "Original file download started"
      } else {
        error
      }
      (
        {
          ..note(
            model,
            "Download",
            if error == "" {
              @bottom_panel.Info
            } else {
              @bottom_panel.Error
            },
            message,
          ),
          status: message,
        },
        @cmd.none,
      )
    }
    CloseModel => {
      if model.busy &&
        model.document.opening() == None &&
        !host_execution_blocks_replacement(model) {
        return ({ ..model, status: busy_reason, }, @cmd.none)
      }
      let (document, pending) = match
        model.document.close(host_retention(model)) {
        Retained(_) =>
          return (
            {
              ..model,
              status: "Resume or finish the retained host execution before closing the model",
            },
            @cmd.none,
          )
        Closed(document, pending) => (document, pending)
      }
      if model.document.document() == None && pending == None {
        return (model, @cmd.none)
      }
      let output = if [
          "ir", "irSource", "sourceUnitIon", "originalArtifact", "modelSource",
        ].any(key => field(model.output, key) != Json::null()) {
        Json::null()
      } else {
        model.output
      }
      (
        {
          ..model,
          document,
          output,
          history: replacement_history(model),
          model_revision: model.model_revision + 1,
          request_id: model.request_id + 1,
          busy: false,
          selected: "",
          query: "",
          collapsed_modules: [],
          generated_state: model.generated_state.reset(),
          evaluation_result: if model.evaluation_host_execution {
            model.evaluation_result
          } else {
            Json::null()
          },
          evaluation_terminal: if model.evaluation_host_execution {
            model.evaluation_terminal
          } else {
            @outcomes.Absent
          },
          evaluation_revision: model.evaluation_revision + 1,
          evaluation_entry: "",
          status: "Model closed",
        },
        @cmd.custom_cmd(_ => {
          release_model()
          if pending is Some(attempt) {
            cancel_model_open(attempt.to_string())
          }
        }),
      )
    }
    DownloadSourceUnit(revision) => {
      if model.document.current_revision() != Some(revision) {
        return (model, @cmd.none)
      }
      let source = text(model.document.inspection(), "sourceUnitIon")
      if source == "" {
        return (model, @cmd.none)
      }
      let message = download_generated(
        Json::array([
          object([
            ("path", Json::string("main.ion")),
            ("content", Json::string(source)),
            ("binary", Json::boolean(false)),
          ]),
        ]).stringify(),
        false,
      )
      let model = note(
        model,
        "Download",
        if message == "" {
          @bottom_panel.Info
        } else {
          @bottom_panel.Error
        },
        if message == "" {
          "Rich Ion source unit download started as main.ion"
        } else {
          message
        },
      )
      (
        {
          ..model,
          status: if message == "" {
            "Source unit download started"
          } else {
            message
          },
        },
        @cmd.none,
      )
    }
    Request(operation) => {
      if model.busy &&
        operation != "initialize" &&
        !host_execution_blocks_replacement(model) {
        return ({ ..model, status: busy_reason, }, @cmd.none)
      }
      if host_execution_blocks_replacement(model) {
        return (
          {
            ..model,
            status: "Resume or finish the retained host execution before replacing the model",
          },
          @cmd.none,
        )
      }

      let request_id = model.request_id + 1
      let request = compile_request(model, operation)
      let worksheet_capture = if operation == "worksheet" {
        Some(
          @worksheet.WorksheetRequest::decode(text(request, "worksheetRequest")),
        ) catch {
          _ =>
            return (
              {
                ..model,
                status: "Worksheet source exceeds its limits or is invalid.",
              },
              @cmd.none,
            )
        }
      } else {
        None
      }
      let model = note(
        model,
        operation_label(operation),
        @bottom_panel.Info,
        "Started request " +
        request_id.to_string() +
        (if operation == "workspace" {
          " · native folder selection"
        } else if model.worksheet {
          " · worksheet revision " + model.worksheet_revision.to_string()
        } else {
          " · source revision " +
          model.revision.to_string() +
          " · " +
          model.language +
          (if model.source_profile == "" {
            ""
          } else {
            " (" + model.source_profile + ")"
          }) +
          " · target " +
          (if model.target == "" { "none" } else { model.target })
        }),
      )
      (
        {
          ..model,
          request_id,
          worksheet_capture,
          busy: true,
          started: now_ms(),
          status: if operation == "workspace" {
            "Choose a workspace folder…"
          } else {
            "Working…"
          },
        },
        request_cmd(
          emit,
          request_id,
          if operation == "worksheet" {
            model.worksheet_revision
          } else {
            model.revision
          },
          request,
        ),
      )
    }
    ReceiveModel(attempt, request_id, revision, operation, reply) => {
      if !model.document.is_current(attempt) {
        return (model, @cmd.none)
      }
      let (next, command) = update_core(
        model,
        Receive(request_id, revision, operation, reply),
        emit,
      )
      ({ ..next, document: next.document.reject(attempt), }, command)
    }
    Receive(request_id, revision, operation, reply) => {
      if request_id != model.request_id {
        return (
          note(
            model,
            operation_label(operation),
            @bottom_panel.Info,
            "Ignored a late reply for request " + request_id.to_string(),
          ),
          @cmd.none,
        )
      }
      let result = @json.parse(reply) catch {
        _ =>
          object([
            ("success", Json::boolean(false)),
            ("message", Json::string("Invalid host response")),
          ])
      }
      if operation == "worksheet" {
        let report = try {
          let captured = model.worksheet_capture.unwrap()
          @worksheet.WorksheetReport::decode(
            captured,
            text(result, "worksheetReport"),
          )
        } catch {
          _ =>
            return (
              {
                ..note(
                  model,
                  "Worksheet",
                  @bottom_panel.Error,
                  if text(result, "message") == "" {
                    "The worksheet returned an invalid report."
                  } else {
                    text(result, "message")
                  },
                ),
                busy: false,
                worksheet_capture: None,
                status: "Worksheet failed",
              },
              @cmd.none,
            )
        }
        let current = worksheet_matches(model, report.source())
        let completion = field(report.to_json(), "completion")
        let summary = if text(completion, "status") == "cancelled" {
          "Worksheet cancelled"
        } else if text(completion, "status") == "failed" {
          "Worksheet stopped: " + text(field(completion, "failure"), "message")
        } else {
          "Worksheet finished"
        }
        let model = reported(
          model,
          "Worksheet",
          "worksheet",
          revision,
          @worksheet_view.diagnostics(report),
        )
        let model = produced(
          model,
          "Worksheet",
          @bottom_panel.Info,
          summary,
          report
          .observations()
          .map(row => row.expression() + "  ⇒  " + row.preview()),
        )
        return (
          {
            ..model,
            busy: false,
            worksheet_capture: None,
            worksheet_report: Some(report),
            status: if current {
              summary
            } else {
              summary + " for an earlier revision"
            },
          },
          @cmd.none,
        )
      }
      if text(result, "operation") == "execution-progress" {
        let host_execution = field(result, "execution")
        return (
          {
            ..model,
            host_execution,
            host_submitting: false,
            status: host_execution_status(host_execution),
          },
          @cmd.none,
        )
      }
      if field(result, "executionTransport") == Json::boolean(true) {
        return (
          {
            ..note(
              model,
              "Host execution",
              @bottom_panel.Warning,
              text(result, "message"),
            ),
            host_execution: if field(result, "execution") == Json::null() {
              model.host_execution
            } else {
              field(result, "execution")
            },
            host_submitting: false,
            submission_unknown: field(result, "submissionUnknown") ==
            Json::boolean(true),
            busy: false,
            status: if field(result, "submissionUnknown") == Json::boolean(true) {
              "Submission status unknown · the host may still be running; reopen the host session"
            } else {
              "Host disconnected · resume the retained execution"
            },
          },
          @cmd.none,
        )
      }
      let model = if field(result, "execution") != Json::null() {
        { ..model, host_execution: field(result, "execution"), }
      } else {
        model
      }
      let operation = if operation == "resume-execution" {
        "evaluate"
      } else {
        operation
      }
      let (result, terminal) = if operation == "evaluate" {
        @outcomes.prepare(result, expected_ids=Some(["workbench"]))
      } else {
        (result, @outcomes.Absent)
      }
      let label = operation_label(operation)
      let took = elapsed(model)
      let succeeded = field(result, "success") == Json::boolean(true)
      if operation == "evaluate" {
        if model.evaluation_entry != model.selected &&
          !model.evaluation_host_execution {
          return (
            {
              ..note(
                model,
                label,
                @bottom_panel.Warning,
                "Request " +
                request_id.to_string() +
                " finished for " +
                entry_label(model, model.evaluation_entry) +
                " after another function was selected; its result was not shown",
              ),
              busy: false,
              status: "Finished for another function",
            },
            @cmd.none,
          )
        }
        let name = entry_label(model, model.evaluation_entry)
        let failure = if succeeded || terminal is Valid(_) {
          None
        } else {
          Some(
            failure_detail(model, operation, request_id, revision, took, result),
          )
        }
        let model = reported(
          model,
          "Evaluate " + name,
          "inputs",
          revision,
          failure?,
          match terminal {
            Valid(_) | Invalid(_) =>
              @bottom_panel.terminal_diagnostics(terminal)
            Absent =>
              if succeeded {
                []
              } else {
                @bottom_panel.reply_diagnostics(result)
              }
          },
        )
        let model = match terminal {
          Valid(summary) =>
            {
              ..model,
              panel: model.panel.outcome(
                clock(),
                label,
                @bottom_panel.terminal_severity(summary),
                "Evaluate " +
                name +
                (if text(result, "profile") == "" {
                  ""
                } else {
                  " · " + text(result, "profile")
                }) +
                " · " +
                summary.heading(),
                [],
                terminal=Some(summary),
              ),
            }
          _ =>
            produced(
              model,
              label,
              if !succeeded {
                @bottom_panel.Error
              } else if text(result, "outcome") == "model-error" {
                @bottom_panel.Warning
              } else {
                @bottom_panel.Info
              },
              "Evaluate " +
              name +
              (if !succeeded {
                " failed"
              } else if text(result, "profile") != "" {
                " · " + text(result, "profile")
              } else {
                " · local runtime"
              }) +
              (if text(result, "outcome") == "model-error" {
                " · model error"
              } else {
                ""
              }),
              if succeeded {
                ["Result: " + text(result, "value")]
              } else {
                [text(result, "message")]
              },
              failure?,
            )
        }
        let model = note(
          model,
          label,
          if !succeeded {
            @bottom_panel.Error
          } else if revision != model.evaluation_revision {
            @bottom_panel.Warning
          } else {
            @bottom_panel.Info
          },
          "Request " +
          request_id.to_string() +
          (if terminal is Valid(_) || succeeded {
            " finished in "
          } else {
            " failed in "
          }) +
          took +
          (match terminal {
            Valid(summary) => " · " + summary.heading()
            _ => ""
          }) +
          (if revision != model.evaluation_revision {
            " for earlier inputs"
          } else {
            ""
          }),
        )
        return (
          {
            ..model,
            busy: false,
            host_submitting: false,
            evaluation_result: result,
            evaluation_terminal: terminal,
            evaluation_result_revision: revision,
            status: if revision != model.evaluation_revision {
              "Finished for earlier inputs"
            } else if terminal is Valid(summary) &&
              summary.level() == @outcomes.Error {
              summary.heading()
            } else if terminal is Valid(summary) &&
              summary.calls.any(c => c.kind == @outcomes.Cancelled) {
              "Evaluation cancelled"
            } else if field(result, "success") == Json::boolean(true) {
              "Function evaluated"
            } else {
              "Evaluation failed"
            },
          },
          @cmd.none,
        )
      }
      if operation == "decode-ion" && succeeded {
        let path = text(result, "path")
        let decoded = text(result, "text")
        let values = match field(result, "values") {
          Number(n, ..) => n.to_int()
          _ => 0
        }
        let (generated_state, _) = model.generated_state.apply(
          @generated.artifacts(model.output),
          ShowIonText(path, decoded, values),
        )
        let message = "Decoded " +
          path +
          " as Ion text: " +
          values.to_string() +
          (if values == 1 { " value, " } else { " values, " }) +
          decoded.length().to_string() +
          " characters in " +
          took
        return (
          {
            ..note(model, label, @bottom_panel.Info, message),
            generated_state,
            generated: true,
            busy: false,
            status: "Decoded " + path + " as Ion text",
          },
          @cmd.none,
        )
      }
      let (scope, scope_revision) = match operation {
        "worksheet" => ("worksheet", revision)
        // A decode belongs to the generated files it read: a new compile makes its problems previous.
        "decode-ion" => ("decode", revision)
        "compile" | "run" => ("source", revision)
        "initialize" => ("session", 0)
        "workspace" => ("session", 0)
        // A successful import or project open replaces the model.
        _ =>
          (
            "model",
            if succeeded && field(result, "ir") != Json::null() {
              model.model_revision + 1
            } else {
              model.model_revision
            },
          )
      }
      // A failed request, or a compile whose generation was refused, keeps its context for the panel's details.
      let failure = if !succeeded || text(result, "generationMessage") != "" {
        Some(
          failure_detail(model, operation, request_id, revision, took, result),
        )
      } else {
        None
      }
      let model = reported(
        model,
        label,
        scope,
        scope_revision,
        @bottom_panel.reply_diagnostics(result),
        failure?,
      )
      let model = if operation == "compile" || operation == "run" {
        {
          ..model,
          problem_counts: @project.problem_counts(result),
          problem_marks: problem_marks(result),
        }
      } else {
        model
      }
      if !succeeded {
        let model = note(
          model,
          label,
          @bottom_panel.Error,
          "Request " +
          request_id.to_string() +
          " failed in " +
          took +
          ": " +
          text(result, "message"),
          failure?,
        )
        let model = produced(
          model,
          label,
          @bottom_panel.Error,
          label + " failed",
          [text(result, "message")],
          failure?,
        )
        let failed = { ..model, busy: false, status: text(result, "message"), }
        return (
          // A connected host's page opens its one workspace even when the host cannot start, so the status bar
          // says why and the source stays where the person expects it.
          if operation == "initialize" &&
            model.connected &&
            model.active is None {
            start_session(failed)
          } else {
            failed
          },
          @cmd.none,
        )
      }
      if operation == "workspace" {
        return (
          {
            ..model,
            busy: false,
            projects: items(field(result, "projects")),
            status: text(result, "message"),
          },
          @cmd.none,
        )
      }
      if text(result, "operation") == "initialize" {
        let catalog = field(result, "catalog")
        let frontends = items(field(catalog, "frontends"))
        let language = if frontends.length() > 0 {
          let ids = frontends
            .map(f => text(f, "languageId"))
            .filter(valid_language)
          if ids.contains("scheme") {
            "scheme"
          } else {
            ids.get(0).unwrap_or("")
          }
        } else {
          ""
        }
        let model = note(
          model,
          label,
          @bottom_panel.Info,
          text(result, "message") +
          " · " +
          frontends.length().to_string() +
          " languages, " +
          items(field(catalog, "targets")).length().to_string() +
          " targets" +
          (if items(field(result, "projects")).is_empty() {
            ""
          } else {
            ", " +
            items(field(result, "projects")).length().to_string() +
            " workspace projects"
          }) +
          " · " +
          took,
        )
        let initialized = {
          ..model,
          busy: false,
          connected: field(result, "connected") == Json::boolean(true),
          capability_runtime: capability_runtime(result),
          executions_available: field(result, "executionsAvailable") ==
          Json::boolean(true),
          workspace_available: field(result, "workspaceAvailable") ==
          Json::boolean(true),
          evaluation_runtime: if field(result, "connected") ==
            Json::boolean(true) &&
            field(result, "executionsAvailable") == Json::boolean(true) {
            @evaluation.TypedInvocation
          } else {
            @evaluation.LocalScheme
          },
          available: !frontends.is_empty(),
          catalog,
          language,
          // A host session starts with empty sources, as before projects.
          language_projects: if field(result, "connected") ==
            Json::boolean(true) {
            Map([])
          } else {
            model.language_projects
          },
          target: if model.connected {
            ""
          } else {
            "scheme"
          },
          projects: items(field(result, "projects")),
          status: text(result, "message"),
        }
        return (start_session(initialized), @cmd.none)
      }
      let compiled = field(result, "ir") != Json::null()
      let document = if compiled {
        model.document.replace(result) catch {
          _ =>
            return (
              {
                ..model,
                busy: false,
                status: "The model source offer is invalid; the previous model was retained",
              },
              @cmd.none,
            )
        }
      } else {
        model.document
      }
      let artifacts = items(field(result, "artifacts"))
      let summary : Array[String] = [model_summary(result)]
      if text(result, "value") != "" {
        summary.insert(0, "Result: " + text(result, "value"))
      }
      if !artifacts.is_empty() {
        summary.push(
          artifacts.length().to_string() +
          " generated files for target " +
          model.target +
          ": " +
          artifacts.map(file => text(file, "path")).join(", "),
        )
      }
      if text(result, "generationMessage") != "" {
        summary.push(text(result, "generationMessage"))
      }
      let model = produced(
        model,
        label,
        if text(result, "generationMessage") != "" {
          @bottom_panel.Warning
        } else {
          @bottom_panel.Info
        },
        label +
        (if text(result, "value") != "" {
          " · " + text(result, "value")
        } else {
          ""
        }) +
        (if operation != "inspect" &&
          operation != "project" &&
          revision != model.revision {
          " · earlier source revision"
        } else {
          ""
        }),
        summary,
        failure?,
      )
      let model = note(
        model,
        label,
        if text(result, "generationMessage") != "" ||
          (
            operation != "inspect" &&
            operation != "project" &&
            revision != model.revision
          ) {
          @bottom_panel.Warning
        } else {
          @bottom_panel.Info
        },
        "Request " +
        request_id.to_string() +
        " finished in " +
        took +
        " · " +
        model_summary(result),
      )
      (
        {
          ..model,
          busy: false,
          output: if operation == "inspect" || operation == "project" {
            model.output
          } else {
            result
          },
          history: if compiled {
            replacement_history(model)
          } else {
            model.history
          },
          model_revision: if compiled {
            model.model_revision + 1
          } else {
            model.model_revision
          },
          evaluation_result: if compiled {
            Json::null()
          } else {
            model.evaluation_result
          },
          evaluation_host_execution: if compiled {
            false
          } else {
            model.evaluation_host_execution
          },
          evaluation_entry: if compiled {
            ""
          } else {
            model.evaluation_entry
          },
          host_draft: if compiled {
            None
          } else {
            model.host_draft
          },
          evaluation_arguments: if compiled {
            "[]"
          } else {
            model.evaluation_arguments
          },
          // The cleared input document is a new input revision, so input
          // diagnostics and late evaluation replies for the old model are previous.
          evaluation_revision: if compiled {
            model.evaluation_revision + 1
          } else {
            model.evaluation_revision
          },
          evaluation_runtime: if model.executions_available && model.connected {
            @evaluation.TypedInvocation
          } else if compiled {
            if text(result, "sourceProfile") == "moonbit-model-bool-v1" ||
              text(result, "sourceProfile") == "moonbit-model-bool-library-v1" {
              @evaluation.TypedInvocation
            } else {
              @evaluation.LocalScheme
            }
          } else {
            model.evaluation_runtime
          },
          document,
          query: if compiled {
            ""
          } else {
            model.query
          },
          collapsed_modules: if compiled {
            []
          } else {
            model.collapsed_modules
          },
          selected: if compiled {
            ""
          } else {
            model.selected
          },
          output_revision: if operation == "inspect" || operation == "project" {
            model.output_revision
          } else {
            revision
          },
          generated_state: if operation == "compile" || operation == "run" {
            model.generated_state.reset()
          } else {
            model.generated_state
          },
          // Generation keeps the layout as it is; a notification offers the files instead.
          notice: if (operation == "compile" || operation == "run") &&
            !artifacts.is_empty() {
            Some({ files: artifacts.length(), target: model.target, })
          } else if operation == "compile" || operation == "run" {
            None
          } else {
            model.notice
          },
          status: if revision == model.revision {
            if text(result, "generationMessage") != "" {
              text(result, "generationMessage")
            } else if text(result, "inspectionMessage") != "" {
              text(result, "inspectionMessage")
            } else {
              "Model ready"
            }
          } else {
            "Finished for an earlier source revision"
          },
        },
        @cmd.none,
      )
    }
    ResumeExecution => {
      if model.busy || model.host_execution == Json::null() {
        return (model, @cmd.none)
      }
      (
        {
          ..model,
          busy: true,
          status: "Reconnecting to the retained host execution…",
          evaluation_host_execution: true,
        },
        request_cmd(
          emit,
          model.request_id,
          model.host_execution_revision,
          object([("operation", Json::string("resume-execution"))]),
        ),
      )
    }
    Cancel => {
      if model.document.opening() is Some(attempt) {
        return (
          {
            ..model,
            document: model.document.reject(attempt),
            busy: false,
            request_id: model.request_id + 1,
            status: "Model opening cancelled",
          },
          @cmd.custom_cmd(_ => cancel_model_open(attempt.to_string())),
        )
      }
      if model.worksheet_capture is Some(_) && model.busy {
        return (
          { ..model, status: "Stopping worksheet…", },
          @cmd.custom_cmd(_ => cancel_host()),
        )
      }
      if host_execution_pending(model) {
        return (
          { ..model, status: "Requesting host cancellation…", },
          @cmd.custom_cmd(_ => cancel_host()),
        )
      }
      (
        {
          ..note(
            model,
            "Cancel",
            @bottom_panel.Warning,
            if model.connected {
              "Discarded request " +
              model.request_id.to_string() +
              ". Connected v1 has no server cancellation; the host may still be working."
            } else {
              "Cancelled request " +
              model.request_id.to_string() +
              " and stopped its worker"
            },
          ),
          busy: false,
          request_id: model.request_id + 1,
          status: if model.connected {
            "Discarded. The host may still be working."
          } else {
            "Cancelled"
          },
        },
        @cmd.custom_cmd(_ => cancel_host()),
      )
    }
    ImportFormat(value) =>
      (
        {
          ..model,
          model_format: if value == "" {
            None
          } else {
            Some(@data.ModelFormat::from_control(value)) catch {
              _ => None
            }
          },
        },
        @cmd.none,
      )
    Import | ImportTree => {
      if model.busy && !host_execution_blocks_replacement(model) {
        return ({ ..model, status: busy_reason, }, @cmd.none)
      }
      let (document, attempt) = match
        model.document.begin(host_retention(model)) {
        Started(document, attempt) => (document, attempt)
        Refused(_) =>
          return (
            {
              ..model,
              status: "Resume or finish the retained host execution before replacing the model",
            },
            @cmd.none,
          )
        Exhausted =>
          return (
            {
              ..model,
              status: "Reopen the page before importing another model",
            },
            @cmd.none,
          )
      }
      (
        {
          ..model,
          document,
          busy: true,
          request_id: model.request_id + 1,
          status: "Choose a model file…",
        },
        @cmd.custom_cmd(scheduler => {
          if msg is ImportTree {
            import_model_tree(attempt.to_string(), reply => {
              scheduler.add(emit(Imported(attempt, reply)))
            })
          } else {
            import_model(
              attempt.to_string(),
              model.model_format.map(f => f.codec_id()).unwrap_or(""),
              reply => scheduler.add(emit(Imported(attempt, reply))),
            )
          }
        }),
      )
    }
    Imported(attempt, source) => {
      if !model.document.is_current(attempt) {
        return (model, @cmd.none)
      }
      if host_execution_blocks_replacement(model) {
        return (
          {
            ..model,
            document: model.document.reject(attempt),
            busy: false,
            status: "Resume or finish the retained host execution before replacing the model",
          },
          @cmd.none,
        )
      }

      let selection = @json.parse(source) catch { _ => Json::null() }
      let tree = text(selection, "kind") == "selected-tree"
      if !tree && text(selection, "kind") != "selected" {
        let message = if text(selection, "kind") == "cancelled" {
          "Model import cancelled"
        } else if text(selection, "reason") == "oversized" {
          "Model import exceeds its file-count, content or path-text limit"
        } else {
          "Could not read the selected model file"
        }
        return (
          {
            ..model,
            document: model.document.reject(attempt),
            busy: false,
            status: message,
          },
          @cmd.none,
        )
      }
      let (label, request) = if tree {
        (
          "captured YAML tree files",
          object([
            ("operation", Json::string("inspect")),
            ("source", Json::string("")),
            ("sourceTree", field(selection, "files")),
          ]),
        )
      } else {
        let (filename, codec) = (
          @document.OriginalFilename::parse(text(selection, "filename")),
          @document.SourceCodec::parse(text(selection, "codec")),
        ) catch {
          _ =>
            return (
              {
                ..model,
                document: model.document.reject(attempt),
                busy: false,
                status: "The selected model file name or format is invalid",
              },
              @cmd.none,
            )
        }
        (
          filename.to_string(),
          object([
            ("operation", Json::string("inspect")),
            ("source", Json::string("")),
            ("sourceCodec", Json::string(codec.to_string())),
            ("sourceBase64", field(selection, "contentBase64")),
            ("sourceFilename", Json::string(filename.to_string())),
          ]),
        )
      }
      let request_id = model.request_id + 1
      let model = note(
        model,
        "Import",
        @bottom_panel.Info,
        "Started request " + request_id.to_string() + " · inspecting " + label,
      )
      (
        remember(model, {
          ..model,
          doc: Model,
          request_id,
          busy: true,
          started: now_ms(),
          status: "Reading model…",
        }),
        request_cmd(
          emit,
          request_id,
          model.revision,
          request,
          opening=Some(attempt),
        ),
      )
    }
    Export =>
      (
        note(
          model,
          "Export",
          @bottom_panel.Info,
          "Exported normalized IR as morphir-ir.json",
        ),
        @cmd.custom_cmd(_ => {
          download_ir(model_source(model.document.inspection()))
        }),
      )
    Worksheet(Reveal(source, range)) => {
      if !worksheet_matches(model, source) || !model.worksheet {
        return (
          {
            ..model,
            status: "Source changed. Run the worksheet again to navigate.",
          },
          @cmd.none,
        )
      }
      let nonce = model.reveal_nonce + 1
      (
        {
          ..model,
          worksheet_reveal: @worksheet_view.reveal(source, range, nonce),
          reveal_nonce: nonce,
        },
        @cmd.none,
      )
    }
    Panel(Reveal(place)) => {
      if place.path == "worksheet.scm" {
        if model.worksheet &&
          model.worksheet_report is Some(report) &&
          worksheet_matches(model, report.source()) {
          let nonce = model.reveal_nonce + 1
          return (
            {
              ..model,
              worksheet_reveal: place.line.to_string() +
              ":" +
              place.column.to_string() +
              ":" +
              nonce.to_string(),
              reveal_nonce: nonce,
            },
            @cmd.none,
          )
        }
        return (model, @cmd.none)
      }
      (reveal(model, place), @cmd.none)
    }
    Panel(CopyDetails(report)) =>
      (
        model,
        @cmd.custom_cmd(scheduler => {
          copy_text(report, copied => scheduler.add(emit(DetailsCopied(copied))))
        }),
      )
    DetailsCopied(copied) => {
      let message = if copied {
        "Copied the details"
      } else {
        "This browser did not allow copying the details"
      }
      (
        {
          ..note(
            model,
            "Copy details",
            if copied {
              @bottom_panel.Info
            } else {
              @bottom_panel.Warning
            },
            message,
          ),
          status: message,
        },
        @cmd.none,
      )
    }
    Panel(action) => {
      let (panel, focus) = model.panel.update(action)
      (
        { ..model, panel, },
        match focus {
          Some(id) => @cmd.custom_cmd(_ => focus_element(id))
          None => @cmd.none
        },
      )
    }
    Project(project) => {
      if model.busy && !host_execution_blocks_replacement(model) {
        return ({ ..model, status: busy_reason, }, @cmd.none)
      }
      if host_execution_blocks_replacement(model) {
        return (
          {
            ..model,
            status: "Resume or finish the retained host execution before replacing the model",
          },
          @cmd.none,
        )
      }

      let (document, attempt) = match
        model.document.begin(host_retention(model)) {
        Started(document, attempt) => (document, attempt)
        Refused(_) => return (model, @cmd.none)
        Exhausted =>
          return (
            { ..model, status: "Reopen the page before opening another model", },
            @cmd.none,
          )
      }
      let request_id = model.request_id + 1
      let model = note(
        model,
        "Open project",
        @bottom_panel.Info,
        "Started request " +
        request_id.to_string() +
        " · workspace project " +
        project,
      )
      (
        {
          ..model,
          document,
          request_id,
          busy: true,
          started: now_ms(),
          status: "Opening project model…",
        },
        request_cmd(
          emit,
          request_id,
          model.revision,
          object([
            ("operation", Json::string("project")),
            ("project", Json::string(project)),
          ]),
          opening=Some(attempt),
        ),
      )
    }
  }
}

///|
fn action_icon(name : String) -> @html.Html {
  @html.span(
    class="action-icon icon-" + name,
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
}

///|
fn output_panel(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let output = model.output
  let targets = [
    @html.option(value="", selected=model.target == "", "No generation"),
  ]
  for target in items(field(model.catalog, "targets")) {
    targets.push(
      @html.option(
        value=text(target, "target"),
        selected=text(target, "target") == model.target,
        text(target, "displayName"),
      ),
    )
  }
  let body : Array[@html.Html] = []
  if !model.worksheet && text(output, "value") != "" {
    body.push(
      @html.div(class="run-value", [
        @html.span(class="muted small", "Result"),
        @html.strong(text(output, "value")),
      ]),
    )
  }
  if model.worksheet {
    if model.worksheet_report is Some(report) {
      body.push(
        @worksheet_view.view(
          report,
          worksheet_matches(model, report.source()),
          emit.map(action => Worksheet(action)),
        ),
      )
    } else {
      body.push(
        @html.p(
          class="muted",
          "Run the worksheet to see expression results and typed details.",
        ),
      )
    }
  } else if model.generated {
    body.push(
      @generated.preview(
        {
          output,
          state: model.generated_state,
          language: model.target,
          mac: model.mac,
        },
        emit.map(action => Generated(action)),
        emit.map(project => DownloadGenerated(project)),
      ),
    )
  } else {
    body.push(
      @editor.view({
        id: "output",
        document_key: "output",
        language: "json",
        label: "Morphir IR",
        read_only: true,
        marks: "",
        reveal: "",
        value: if field(output, "ir") == Json::null() {
          "Your compiled model will appear here."
        } else {
          pretty(model_source(output))
        },
      }),
    )
  }
  let stale = if model.worksheet {
    match model.worksheet_report {
      Some(report) => !worksheet_matches(model, report.source())
      None => false
    }
  } else {
    model.output_revision >= 0 && model.output_revision != model.revision
  }
  @html.section(class="panel output-panel", [
    @html.div(class="panel-heading", [
      @html.div(class="tabs", [
        @html.button(
          class=if !model.generated { "tab selected" } else { "tab" },
          on_click=emit(OutputTab(false)),
          if model.worksheet {
            "Results"
          } else {
            "Morphir IR"
          },
        ),
        @html.button(
          class=if model.generated { "tab selected" } else { "tab" },
          hidden=model.worksheet,
          on_click=emit(OutputTab(true)),
          "Generated",
        ),
      ]),
      @html.div(class="panel-actions", [
        @html.label(class="compact-select", hidden=model.worksheet, [
          @html.span(class="small muted", "Target"),
          @html.select(
            disabled=model.busy,
            on_change=emit.map(value => Target(value)),
            attrs=@html.Attrs::build()
              .aria_label("Target")
              .value_prop(model.target),
            targets,
          ),
        ]),
        @html.span(
          class="stale-badge",
          hidden=!stale,
          if stale {
            "Source changed · rerun"
          } else {
            ""
          },
        ),
        match model.document.current_revision() {
          Some(revision) =>
            @html.button(
              class="ghost",
              hidden=model.worksheet ||
                text(model.document.inspection(), "sourceUnitIon") == "",
              title="Download the rich Ion source unit, including metadata and provenance",
              attrs=@html.Attrs::build().aria_label("Download source unit"),
              on_click=emit(DownloadSourceUnit(revision)),
              [action_icon("download"), @html.span("Source unit")],
            )
          None => @html.span("")
        },
      ]),
    ]),
    @html.div(class="output-body", body),
  ])
}

///|
/// The on-screen way into the command palette, with its shortcut, for people who do not know the chord.
fn command_center(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let chord = @keys.shortcut(@keys.keymap(), ShowCommands, mac=model.mac)
  let label = chord.map(c => c.label(mac=model.mac)).unwrap_or("")
  let attrs = @html.Attrs::build()
    .aria_label("Command palette")
    .aria_haspopup("dialog")
  @html.button(
    class="command-center",
    title="Command palette (" + label + ")",
    attrs=match chord {
      Some(c) => attrs.aria_keyshortcuts(c.aria(mac=model.mac))
      None => attrs
    },
    on_click=emit(RunCommand(ShowCommands)),
    [
      @html.span(
        class="action-icon icon-command",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "",
      ),
      @html.span(class="command-center-label", "Command palette"),
      @html.kbd(class="shortcut", label),
    ],
  )
}

///|
/// The Morphir logo. It links to the hosting site when there is one.
/// The site links use `escape=true`: the workbench has no router, and Rabbita drops captured link clicks without one.
fn brand(site_home : String?) -> @html.Html {
  let logos = [
    @html.img(class="brand-mark", src="./morphir-mark.svg", alt="Morphir"),
    @html.img(
      class="brand-logo nav-label",
      src="./morphir-logo.svg",
      alt="Morphir",
    ),
  ]
  match site_home {
    Some(href) =>
      @html.a(
        class="brand",
        href~,
        title="Morphir home",
        attrs=@html.Attrs::build().aria_label("Morphir home"),
        logos,
        escape=true,
      )
    None => @html.div(class="brand", logos)
  }
}

///|
/// The workspace opening whose drop zone received a dropped folder, from the reply's `workspace` and `opening`
/// members.
fn drop_origin(reply : String) -> Visit? {
  let parsed = @json.parse(reply) catch { _ => return None }
  match parsed {
    Object(fields) =>
      match (fields.get("workspace"), fields.get("opening")) {
        (Some(String(id)), Some(Number(opening, ..))) =>
          @workspace.WorkspaceId::parse(id).map(workspace => {
            workspace,
            opening: opening.to_int(),
          })
        _ => None
      }
    _ => None
  }
}

///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        (
          initial(),
          @cmd.batch([
            request_cmd(
              emit,
              0,
              0,
              object([("operation", Json::string("initialize"))]),
            ),
            @cmd.custom_cmd(scheduler => {
              watch_drop("[data-drop=\"project\"]", reply => {
                // A dropped folder belongs to the workspace that showed the drop zone.
                scheduler.add(
                  emit(
                    match drop_origin(reply) {
                      Some(visit) => Routed(visit, FolderPicked(reply))
                      None => FolderPicked(reply)
                    },
                  ),
                )
              })
            }),
            @cmd.custom_cmd(scheduler => {
              let mac = mac_platform()
              watch_keys((key, ctrl, meta, shift, alt, editing) => {
                let chord = @keys.Chord::from_event(
                  key,
                  ctrl~,
                  meta~,
                  shift~,
                  alt~,
                  mac~,
                )
                match
                  @keys.resolve(@keys.keymap(), chord, {
                    editing,
                    in_tree: false,
                  }) {
                  Some(command) => {
                    scheduler.add(emit(RunCommand(command)))
                    true
                  }
                  None => false
                }
              })
            }),
          ]),
        )
      },
      update~,
    )
    model.view(model => view(model, emit))
  }).mount("app")
}

///|
/// "Not saved" after a failed save, and the inline question of "Reset project".
fn project_storage(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(class="project-storage", [
    @html.p(
      class="small file-error",
      hidden=model.storage_ok,
      title="This browser did not keep the project. It stays in this page until you leave.",
      "Not saved",
    ),
    if model.reset_asking {
      @html.div(
        class="explorer-reset",
        attrs=@html.Attrs::build()
          .role("group")
          .aria_label("Reset project")
          .on_keydown(event => {
            if event.key() == "Escape" {
              event.prevent_default()
              emit(CancelReset)
            } else {
              @cmd.none
            }
          }),
        [
          @html.span(
            "Reset the " +
            language_name(model, model.language) +
            " project to its starting file? Your changes are lost.",
          ),
          @html.div(class="explorer-reset-actions", [
            @html.button(
              id="reset-confirm",
              class="danger small",
              attrs=@html.Attrs::build().aria_label("Confirm reset"),
              on_click=emit(ConfirmReset),
              "Reset",
            ),
            @html.button(
              class="secondary small",
              attrs=@html.Attrs::build().aria_label("Keep project"),
              on_click=emit(CancelReset),
              "Keep",
            ),
          ]),
        ],
      )
    } else {
      @html.nothing
    },
  ])
}

///|
fn explorer_props(model : Model) -> @explorer.Props {
  {
    data: model.document.inspection(),
    selected: model.selected,
    query: model.query,
    collapsed_modules: model.collapsed_modules,
    raw: model.explorer_raw,
    original_yaml: match model.document.original() {
      Some(original) if original.codec.format() is @data.ModelFormat::YAML =>
        Some(@utf8.decode(original.copy_bytes()[:], ignore_bom=true)) catch {
          _ => None
        }
      _ => None
    },
  }
}

///|
fn capability_runtime(result : Json) -> CapabilityRuntime {
  guard @capabilities.Evaluator::from_json(field(result, "capabilityEvaluator"))
    is Some(evaluator) else {
    return Unavailable
  }
  if field(result, "connected") == Json::boolean(true) {
    if field(result, "executionsAvailable") == Json::boolean(true) &&
      field(result, "nativeSession") != Json::boolean(true) &&
      text(result, "capabilityRuntime") == "connected" {
      Connected(evaluator)
    } else {
      Unavailable
    }
  } else if field(result, "nativeSession") == Json::boolean(true) {
    if field(result, "executionsAvailable") == Json::boolean(true) &&
      text(result, "capabilityRuntime") == "native" {
      Native(evaluator)
    } else {
      Unavailable
    }
  } else if field(result, "executionsAvailable") != Json::boolean(true) {
    Standalone(evaluator)
  } else {
    Unavailable
  }
}

///|
fn capability_evaluator(model : Model) -> @capabilities.Evaluator? {
  match model.capability_runtime {
    Connected(evaluator) =>
      if model.connected && model.executions_available {
        Some(evaluator)
      } else {
        None
      }
    Standalone(evaluator) =>
      if model.connected || model.executions_available {
        None
      } else {
        Some(evaluator)
      }
    Native(evaluator) =>
      if !model.connected && model.executions_available {
        Some(evaluator)
      } else {
        None
      }
    Unavailable => None
  }
}

///|
fn capability_descriptions(model : Model) -> Bool {
  capability_evaluator(model) is Some(_)
}

///|
fn checking_available(model : Model) -> Bool {
  guard model.evaluation_runtime.is_typed() &&
    capability_evaluator(model) is Some(evaluator) else {
    return false
  }
  @capabilities.supports_checks(
    field(model.document.inspection(), "capabilityEvaluations"),
    evaluator,
    model.selected
    .strip_prefix("value|")
    .unwrap_or(model.selected[:])
    .to_owned(),
  )
}

///|
fn evaluation_profile(
  data : Json,
  selected : String,
  typed : Bool,
  capabilities~ : Bool = false,
) -> Json {
  let profiles = if typed {
    let manifest = field(
      data,
      if capabilities {
        "capabilityEvaluations"
      } else {
        "typedEvaluations"
      },
    )
    let entry = field(
      field(manifest, "entries"),
      selected.strip_prefix("value|").unwrap_or(selected[:]).to_owned(),
    )
    if entry == Json::null() {
      // A bounded capability description inventory must not remove a previously
      // supported strict entry from the complete generated manifest. It grants
      // no permissive offer; checking_available checks the selected entry and evaluator.
      let legacy = field(
        field(field(data, "typedEvaluations"), "entries"),
        selected.strip_prefix("value|").unwrap_or(selected[:]).to_owned(),
      )
      if capabilities && field(legacy, "supported") == Json::boolean(true) {
        return legacy
      }
      return object([
        ("supported", Json::boolean(false)),
        (
          "reason",
          Json::string(
            if text(manifest, "reason") != "" {
              text(manifest, "reason")
            } else {
              "Typed evaluation requires a public entry with supported input and output types."
            },
          ),
        ),
      ])
    }
    field(manifest, "entries")
  } else {
    field(data, "evaluations")
  }
  let profile = field(
    profiles,
    selected.strip_prefix("value|").unwrap_or(selected[:]).to_owned(),
  )
  if profile == Json::null() {
    object([
      ("supported", Json::boolean(false)),
      ("reason", Json::string("Only public functions can be evaluated.")),
    ])
  } else {
    profile
  }
}

///|
/// Keep exact JSON number lexemes out of the JavaScript object transport.
fn model_source(data : Json) -> String {
  if text(data, "irSource") != "" {
    text(data, "irSource")
  } else {
    field(data, "ir").stringify()
  }
}

///|
fn default_arguments(
  profile : Json,
  mode : @evaluation.InputMode,
  typed : Bool,
) -> String {
  let json = pretty(field(profile, "default").stringify())
  if mode == @evaluation.Ion {
    @arguments.convert_inputs(profile, json, false, true, typed) catch {
      _ => "[]"
    }
  } else {
    json
  }
}

///|
fn host_execution_pending(model : Model) -> Bool {
  model.host_submitting ||
  (
    model.host_execution != Json::null() &&
    text(model.host_execution, "state") != "terminal"
  )
}

///|
fn host_execution_status(execution : Json) -> String {
  if execution == Json::null() {
    return ""
  }
  "Host · " +
  text(execution, "state") +
  (if field(execution, "cancelRequested") == Json::boolean(true) {
    " · cancellation acknowledged"
  } else {
    ""
  }) +
  (if field(execution, "connected") == Json::boolean(false) {
    " · disconnected"
  } else {
    ""
  })
}

///|
fn host_execution_disconnected(model : Model) -> Bool {
  model.host_execution != Json::null() &&
  field(model.host_execution, "connected") == Json::boolean(false)
}

///|
fn host_execution_blocks_replacement(model : Model) -> Bool {
  host_retention(model) != @document.HostRetention::Idle
}

///|
fn host_retention(model : Model) -> @document.HostRetention {
  if model.submission_unknown {
    @document.HostRetention::UnknownSubmission
  } else if model.host_submitting {
    @document.HostRetention::Submitting
  } else if host_execution_disconnected(model) {
    @document.HostRetention::Disconnected
  } else if host_execution_pending(model) {
    @document.HostRetention::Running
  } else {
    @document.HostRetention::Idle
  }
}

// Project explorer, shortcuts and the command palette. The explorer and the palette are pure state machines; these
// helpers give them the workbench's data and turn their effects into commands.

///|
let busy_reason = "Wait for the running operation to finish"

///|
fn explorer_env(model : Model) -> @project_files.Env {
  {
    project: active_project(model),
    rules: file_rules(model, model.language),
    counts: model.problem_counts,
    busy: model.busy,
    samples: sample_entries(model),
    sample_reason: sample_reason(model),
  }
}

///|
fn language_name(model : Model, language : String) -> String {
  match text(frontend(model, language), "displayName") {
    "" => language
    name => name
  }
}

///|
fn focus_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => focus_now(id), kind=@cmd.after_render)
}

///|
/// Turns the explorer's effects into focus moves and work outside the project.
fn explorer_effects(
  model : Model,
  effects : Array[@project_files.Effect],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let mut model = model
  let cmds : Array[@cmd.Cmd] = []
  for effect in effects {
    match effect {
      FocusRow(item) =>
        cmds.push(focus_after_render(@project_files.row_id(item)))
      FocusInput(start, end) =>
        cmds.push(
          @cmd.custom_cmd(
            _ => focus_selecting(@project_files.input_id, start, end),
            kind=@cmd.after_render,
          ),
        )
      FocusName => cmds.push(focus_after_render(@project_files.name_id))
      FocusConfirm => cmds.push(focus_after_render(@project_files.confirm_id))
      FocusMenu(index) =>
        cmds.push(focus_after_render(@project_files.menu_item_id(index)))
      FocusEditor =>
        cmds.push(@cmd.custom_cmd(_ => focus_editor(), kind=@cmd.after_render))
      Copy(path) =>
        cmds.push(
          @cmd.custom_cmd(scheduler => {
            copy_text(path, copied => scheduler.add(emit(Copied(path, copied))))
          }),
        )
      ShowProblems(_) =>
        if model.panel.size == @bottom_panel.Collapsed ||
          model.panel.tab != @bottom_panel.Diagnostics {
          let (panel, _) = model.panel.update(
            @bottom_panel.Activate(@bottom_panel.Diagnostics),
          )
          model = { ..model, panel, }
        }
      ImportFolder =>
        cmds.push(
          @cmd.custom_cmd(scheduler => {
            pick_folder(reply => scheduler.add(emit(FolderPicked(reply))))
          }),
        )
      AskReset => {
        model = { ..model, reset_asking: true, }
        cmds.push(focus_after_render("reset-confirm"))
      }
      ShowPalette => {
        let (opened, cmd) = open_palette(model, Show(">"), emit)
        model = opened
        cmds.push(cmd)
      }
      LoadSample(id) => {
        let (opened, cmd) = update_core(model, Sample(id), emit)
        model = opened
        cmds.push(cmd)
      }
    }
  }
  (model, @cmd.batch(cmds))
}

///|
/// Shows the project in Try Morphir (compile layout, sidebar open) and gives the explorer one action.
fn in_project_view(
  model : Model,
  action : @project_files.Action,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let shown = remember(model, {
    ..model,
    doc: Source,
    worksheet: false,
    layout: model.layout.apply(Reveal(Files)),
  })
  let shown = match action {
    Open(path) => {
      let (files_edit, _, _) = @project_files.apply(
        shown.files_edit,
        explorer_env(shown),
        Reveal(path),
      )
      { ..shown, files_edit, }
    }
    _ => shown
  }
  // A filter that hides the target row would hide its inline rename, delete or new-file input.
  let target = match action {
    Open(path) => path
    _ => active_project(shown).active
  }
  let shown = if @project_files.matches_filter(target, shown.files_edit.filter) {
    shown
  } else {
    { ..shown, files_edit: { ..shown.files_edit, filter: "", }, }
  }
  update_core(shown, Files(action), emit)
}

///|
fn runnable(model : Model) -> Bool {
  model.worksheet || (!model.connected && model.language == "scheme")
}

///|
/// Whether the package exposes the open file, when the language keeps packages and the file is a module.
fn active_exposure(model : Model) -> Bool? {
  let project = active_project(model)
  guard file_rules(model, model.language).add_reason() is None else {
    return None
  }
  project.file_module(project.active).map(found => found.1)
}

///|
/// The commands the palette lists now. Commands that do not apply here are left out; commands that apply but cannot
/// run now are listed with their reason.
fn palette_commands(model : Model) -> Array[@palette.Command] {
  let commands : Array[@palette.Command] = []
  fn add(
    id : @keys.CommandId,
    title : String,
    category : String,
    reason : String,
  ) -> Unit {
    commands.push({ id, title, category, enabled: reason == "", reason, })
  }

  let busy = if model.busy { busy_reason } else { "" }
  let in_workspace = model.screen is Workspace && model.active is Some(_)
  let local_reason = if model.connected {
    "A connected host provides one workspace; use Browser local for more"
  } else {
    ""
  }
  // Workspace entry points, from anywhere.
  add(ShowGettingStarted, "Show getting started", "Workspace", "")
  if model.registry.entries
    .iter()
    .any(e => {
      (e.saved || model.parked.contains(e.id)) && Some(e.id) != model.active
    }) ||
    (model.active is Some(_) && !in_workspace) {
    add(SwitchWorkspace, "Switch workspace…", "Workspace", "")
  }
  if model.active is Some(id) && !model.connected {
    add(
      CloseWorkspace,
      "Close workspace",
      "Workspace",
      closing_blocked(model, id).unwrap_or(""),
    )
  }
  add(TryIdea, "Try an idea…", "Workspace", local_reason)
  add(OpenWorkspace, "Open a workspace…", "Workspace", local_reason)
  add(CreateWorkspace, "Create a workspace…", "Workspace", local_reason)
  add(
    ExploreModel,
    "Explore a model…",
    "Workspace",
    if local_reason == "" {
      busy
    } else {
      local_reason
    },
  )
  if !in_workspace {
    add(TogglePanel, "Toggle panel", "View", "")
    return commands
  }
  // Content of the active workspace.
  if !model.connected {
    if !holds(model, Intent) {
      add(AddIntent, "Add modeling intent", "Workspace", "")
    }
    if !holds(model, ConceptualModel) {
      add(AddConceptualModel, "Add a conceptual model", "Workspace", "")
    }
    if !holds(model, SourceProject) {
      add(AddSourceProject, "Add a source project", "Workspace", "")
    }
    if !holds(model, ModelDocument) && !holds(model, SourceProject) {
      add(
        ImportModel,
        "Import a model into this workspace…",
        "Workspace",
        busy,
      )
    }
  }
  let docs = documents_of(model)
  for
    entry in [
      (@workspace.Document::Source, @keys.CommandId::ShowSource, "Show source"),
      (Model, ShowModel, "Show model"),
      (IntentDraft, ShowIntent, "Show modeling intent"),
      (ConceptDraft, ShowConcept, "Show conceptual model"),
    ] {
    if docs.contains(entry.0) && model.doc != entry.0 {
      add(entry.1, entry.2, "View", "")
    }
  }
  add(
    TogglePrimarySidebar,
    if model.layout.is_open(Primary) {
      "Hide left sidebar"
    } else {
      "Show left sidebar"
    },
    "View",
    "",
  )
  add(
    ToggleSecondarySidebar,
    if model.layout.is_open(Secondary) {
      "Hide right sidebar"
    } else {
      "Show right sidebar"
    },
    "View",
    "",
  )
  let views = views_of(model)
  for
    entry in [
      (@shell.View::Files, @keys.CommandId::MoveFiles),
      (Models, MoveModels),
      (Generated, MoveGenerated),
      (Ideas, MoveIdeas),
    ] {
    if views.contains(entry.0) {
      add(
        entry.1,
        "Move " +
        entry.0.title() +
        " to " +
        model.layout.side_of(entry.0).other().destination(),
        "View",
        "",
      )
    }
  }
  if views.contains(Generated) {
    add(ShowGeneratedFiles, "Show generated files", "View", "")
  }
  guard docs.contains(Source) else {
    add(TogglePanel, "Toggle panel", "View", "")
    return commands
  }
  let projects = !model.connected && holds(model, SourceProject)
  let rules = file_rules(model, model.language)
  add(
    Compile,
    "Compile",
    "Build",
    if model.worksheet {
      "Switch to Compile & inspect to compile the project"
    } else if !model.available {
      "No language is available yet"
    } else {
      busy
    },
  )
  if runnable(model) {
    add(
      Run,
      if model.worksheet {
        "Run worksheet"
      } else {
        "Compile & run"
      },
      "Build",
      busy,
    )
  }
  if !model.worksheet {
    add(SetTarget, "Set generation target…", "Build", busy)
    add(SwitchLanguage, "Switch language…", "Project", busy)
    if !model.connected &&
      !items(field(frontend(model, model.language), "profiles")).is_empty() {
      add(SelectProfile, "Select source profile…", "Project", busy)
      add(ShowProfileDetails, "Show source profile details", "Project", "")
    }
  }
  if projects {
    add(GoToFile, "Go to file…", "Go", "")
    add(
      NewFile,
      "New file…",
      "File",
      match rules.add_reason() {
        Some(reason) => reason
        None => busy
      },
    )
    add(RenameFile, "Rename file…", "File", busy)
    add(DeleteFile, "Delete file", "File", busy)
    add(CopyPath, "Copy path of the open file", "File", "")
    match active_exposure(model) {
      Some(true) => add(ToggleExposed, "Stop exposing module", "Project", "")
      Some(false) => add(ToggleExposed, "Expose module", "Project", "")
      None => ()
    }
    if rules.add_reason() is None {
      add(RenamePackage, "Rename package…", "Project", "")
    }
    add(ImportFolder, "Import folder…", "Project", busy)
    add(ResetProject, "Reset project…", "Project", busy)
    add(CollapseFolders, "Collapse folders", "View", "")
    add(ShowExplorer, "Show project explorer", "View", "")
    add(
      SwitchLayout,
      if model.worksheet {
        "Switch to Compile & inspect"
      } else {
        "Switch to Worksheet"
      },
      "View",
      "",
    )
  }
  if selected_binary_ion(model) is Some(path) {
    add(ViewIonText, "View as Ion text: " + path, "Generated", busy)
  }
  // One entry for each example and sample, from the list the explorer's project menu also reads.
  for sample in sample_entries(model) {
    add(
      LoadSample(sample.0),
      "Open sample: " + sample.1,
      "Sample",
      sample_reason(model),
    )
  }
  add(TogglePanel, "Toggle panel", "View", "")
  commands
}

///|
/// The second list of a command: languages, targets or samples.
fn palette_choices(model : Model) -> Array[@palette.Choice] {
  let current = fn(value : String, chosen : String) {
    if value == chosen {
      "current"
    } else {
      ""
    }
  }
  match model.palette.choosing {
    Some((SwitchLanguage, _)) =>
      items(field(model.catalog, "frontends")).map(item => @palette.Choice::{
        value: text(item, "languageId"),
        label: text(item, "displayName"),
        detail: current(text(item, "languageId"), model.language),
      })
    Some((SwitchWorkspace, _)) =>
      model.registry.entries
      .filter(e => {
        e.saved || model.parked.contains(e.id) || Some(e.id) == model.active
      })
      .map(e => @palette.Choice::{
        value: e.id.to_string(),
        label: e.name.to_string(),
        detail: if Some(e.id) == model.active {
          "current"
        } else if model.parked.contains(e.id) {
          "open"
        } else {
          e.preset.label()
        },
      })
    Some((SelectProfile, _)) =>
      items(field(frontend(model, model.language), "profiles")).map(item => @palette.Choice::{
        value: text(item, "id"),
        label: text(item, "displayName"),
        detail: current(text(item, "id"), model.source_profile),
      })
    Some((SetTarget, _)) =>
      [
        @palette.Choice::{
          value: "",
          label: "No generation",
          detail: current("", model.target),
        },
        ..items(field(model.catalog, "targets")).map(item => @palette.Choice::{
          value: text(item, "target"),
          label: text(item, "displayName"),
          detail: current(text(item, "target"), model.target),
        }),
      ]
    _ => []
  }
}

///|
fn palette_entries(model : Model) -> Array[@palette.Entry] {
  @palette.entries(
    model.palette,
    files=if model.connected {
      []
    } else {
      active_project(model).files.map(f => f.path)
    },
    commands=palette_commands(model),
    choices=palette_choices(model),
    mac=model.mac,
  )
}

///|
/// Opens the palette. From the page it first keeps the focus so Escape can return to it; a palette that asks a
/// second question keeps the focus it kept for the first.
fn open_palette(
  model : Model,
  action : @palette.Action,
  emit : @cmd.Emit[Msg],
  remember~ : Bool = true,
) -> (Model, @cmd.Cmd) {
  let keep = if remember && !model.palette.open {
    @cmd.custom_cmd(_ => remember_focus())
  } else {
    @cmd.none
  }
  let (opened, cmd) = update_core(model, Palette(action), emit)
  (opened, @cmd.batch([keep, cmd]))
}

///|
/// Runs a command from a shortcut, the palette or a menu. A command that cannot run now does nothing.
fn run_command(
  model : Model,
  command : @keys.CommandId,
  emit : @cmd.Emit[Msg],
  from_palette~ : Bool = false,
) -> (Model, @cmd.Cmd) {
  let available = palette_commands(model)
    .iter()
    .find_first(c => c.id == command)
  let runs = match available {
    Some(entry) => entry.enabled
    // Commands the palette does not list, such as Show all commands, always run.
    None => command is (ShowCommands | GoToFile | ContextMenu)
  }
  guard runs else { return (model, @cmd.none) }
  let active = active_project(model).active
  match command {
    Compile => update_core(model, Request("compile"), emit)
    Run =>
      update_core(
        model,
        Request(if model.worksheet { "worksheet" } else { "run" }),
        emit,
      )
    GoToFile => open_palette(model, Show(""), emit, remember=!from_palette)
    ShowCommands => open_palette(model, Show(">"), emit, remember=!from_palette)
    SwitchLanguage =>
      open_palette(
        model,
        Ask(SwitchLanguage, "Switch language"),
        emit,
        remember=!from_palette,
      )
    SetTarget =>
      open_palette(
        model,
        Ask(SetTarget, "Set generation target"),
        emit,
        remember=!from_palette,
      )
    LoadSample(id) => update_core(model, Sample(id), emit)
    ViewIonText =>
      match selected_binary_ion(model) {
        Some(path) => {
          let (shown, cmd) = start_decode(
            { ..model, doc: Source, worksheet: false, generated: true, },
            path,
            emit,
          )
          (shown, cmd)
        }
        None => (model, @cmd.none)
      }
    NewFile => in_project_view(model, StartAdd(None), emit)
    RenameFile => in_project_view(model, StartRename(File(active)), emit)
    DeleteFile => in_project_view(model, StartDelete(File(active)), emit)
    CopyPath =>
      (
        model,
        @cmd.custom_cmd(scheduler => {
          copy_text(active.to_string(), copied => {
            scheduler.add(emit(Copied(active.to_string(), copied)))
          })
        }),
      )
    CollapseFolders => in_project_view(model, CollapseAll, emit)
    ToggleExposed =>
      in_project_view(
        model,
        Exposed(active, active_exposure(model) == Some(false)),
        emit,
      )
    RenamePackage => in_project_view(model, StartNaming, emit)
    ImportFolder => update_core(model, PickFolder, emit)
    ResetProject => {
      let (shown, cmd) = in_project_view(model, Focus(File(active)), emit)
      (
        { ..shown, reset_asking: true, },
        @cmd.batch([cmd, focus_after_render("reset-confirm")]),
      )
    }
    TogglePanel =>
      update_core(
        model,
        Panel(
          if model.panel.size == @bottom_panel.Collapsed {
            @bottom_panel.Open
          } else {
            @bottom_panel.Collapse
          },
        ),
        emit,
      )
    SwitchLayout => update_core(model, Layout(!model.worksheet), emit)
    ShowSource => update_core(model, ShowDocument(Source), emit)
    ShowModel => update_core(model, ShowDocument(Model), emit)
    ShowIntent => update_core(model, ShowDocument(IntentDraft), emit)
    ShowConcept => update_core(model, ShowDocument(ConceptDraft), emit)
    ShowGettingStarted => update_core(model, ShowStart, emit)
    SwitchWorkspace =>
      open_palette(
        model,
        Ask(SwitchWorkspace, "Switch workspace"),
        emit,
        remember=!from_palette,
      )
    CloseWorkspace =>
      match model.active {
        Some(id) => update_core(model, CloseWorkspace(id), emit)
        None => (model, @cmd.none)
      }
    CreateWorkspace => start_with(model, CreateChoices, emit)
    TryIdea => start_with(model, Idea, emit)
    OpenWorkspace => start_with(model, OpenChoices, emit)
    ExploreModel => start_with(model, ExploreChoices, emit)
    AddIntent => update_core(model, AddContent(Intent), emit)
    AddConceptualModel => update_core(model, AddContent(ConceptualModel), emit)
    AddSourceProject => update_core(model, AddContent(SourceProject), emit)
    ImportModel => update_core(model, AddContent(ModelDocument), emit)
    TogglePrimarySidebar => update_core(model, Shell(Toggle(Primary)), emit)
    ToggleSecondarySidebar => update_core(model, Shell(Toggle(Secondary)), emit)
    MoveFiles => move_view(model, Files, emit)
    MoveModels => move_view(model, Models, emit)
    MoveGenerated => move_view(model, Generated, emit)
    MoveIdeas => move_view(model, Ideas, emit)
    ShowGeneratedFiles => update_core(model, ShowGenerated, emit)
    SelectProfile =>
      open_palette(
        model,
        Ask(SelectProfile, "Select source profile"),
        emit,
        remember=!from_palette,
      )
    ShowProfileDetails =>
      (
        { ..model, doc: Source, worksheet: false, },
        @cmd.custom_cmd(_ => open_profile_details(), kind=@cmd.after_render),
      )
    ShowExplorer => {
      let (shown, cmd) = in_project_view(model, Focus(File(active)), emit)
      let row = match shown.files_edit.current(explorer_env(shown)) {
        Some(item) => focus_after_render(@project_files.row_id(item))
        None => @cmd.none
      }
      (shown, @cmd.batch([cmd, row]))
    }
    ContextMenu => (model, @cmd.none)
  }
}

///|
/// Shows getting started with one of its choices open.
fn start_with(
  model : Model,
  panel : StartPanel,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (shown, focus) = update_core(model, ShowStart, emit)
  let (opened, cmd) = update_core(
    { ..shown, start: { ..shown.start, panel: Closed, }, },
    StartPanel(panel),
    emit,
  )
  (opened, @cmd.batch([focus, cmd]))
}

///|
/// Moves a view to the other sidebar and opens it there, so the moved view is in sight.
fn move_view(
  model : Model,
  view : @shell.View,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let side = model.layout.side_of(view).other()
  let (moved, cmd) = update_core(model, Shell(Move(view, side)), emit)
  ({ ..moved, layout: moved.layout.apply(Reveal(view)), }, cmd)
}

///|
/// Opens the source profile details and moves the focus to them.
extern "js" fn open_profile_details() =
  #|() => { const d = document.querySelector('.profile-details details'); if (d) { d.open = true; d.querySelector('summary')?.focus(); } }

// Failure details for the tool panel.

///|
fn plural_files(count : Int32) -> String {
  count.to_string() + (if count == 1 { " file" } else { " files" })
}

///|
/// What a failed request ran and how it failed, for the panel's details and the Copy details report. The code and
/// stage are the reply's own; a refused generation names its first problem's code.
fn failure_detail(
  model : Model,
  operation : String,
  request_id : Int32,
  revision : Int32,
  took : String,
  result : Json,
) -> @bottom_panel.Failure {
  let context : Array[(String, String)] = []
  match operation {
    "worksheet" => {
      context.push(("Language", "Scheme worksheet"))
      context.push(("Worksheet revision", revision.to_string()))
    }
    "evaluate" | "resume-execution" => {
      context.push(("Function", entry_label(model, model.evaluation_entry)))
      context.push(
        (
          "Runtime",
          if model.evaluation_host_execution {
            "host typed invocation"
          } else if model.evaluation_runtime.is_typed() {
            "typed invocation"
          } else {
            "local Scheme"
          },
        ),
      )
      context.push(("Inputs revision", revision.to_string()))
    }
    "decode-ion" => {
      let file = @generated.selected(
        model.output,
        model.generated_state.selected,
      )
      context.push(("File", text(file, "path")))
      context.push(
        (
          "Size",
          match @generated.binary_size(file) {
            Some(bytes) => bytes.to_string() + " bytes"
            None => ""
          },
        ),
      )
      context.push(("Generated by", "target " + model.target))
    }
    "compile" | "run" => {
      let project = active_project(model)
      context.push(("Language", language_name(model, model.language)))
      if !model.connected {
        context.push(
          (
            "Profile",
            project.profile
            .map(p => p.to_string())
            .unwrap_or(model.source_profile),
          ),
        )
        context.push(
          ("Provider", project.provider.map(p => p.to_string()).unwrap_or("")),
        )
      }
      context.push(
        ("Target", if model.target == "" { "none" } else { model.target }),
      )
      if !model.connected {
        context.push(
          (
            "Project",
            project.name.to_string() +
            " (" +
            plural_files(project.files.length()) +
            ")",
          ),
        )
      }
      context.push(("Source revision", revision.to_string()))
    }
    _ => ()
  }
  context.push(("Duration", took))
  let generation = match items(field(result, "generationDiagnostics")) {
    [first, ..] => text(first, "code")
    [] => ""
  }
  let failed = field(result, "success") != Json::boolean(true)
  {
    request_id,
    operation: operation_label(operation),
    code: if text(result, "code") != "" {
      text(result, "code")
    } else if failed {
      ""
    } else {
      generation
    },
    stage: if text(result, "stage") != "" {
      text(result, "stage")
    } else if failed {
      ""
    } else {
      "generation"
    },
    message: if failed {
      text(result, "message")
    } else {
      text(result, "generationMessage")
    },
    context,
    raw: @bottom_panel.redacted(result).stringify(indent=2),
  }
}

// Generated files.

///|
/// Turns the generated files' effects into a decode request, the clipboard, a download and focus moves.
fn generated_effects(
  model : Model,
  effects : Array[@generated.Effect],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let mut model = model
  let cmds : Array[@cmd.Cmd] = []
  for effect in effects {
    match effect {
      RequestIonText(path) => {
        let (started, cmd) = start_decode(model, path, emit)
        model = started
        cmds.push(cmd)
      }
      Copy(path) =>
        cmds.push(
          @cmd.custom_cmd(scheduler => {
            copy_text(path, copied => scheduler.add(emit(Copied(path, copied))))
          }),
        )
      DownloadFile(path) => {
        // A download from a file's menu leaves the selection and the preview as they are.
        let (after, cmd) = start_download(
          model,
          [@generated.selected(model.output, path)],
          false,
        )
        model = after
        cmds.push(cmd)
      }
      FocusMenu(index) =>
        cmds.push(
          focus_after_render(
            @context_menu.item_id(@generated.menu_id_prefix, index),
          ),
        )
      FocusFile(path) => cmds.push(focus_after_render(@generated.file_id(path)))
    }
  }
  (model, @cmd.batch(cmds))
}

///|
/// Starts a download and logs the request. The browser or native dialog owns saving.
fn start_download(
  model : Model,
  files : Array[Json],
  project : Bool,
) -> (Model, @cmd.Cmd) {
  let message = download_generated(Json::array(files).stringify(), project)
  let model = note(
    model,
    "Download",
    if message == "" {
      @bottom_panel.Info
    } else {
      @bottom_panel.Error
    },
    if message != "" {
      message
    } else if project {
      "Download started: morphir-project.zip with " +
      files.length().to_string() +
      " generated files"
    } else {
      "Download started: " + text(files[0], "path")
    },
  )
  (
    {
      ..model,
      status: if message == "" {
        "Generated file download started"
      } else {
        message
      },
    },
    @cmd.none,
  )
}

///|
/// Decodes a generated binary Ion file to text in the worker, as a request: the busy rule, cancellation and late replies
/// work as for a compile.
fn start_decode(
  model : Model,
  path : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if model.busy {
    let message = "Another operation is running; view the Ion text when it finishes"
    return (
      {
        ..note(model, "View as Ion text", @bottom_panel.Warning, message),
        status: message,
      },
      @cmd.none,
    )
  }
  let file = @generated.selected(model.output, path)
  guard text(file, "path") == path && @generated.is_binary_ion(file) else {
    return (model, @cmd.none)
  }
  if model.connected {
    // A connected host has no decode-ion operation; only the local worker decodes.
    let message = "Ion text is decoded by the browser-local worker only"
    return (
      {
        ..note(model, "View as Ion text", @bottom_panel.Warning, message),
        status: message,
      },
      @cmd.none,
    )
  }
  let request_id = model.request_id + 1
  let model = note(
    model,
    "View as Ion text",
    @bottom_panel.Info,
    "Started request " + request_id.to_string() + " · decoding " + path,
  )
  (
    {
      ..model,
      request_id,
      busy: true,
      started: now_ms(),
      generated: true,
      generated_state: { ..model.generated_state, selected: path, },
      status: "Decoding " + path + "…",
    },
    request_cmd(
      emit,
      request_id,
      model.output_revision,
      object([
        ("operation", Json::string("decode-ion")),
        ("path", Json::string(path)),
        ("source", field(file, "content")),
      ]),
    ),
  )
}

///|
/// The selected generated file when it is binary Ion and the local worker can decode it, for the palette's View
/// as Ion text.
fn selected_binary_ion(model : Model) -> String? {
  let file = @generated.selected(model.output, model.generated_state.selected)
  if !model.connected && @generated.is_binary_ion(file) {
    Some(text(file, "path"))
  } else {
    None
  }
}
