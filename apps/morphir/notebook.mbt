///|
enum NotebookOperation {
  Index
  Export
  Import
}

///|
fn NotebookOperation::command(self : NotebookOperation) -> String {
  match self {
    Index => "notebook"
    Export => "notebook.export"
    Import => "notebook.import"
  }
}

///|
fn notebook_operation(command : String) -> NotebookOperation? {
  match command {
    "notebook" => Some(Index)
    "notebook export" => Some(Export)
    "notebook import" => Some(Import)
    _ => None
  }
}

///|
/// Select only the error-result namespace. The complete command schema owns
/// syntax validation; this library parser leaves the remaining values opaque.
fn notebook_error_operation(argv : Array[String]) -> NotebookOperation? {
  let probe = @argparse.Command(
    "morphir",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[
      @argparse.FlagArg("json"),
      @argparse.FlagArg("json-lines"),
      @argparse.FlagArg("help", short='h'),
    ],
    positionals=[
      @argparse.PositionArg(
        "command",
        num_args=@argparse.ValueRange(upper=1),
        allow_hyphen_values=true,
      ),
      @argparse.PositionArg(
        "operation",
        num_args=@argparse.ValueRange(upper=1),
        allow_hyphen_values=true,
      ),
      @argparse.PositionArg(
        "tail",
        num_args=@argparse.ValueRange(lower=0),
        allow_hyphen_values=true,
      ),
    ],
  )
  let selected = probe.parse(argv~, env=Map([])) catch { _ => return None }
  guard selected.values.get("command") is Some(["notebook"]) else {
    return None
  }
  match selected.values.get("operation") {
    Some(["export"]) => Some(Export)
    Some(["import"]) => Some(Import)
    _ => Some(Index)
  }
}

///|
fn notebook_failure(
  operation : NotebookOperation,
  mode : OutputMode,
  code : String,
  message : String,
  status : Int32,
) -> Int32 {
  @platform.stderr(message + "\n")
  let report : Json = {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": operation.command(),
    "state": "failed",
    "exitCode": status,
    "diagnostics": [{ "code": code, "severity": "error", "message": message }],
    "error": { "code": code, "message": message },
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("result", report)
    Human => ()
  }
  status
}

///|
fn notebook_success(
  operation : NotebookOperation,
  mode : OutputMode,
  result : Json,
  diagnostics : Array[Json],
) -> Unit {
  let report : Json = {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": operation.command(),
    "state": "succeeded",
    "exitCode": 0,
    "diagnostics": diagnostics,
    "result": result,
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("result", report)
    Human =>
      if result is Object(fields) && fields.get("help") is Some(String(help)) {
        println(help)
      } else {
        println(result.stringify())
      }
  }
}

///|
enum NotebookPhase {
  Input(String)
  Convert(String)
  Evaluate(String)
  Write(String)
}

///|
fn NotebookPhase::path(self : NotebookPhase) -> String {
  match self {
    Input(path) | Convert(path) | Evaluate(path) | Write(path) => path
  }
}

///|
fn notebook_default_output(input : String, extension : String) -> String {
  let suffix = notebook_extension(input)
  input[:input.length() - suffix.length()].to_owned() + "." + extension
}

///|
fn notebook_format(path : String) -> @notebook.Format raise {
  let extension = notebook_extension(path)
  @notebook.Format::parse(
    if extension.is_empty() {
      ""
    } else {
      extension[1:].to_owned()
    },
  )
}

