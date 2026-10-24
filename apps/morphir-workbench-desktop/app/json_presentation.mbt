///|
// Only a leading --json owns CLI syntax. --json -- RAW reserves one
// separator; RAW remains literal. Proton still receives the original argv array, including the owned prefix.
// --forward-argv -- RAW keeps a literal leading --json outside that boundary.
enum PresentationMode {
  Human
  Events
  Help(String)
}

///|
fn presentation_command() -> @argparse.Command {
  @argparse.Command(
    "workbench.desktop",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[@argparse.FlagArg("json"), @argparse.FlagArg("help", short='h')],
    about="Leading --json emits morphir/command-event 0.1.0 lifecycle events on stdout; framework stderr/file logging is unchanged. Native worker sentinel keeps binary stdout and puts events on stderr. --json --help returns morphir/command-result help without starting Proton or a worker. Expected JSON-mode failures exit 1; syntax exits 2. Legacy hard aborts/signals are not portable exit codes. --json -- RAW reserves one separator; --forward-argv -- RAW represents literal --json. Framework argv is never filtered or reconstructed. Ready requires actual window/browser callbacks; quit status is observed in on_quit.",
  )
}

///|
fn presentation_mode(args : ArrayView[String]) -> PresentationMode raise {
  if args.is_empty() || args[0] != "--json" {
    return Human
  }
  let prefix = if args.length() >= 2 && args[1] == "--" {
    args[:1]
  } else {
    args
  }
  let cmd = presentation_command()
  let matches = cmd.parse(argv=prefix, env=Map([]))
  if matches.flags.get_or_default("help", false) {
    Help(cmd.render_help())
  } else {
    Events
  }
}

///|
fn presentation_event(
  sequence : Int32,
  event : String,
  fields : Map[String, Json],
) -> String {
  let value : Map[String, Json] = {
    "profile": "morphir/command-event",
    "contractVersion": "0.1.0",
    "command": "workbench.desktop",
    "event": Json(event),
    "sequence": Json(sequence),
  }
  for key, item in fields {
    value[key] = item
  }
  Json(value).stringify() + "\n"
}

///|
fn presentation_help(text : String) -> String {
  let value : Json = {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "workbench.desktop",
    "state": "succeeded",
    "exitCode": 0,
    "result": { "help": Json(text) },
    "diagnostics": [],
  }
  value.stringify() + "\n"
}

///|
enum DesktopEvent {
  Startup
  WindowReady
  BrowserLoaded
  Failure(String, String)
  QuitPrevented
  Exit(Int32)
}

///|
fn desktop_event(sequence : Int32, event : DesktopEvent) -> String {
  let (name, fields) : (String, Map[String, Json]) = match event {
    Startup => ("startup", {})
    WindowReady => ("window-ready-to-show", {})
    BrowserLoaded => ("browser-did-finish-load", {})
    Failure(code, message) =>
      ("failure", { "error": { "code": Json(code), "message": Json(message) } })
    QuitPrevented =>
      (
        "quit-prevented",
        {
          "error": {
            "code": "worker_exit_unconfirmed",
            "message": "Native worker exit could not be confirmed",
          },
        },
      )
    Exit(code) => ("exit", { "exitCode": Json(code) })
  }
  presentation_event(sequence, name, fields)
}

///|
struct DesktopPresentation {
  enabled : Bool
  wire : Bool
  mut sequence : Int32
}
