///|
fn receive_workspace(
  model : Model,
  request_id : Int32,
  revision : Int32,
  reply : Json,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let projects = items(field(reply, "projects"))
  let selected = current_project_path(model).to_string()
  let current = projects
    .iter()
    .find_first(p => {
      text(p, "path") == (if selected == "" { "." } else { selected })
    })
    .unwrap_or(Json::null())
  let result = project_model_result(model, field(current, "result"))
  let fields = match result {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields["artifacts"] = field(reply, "artifacts")
  fields["workspaceProjects"] = Json::array(projects)
  let combined = Json::object(fields)
  let (next, command) = if current == Json::null() {
    (
      {
        ..model,
        busy: false,
        output: combined,
        document: @document.State::new(),
        selected: "",
        evaluation_result: Json::null(),
        evaluation_entry: "",
        model_revision: model.model_revision + 1,
        evaluation_revision: model.evaluation_revision + 1,
      },
      @cmd.none,
    )
  } else {
    update_core(
      model,
      Receive(request_id, revision, "compile", combined.stringify()),
      emit,
    )
  }
  let mut next = { ..next, output: combined, output_revision: revision, }
  let mut passed = 0
  let mut failure = ""
  for project in projects {
    let result = field(project, "result")
    if text(project, "path") != text(current, "path") {
      next = reported(
        next,
        "Compile " + text(project, "name"),
        "source",
        revision,
        @bottom_panel.reply_diagnostics(result),
      )
    }
    if field(result, "success") == Json::boolean(true) {
      passed += 1
    } else {
      if failure == "" {
        failure = text(result, "message")
        if failure == "" {
          failure = text(result, "generationMessage")
        }
      }
      next = note(
        next,
        "Compile " + text(project, "name"),
        @bottom_panel.Error,
        text(result, "message"),
      )
    }
  }
  (
    {
      ..next,
      busy: false,
      status: "Compiled " +
      passed.to_string() +
      "/" +
      projects.length().to_string() +
      " projects" +
      (if failure == "" { "" } else { " · " + failure }),
    },
    command,
  )
}
