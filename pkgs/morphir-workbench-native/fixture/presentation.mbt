///|
/// Presentation owns only these reserved outer families. Raw operands are sliced
/// from the original argv and unwrapped once, never rebuilt from parser values.
enum Presentation {
  Legacy(Array[String])
  Structured(Array[String])
  JsonHelp
} derive(Eq)

///|
fn presentation_command() -> @argparse.Command {
  @argparse.Command(
    "workbench.native.fixture",
    about="RAW remains ignored. Only executable argv[0] selects deliberate fault modes; binary stdout and deliberate status 7, sleeps, frames and stderr floods remain unchanged. Opt-in reporting: --json -- RAW; literal escape: --forward-argv -- RAW. Each reserved family unwraps once. A lone --json is literal. --json --help has no effects. Finite stdout: one compact morphir/command-result 0.1.0 plus LF, existing JSON success objects stay bare. Failure status equals exitCode, expected refusals use 1. Wire stdout stays unchanged; bounded morphir/command-event 0.1.0 NDJSON uses stderr. Ready means initialized, not qualified. Signals, hard aborts and deliberate corruption may prevent terminal reporting.",
    disable_help_flag=true,
    disable_version_flag=true,
    disable_help_subcommand=true,
    flags=[
      @argparse.FlagArg("json", conflicts_with=["forward-argv"]),
      @argparse.FlagArg("forward-argv"),
      @argparse.FlagArg("help"),
    ],
    positionals=[
      @argparse.PositionArg(
        "RAW",
        num_args=@argparse.ValueRange(lower=0),
        allow_hyphen_values=true,
      ),
    ],
  )
}

///|
fn presentation(arguments : ArrayView[String]) -> Presentation raise {
  match arguments {
    ["--json", "--help"] => {
      ignore(presentation_command().parse(argv=arguments, env=Map([])))
      JsonHelp
    }
    ["--json", "--", .. raw] => {
      ignore(presentation_command().parse(argv=arguments, env=Map([])))
      Structured(raw.to_owned())
    }
    ["--forward-argv", "--", .. raw] => {
      ignore(presentation_command().parse(argv=arguments, env=Map([])))
      Legacy(raw.to_owned())
    }
    _ => Legacy(arguments.to_owned())
  }
}

///|
fn completed(result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "workbench.native.fixture",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
async fn json_help() -> Unit {
  @stdio.stdout.write(
    completed({ "render_help": presentation_command().render_help() }).stringify() +
    "\n",
  )
}

///|
async fn event(
  name : String,
  sequence : Int32,
  error~ : Error? = None,
  exit_code~ : Int32 = 0,
) -> Unit {
  let fields : Map[String, Json] = {
    "profile": "morphir/command-event",
    "contractVersion": "0.1.0",
    "command": "workbench.native.fixture",
    "event": Json::string(name),
    "sequence": Json::number(sequence.to_double()),
  }
  if name == "terminal" {
    fields["exitCode"] = Json::number(exit_code.to_double())
  }
  if error is Some(error) {
    let message = error.to_string()
    let message = if message.length() > 1024 {
      message[:1024].to_owned()
    } else {
      message
    }
    fields["error"] = { "code": "command.failed", "message": message }
    fields["exitCode"] = Json::number(exit_code.to_double())
  }
  @stdio.stderr.write(Json::object(fields).stringify() + "\n")
}
