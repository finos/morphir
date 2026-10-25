///|
/// The compile interface selects the existing discovery/planning/publication path.
/// It cannot select arbitrary pipeline components or generation backends.
fn compilation_cli(cli : Cli) -> Cli raise {
  if flag(cli, "types-only") {
    raise @config.Invalid("compile.types_only_unsupported")
  }
  let version = value(cli, "version", fallback="4")
  if !["4", "4.0.0", "4.0.0-draft"].contains(version) {
    raise @config.Invalid(
      "compile.unsupported_version: only draft IR 4 is supported",
    )
  }
  let language = value(cli, "language", fallback="moonbit")
  let (provider, profile) = match language {
    "moonbit" => (@moonbit_frontend.PROVIDER, "moonbit-model-stable-v1")
    "elm" => (@elm_frontend.PROVIDER, "library-origins")
    _ => raise @config.Invalid("compile.unsupported_language: " + language)
  }
  let format = value(cli, "model-format", fallback="ion-binary")
  if !["ion-binary", "ion-text", "morphir-json"].contains(format) {
    raise @config.Invalid("compile.unsupported_model_format: " + format)
  }
  let input = value(cli, "input")
  if input != "" && value(cli, "path") != "" {
    raise @config.Invalid("compile.conflicting_input")
  }
  let entries = cli.entries.copy()
  if input != "" {
    entries["path"] = [input]
  }
  entries["frontend"] = [language]
  entries["frontend-provider"] = [value(cli, "provider", fallback=provider)]
  entries["frontend-profile"] = [value(cli, "profile", fallback=profile)]
  entries["backend"] = ["checkpoint"]
  entries["checkpoint-format"] = [format]
  let flags = cli.flags.copy()
  flags["log"] = flag(cli, "log") || connected_supported()
  { ..cli, entries, flags, }
}

///|
fn compilation_result(
  result : Json,
  mode : OutputMode,
  cancelled~ : Bool = false,
) -> Unit {
  guard result is Object(fields) else { return }
  let success = fields.get("successful") == Some(Json::boolean(true))
  let diagnostics = fields.get("diagnostics").unwrap_or(Json::array([]))
  let report : Map[String, Json] = Map::from_array([
    ("profile", Json::string("morphir/command-result")),
    ("contractVersion", Json::string("0.1.0")),
    ("command", Json::string("compile")),
    ("state", Json::string(if success { "succeeded" } else { "failed" })),
    (
      "exitCode",
      Json::number(if success { 0.0 } else if cancelled { 130.0 } else { 1.0 }),
    ),
    ("diagnostics", diagnostics),
  ])
  if success {
    report["result"] = result
  } else {
    report["error"] = {
      "code": if cancelled {
        "compile.cancelled"
      } else {
        "compile.failed"
      },
      "message": "Compilation did not publish a model",
    }
  }
  match mode {
    JSON => println(Json::object(report).stringify())
    JSONLines => emit_record("result", Json::object(report))
    Human => ()
  }
}

///|
fn compilation_error(
  message : String,
  mode : OutputMode,
  status : Int32,
) -> Unit {
  let report : Json = {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "compile",
    "state": "failed",
    "exitCode": status,
    "diagnostics": [],
    "error": { "code": "compile.invalid_request", "message": message },
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("result", report)
    Human => ()
  }
}
