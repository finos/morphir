///|
// Only a leading --json owns CLI syntax. --json -- RAW reserves one
// separator; RAW remains literal and is ignored just as legacy host argv was.
// --forward-argv -- RAW keeps a literal leading --json outside that boundary.
enum PresentationMode {
  Human
  Events
  Help(String)
}

///|
fn presentation_command() -> @argparse.Command {
  @argparse.Command(
    "workbench.mck.selected.js",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[@argparse.FlagArg("json"), @argparse.FlagArg("help", short='h')],
    about="Reads bounded NDJSON on stdin; stdout remains exact wire NDJSON. Leading --json emits morphir/command-event 0.1.0 on stderr. --json --help returns morphir/command-result help on stderr without reading stdin. Expected JSON-mode failures exit 1; syntax exits 2. Legacy hard aborts/signals are not portable exit codes. --json -- RAW reserves one separator; --forward-argv -- RAW represents literal --json. Other argv stays ignored.",
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
    "command": "workbench.mck.selected.js",
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
    "command": "workbench.mck.selected.js",
    "state": "succeeded",
    "exitCode": 0,
    "result": { "help": Json(text) },
    "diagnostics": [],
  }
  value.stringify() + "\n"
}

///|
extern "js" fn presentation_args() -> FixedArray[String] =
  #| () => typeof process === 'undefined' ? [] : process.argv.slice(2)

///|
extern "js" fn presentation_write(text : String) -> Unit =
  #| text => process.stderr.write(text)

///|
// Syntax rejection has not started stdin or the protocol server. Queue a
// completion barrier after the owned diagnostic, with a five-second deadline
// for a blocked or broken stderr destination. Preserve the syntax exit code.
extern "js" fn presentation_exit(code : Int32) -> Unit =
  #| code => {
  #|   const timeout = setTimeout(() => process.exit(code), 5000);
  #|   const finish = () => { clearTimeout(timeout); process.exit(code); };
  #|   process.stderr.once('error', finish);
  #|   process.stderr.write('', finish);
  #| }