///|
fn notebook_command(cli : Cli, mode : OutputMode) -> Int32 {
  guard notebook_operation(cli.command) is Some(operation) else {
    abort("notebook command ownership")
  }
  if cli.help {
    notebook_success(operation, mode, { "help": cli.help_text }, [])
    return 0
  }
  let input = value(cli, "path")
  if input.is_empty() {
    return notebook_failure(
      operation, mode, "notebook.input_required", "A notebook or worksheet input file is required",
      2,
    )
  }
  let mut phase = NotebookPhase::Input(input)
  try {
    let given_output = value(cli, "output")
    let diagnostics : Array[Json] = []
    let (output, format, content, cells, skipped, evaluated) = match operation {
      Export => {
        let format = if value(cli, "format") != "" {
          @notebook.Format::parse(value(cli, "format"))
        } else if given_output != "" &&
          !notebook_extension(given_output).is_empty() {
          notebook_format(given_output)
        } else {
          @notebook.Ipynb
        }
        let evaluate = flag(cli, "evaluate")
        if evaluate {
          format.require_outputs()
        }
        if evaluate && !@platform.interruption_supported() {
          return notebook_failure(
            operation, mode, "worksheet.interruption_unavailable", "Worksheet evaluation needs an interruptible host; export without --evaluate is available",
            2,
          )
        }
        let output = if given_output == "" {
          notebook_default_output(input, format.name())
        } else {
          given_output
        }
        if notebook_output_is_input(input, output) {
          return notebook_failure(
            operation, mode, "notebook.output_is_input", "The output must differ from the input file",
            2,
          )
        }
        if evaluate {
          @platform.interruption_start()
        }
        defer (if evaluate { @platform.interruption_stop() })
        let captured : Result[Bytes, Error] = Ok(
          @platform.read_input(input, 1048576),
        ) catch {
          error => Err(error)
        }
        let bytes = match captured {
          Ok(bytes) => bytes
          Err(error) => {
            if @platform.interruption_requested() {
              return notebook_failure(
                operation, mode, "notebook.cancelled", "Notebook evaluation was cancelled",
                130,
              )
            }
            raise error
          }
        }
        let request = worksheet_capture(bytes, "notebook-source", 0)
        let report = if evaluate {
          phase = Evaluate(input)
          let started = @platform.monotonic_seconds()
          let report = request.evaluate(interrupted=fn() {
            if @platform.interruption_requested() {
              Some(@worksheet.Cancelled)
            } else if @platform.monotonic_seconds() - started >= 120.0 {
              Some(@worksheet.TimedOut)
            } else {
              None
            }
          })
          match report.completion() {
            Cancelled =>
              return notebook_failure(
                operation, mode, "notebook.cancelled", "Notebook evaluation was cancelled",
                130,
              )
            Failed(failure) if failure.code == "worksheet.timeout" =>
              return notebook_failure(
                operation, mode, "notebook.evaluation_timeout", "Notebook evaluation timed out",
                1,
              )
            _ => ()
          }
          Some(report)
        } else {
          None
        }
        phase = Convert(input)
        let exported = @notebook.export_notebook(
          request.source(),
          format,
          report?,
        )
        (output, format, exported.content(), exported.cells(), [], evaluate)
      }
      Import => {
        let format = notebook_format(input)
        let output = if given_output == "" {
          notebook_default_output(input, "scm")
        } else {
          given_output
        }
        if notebook_output_is_input(input, output) {
          return notebook_failure(
            operation, mode, "notebook.output_is_input", "The output must differ from the input file",
            2,
          )
        }
        let bytes = @platform.read_input(input, 8388608)
        let text = @utf8.decode(bytes[:])
        phase = Convert(input)
        let imported = @notebook.import_notebook(text, format)
        let skipped = imported.skipped()
        for cell in skipped {
          let details = cell.to_json()
          let message = "Skipped notebook cell " +
            cell.index().to_string() +
            " (" +
            cell.name() +
            "): " +
            details.stringify()
          @platform.stderr(message + "\n")
          diagnostics.push({
            "code": "notebook.skipped_cell",
            "severity": "warning",
            "path": input,
            "message": message,
          })
        }
        (
          output,
          format,
          imported.source(),
          imported.cells(),
          skipped.map(cell => cell.to_json()),
          false,
        )
      }
      Index =>
        return notebook_failure(
          operation, mode, "notebook.operation_required", "Choose notebook export or notebook import",
          2,
        )
    }
    phase = Write(output)
    @platform.write(output, content)
    notebook_success(
      operation,
      mode,
      {
        "outputPath": output,
        "format": format.name(),
        "cellCount": cells,
        "skippedCells": skipped,
        "evaluated": evaluated,
      },
      diagnostics,
    )
    0
  } catch {
    error => {
      let (code, message, status) = match error {
        @notebook.UnsupportedFormat(_) as error =>
          (@notebook.Invalid::code(error), @notebook.Invalid::message(error), 2)
        @notebook.OutputsRequireJupyter as error =>
          (@notebook.Invalid::code(error), @notebook.Invalid::message(error), 2)
        @notebook.StaleObservations as error =>
          (@notebook.Invalid::code(error), @notebook.Invalid::message(error), 2)
        @notebook.TooManyForms as error =>
          (@notebook.Invalid::code(error), @notebook.Invalid::message(error), 2)
        _ => {
          let (code, status) = match phase {
            Input(_) => ("notebook.read_failed", 2)
            Convert(_) => ("notebook.invalid_input", 2)
            Evaluate(_) => ("notebook.evaluation_failed", 1)
            Write(_) => ("notebook.write_failed", 1)
          }
          (code, phase.path() + ": " + @host.error_message(error), status)
        }
      }
      notebook_failure(operation, mode, code, message, status)
    }
  }
}

///|
fn notebook_output_is_input(input : String, output : String) -> Bool {
  fn absolute(text : String) -> String {
    if @platform.system_type() == "windows" {
      let path = @path_windows.Path(text)
      let path = if path.is_absolute() {
        path
      } else {
        @path_windows.Path(@platform.cwd()).join(path)
      }
      path.normalize().0
    } else {
      let path = @path_posix.Path(text)
      let path = if path.is_absolute() {
        path
      } else {
        @path_posix.Path(@platform.cwd()).join(path)
      }
      path.normalize().0
    }
  }
  absolute(input) == absolute(output)
}

///|
fn notebook_extension(text : String) -> StringView {
  if @platform.system_type() == "windows" {
    @path_windows.Path(text).extname()
  } else {
    @path_posix.Path(text).extname()
  }
}
