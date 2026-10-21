///|
fn project_model_result(model : Model, result : Json) -> Json {
  let selected = items(field(result, "units"))
    .iter()
    .find_first(unit => {
      model.workspace_files.opened() == Some(text(unit, "source"))
    })
  guard selected is Some(Object(unit)) else { return result }
  let fields = unit.copy()
  for
    key in [
      "success", "artifacts", "generated", "generationWarnings", "generationDiagnostics",
      "generationMessage",
    ] {
    if field(result, key) != Json::null() {
      fields[key] = field(result, key)
    }
  }
  if text(Json::object(unit), "source") == text(result, "source") &&
    field(result, "value") != Json::null() {
    fields["value"] = field(result, "value")
  }
  Json::object(fields)
}

///|
/// Cached results belong to project paths. A file in another project changes the model used by evaluation.
fn follow_current_project(before : Model, next : Model) -> Model {
  let same_project = (before.workspace_files.current() catch { _ => None }) ==
    (next.workspace_files.current() catch { _ => None })
  if host_execution_blocks_replacement(next) ||
    (
      same_project &&
      before.workspace_files.opened() == next.workspace_files.opened()
    ) {
    return next
  }
  let projects = items(field(next.output, "workspaceProjects"))
  let current = next.workspace_files.current() catch { _ => None }
  let path = current.map(p => p.to_string()).unwrap_or("")
  let found = projects
    .iter()
    .find_first(p => {
      current is Some(_) &&
      text(p, "path") == (if path == "" { "." } else { path })
    })
  let result = found
    .map(project => field(project, "result"))
    .unwrap_or(Json::null())
  let selected = project_model_result(next, result)
  // Workspace-level notes keep the last source model within the current project.
  if same_project && selected == result {
    return next
  }
  let result = selected
  let fresh = next.output_revision == next.revision
  let fields = match result {
    Object(fields) if fresh => fields.copy()
    _ => Map([])
  }
  fields["workspaceProjects"] = field(next.output, "workspaceProjects")
  fields["artifacts"] = field(next.output, "artifacts")
  let document = if field(result, "ir") != Json::null() && fresh {
    next.document.replace(result) catch {
      _ => @document.State::new()
    }
  } else {
    @document.State::new()
  }
  {
    ..next,
    output: Json::object(fields),
    document,
    selected: "",
    query: "",
    collapsed_modules: [],
    evaluation_result: Json::null(),
    evaluation_entry: "",
    model_revision: next.model_revision + 1,
    evaluation_revision: next.evaluation_revision + 1,
  }
}
