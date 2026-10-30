///|
extern "js" fn pick_notebook(receive : (String) -> Unit) =
  #| (receive) => globalThis.morphirWorkbench.pickNotebook(receive)

///|
fn notebook_source(model : Model) -> @worksheet.CapturedWorksheetSource raise {
  @worksheet.CapturedWorksheetSource::new(
    @worksheet.WorksheetId::parse(worksheet_source_id(model)),
    @worksheet.SourceRevision::new(model.worksheet_revision),
    model.worksheet_source,
  )
}

///|
fn notebook_problem(model : Model, message : String) -> (Model, @cmd.Cmd) {
  (
    {
      ..note(model, "Notebook", @bottom_panel.Warning, message),
      status: message,
    },
    @cmd.none,
  )
}

///|
fn notebook_open(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if !model.worksheet || !workspace_writable(model) || model.busy {
    return (model, @cmd.none)
  }
  let source = notebook_source(model) catch {
    error => return notebook_problem(model, error.to_string())
  }
  (
    model,
    @cmd.custom_cmd(scheduler => {
      pick_notebook(reply => scheduler.add(emit(NotebookPicked(source, reply))))
    }),
  )
}

///|
fn notebook_picked(
  model : Model,
  source : @worksheet.CapturedWorksheetSource,
  reply : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if !model.worksheet ||
    !workspace_writable(model) ||
    model.busy ||
    !worksheet_matches(model, source) {
    return notebook_problem(
      model, "Worksheet changed while choosing a notebook. Open it again.",
    )
  }
  try {
    let reply = @json.parse(reply)
    if field(reply, "cancelled") is True {
      return (model, @cmd.none)
    }
    if text(reply, "error") != "" {
      return notebook_problem(model, text(reply, "error"))
    }
    let imported = @notebook.import_notebook(
      text(reply, "content"),
      @notebook.Format::parse(text(reply, "format")),
    )
    let (changed, cmd) = update_core(model, Source(imported.source()), emit)
    let mut next = changed
    for cell in imported.skipped() {
      next = note(
        next,
        "Notebook",
        @bottom_panel.Warning,
        "Skipped " + cell.name() + ": " + cell.to_json().stringify(),
      )
    }
    let skipped = imported.skipped().length()
    let message = "Opened " +
      text(reply, "filename") +
      " as a worksheet" +
      (if skipped == 0 {
        ""
      } else {
        " · skipped " + skipped.to_string() + " cells"
      })
    ({ ..next, status: message, }, cmd)
  } catch {
    error =>
      notebook_problem(
        model,
        "Notebook could not be opened: " + error.to_string(),
      )
  }
}

///|
fn notebook_export(
  model : Model,
  format : @notebook.Format,
) -> (Model, @cmd.Cmd) {
  if !model.worksheet {
    return (model, @cmd.none)
  }
  try {
    let source = notebook_source(model)
    let report = match (format, model.worksheet_report) {
      (Ipynb, Some(report)) if worksheet_matches(model, report.source()) =>
        Some(report)
      _ => None
    }
    let exported = @notebook.export_notebook(source, format, report?)
    let path = "worksheet." + format.name()
    let error = download_generated(
      Json::array([
        { "path": path, "content": exported.content(), "binary": false },
      ]).stringify(),
      false,
    )
    if error != "" {
      return notebook_problem(model, error)
    }
    let message = "Downloaded " +
      path +
      (if report is Some(_) {
        " with current results"
      } else {
        " (source only)"
      })
    (
      {
        ..note(model, "Notebook", @bottom_panel.Info, message),
        status: message,
      },
      @cmd.none,
    )
  } catch {
    error =>
      notebook_problem(
        model,
        "Notebook could not be exported: " + error.to_string(),
      )
  }
}
