///|
let launcher_help : String =
  #|Usage: moonx finos/morphir/moonx@VERSION [LAUNCHER OPTIONS] [MORPHIR ARGUMENTS]
  #|
  #|Runs the packaged Morphir CLI. Node must be available on PATH.
  #|Native installation does not require Node.
  #|
  #|Launcher options, before the first Morphir argument:
  #|  --moonx-help     Show this launcher help.
  #|  --moonx-json     Report launcher help and startup failures as JSON.
  #|  --json           Select launcher JSON and also forward --json to Morphir.
  #|  --moonx-forward  Forward every following argument literally.
  #|
  #|Use --help for Morphir help. Arguments, cwd and binary streams are preserved.
  #|Forwarded commands own stdout and their result schemas remain unchanged.
  #|Launcher JSON uses morphir/command-result 0.1.0, command moonx. Help succeeds
  #|with result.help. A startup failure has state failed, exitCode, diagnostics
  #|and error {code, message}. Launcher startup and cleanup reports use stderr,
  #|including JSON, so framed command channels receive no launcher document.
  #|Local launcher help writes its finite result to stdout.
  #|Syntax exits 2. Startup failure exits 1. Cancellation retains the host status.
  #|POSIX preserves SIGINT/SIGTERM. Stock Windows Moonx maps parent Ctrl+C to
  #|Node Ctrl+Break: Morphir reports Quit/131; the parent retains 0xC000013A.

///|
fn failure_document(status : UInt32, code : String, message : String) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "moonx",
    "state": "failed",
    "exitCode": status,
    "diagnostics": [],
    "error": { "code": code, "message": message },
  }
}

///|
fn help_document() -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "moonx",
    "state": "succeeded",
    "exitCode": 0,
    "diagnostics": [],
    "result": { "help": launcher_help },
  }
}

///|
fn report_failure(
  format : @options.OutputFormat,
  status : UInt32,
  code : String,
  message : String,
) -> Unit {
  match format {
    MachineJson => eprintln(failure_document(status, code, message).stringify())
    Human => eprintln("Morphir Moonx: " + message)
  }
}

///|
fn startup_failure(outcome : @launcher.LaunchOutcome) -> (String, String)? {
  let failure = match outcome.result() {
    Started(_) => return None
    NotStarted(Failed(NodeMissing(..))) =>
      (
        "moonx.node_missing", "Node is required for Moonx. Install Node and make node available on PATH, or use the native Morphir CLI.",
      )
    NotStarted(Failed(Materialization(error))) =>
      ("moonx.materialization_failed", error.to_string())
    NotStarted(Failed(ProcessStart(error))) =>
      ("moonx.process_start_failed", error.to_string())
    NotStarted(Cancelled(_)) =>
      ("moonx.cancelled", "Morphir was cancelled before its process started.")
  }
  Some(failure)
}

///|
fn startup_document(outcome : @launcher.LaunchOutcome) -> Json? {
  match startup_failure(outcome) {
    Some((code, message)) =>
      Some(failure_document(outcome.selected_status().bits(), code, message))
    None => None
  }
}
