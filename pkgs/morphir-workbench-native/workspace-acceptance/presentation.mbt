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
    "workbench.native.workspace-acceptance",
    about="RAW selects fixture PATH, race BASE, or default checks. Fixed PATH and BASE are literal, including flag-shaped strings; legacy unrecognized invocations still run checks. Opt-in reporting: --json -- RAW; literal escape: --forward-argv -- RAW. Each reserved family unwraps once. A lone --json is literal. --json --help has no effects. Finite stdout: one compact morphir/command-result 0.1.0 plus LF, existing JSON success objects stay bare. Failure status equals exitCode, expected refusals use 1. Wire stdout stays unchanged; bounded morphir/command-event 0.1.0 NDJSON uses stderr. Ready means initialized, not qualified. Signals, hard aborts and deliberate corruption may prevent terminal reporting.",
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
    "command": "workbench.native.workspace-acceptance",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
fn failed(error : Error) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "workbench.native.workspace-acceptance",
    "state": "failed",
    "exitCode": 1,
    "error": { "code": "command.failed", "message": error.to_string() },
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
