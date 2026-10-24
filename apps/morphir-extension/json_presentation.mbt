///|
// Only leading --json owns presentation syntax. The legacy no-argument
// protocol invocation remains strict; no opaque operand tail is accepted.
enum PresentationMode {
  Human
  Events
  Help(String)
}

///|
fn presentation_command() -> @argparse.Command {
  @argparse.Command(
    "extension.mep",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[@argparse.FlagArg("json"), @argparse.FlagArg("help", short='h')],
    about="Reads MEP Content-Length frames on stdin; stdout remains exact MEP frames. Leading --json emits morphir/command-event 0.1.0 on stderr. --json --help returns morphir/command-result help on stderr without reading stdin. Expected JSON-mode failures exit 1; syntax exits 2. Legacy hard aborts/signals are not portable exit codes. No positional arguments are accepted.",
  )
}

///|
fn presentation_mode(args : ArrayView[String]) -> PresentationMode raise {
  if args.is_empty() || args[0] != "--json" {
    return Human
  }
  let prefix = args
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
    "command": "extension.mep",
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
    "command": "extension.mep",
    "state": "succeeded",
    "exitCode": 0,
    "result": { "help": Json(text) },
    "diagnostics": [],
  }
  value.stringify() + "\n"
}

///|
async fn presentation_write(text : String) -> Unit {
  @stdio.stderr.write(text)
}
