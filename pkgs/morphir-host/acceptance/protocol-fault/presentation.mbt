///|
/// Presentation owns only these reserved outer families. Raw operands are sliced
/// from the original argv and unwrapped once, never rebuilt from parser values.
enum Presentation {
  Legacy(Array[String])
  Structured(Array[String])
  JsonHelp
} derive(Eq)

///|
suberror PresentationError {
  PresentationError(String)
}

///|
fn presentation_command() -> @argparse.Command {
  @argparse.Command(
    "host.acceptance.protocol-fault",
    about="RAW is literal CHECKPOINT FAULT followed by historically ignored operands. Completed mutation reports fault, path and actual bytesWritten after writing. Codec and fault validation are domain checks. Opt-in reporting: --json -- RAW; literal escape: --forward-argv -- RAW. Each reserved family unwraps once. A lone --json is literal. --json --help has no effects. Finite stdout: one compact morphir/command-result 0.1.0 plus LF, existing JSON success objects stay bare. Failure status equals exitCode, expected refusals use 1. Wire stdout stays unchanged; bounded morphir/command-event 0.1.0 NDJSON uses stderr. Ready means initialized, not qualified. Signals, hard aborts and deliberate corruption may prevent terminal reporting.",
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
    "command": "host.acceptance.protocol-fault",
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
    "command": "host.acceptance.protocol-fault",
    "state": "failed",
    "exitCode": 1,
    "error": { "code": "command.failed", "message": presentation_reason(error) },
    "diagnostics": [],
  }
}

///|
fn json_help() -> Unit {
  json_output(
    completed({ "render_help": presentation_command().render_help() }).stringify(),
  )
}

///|
// Microsoft UCRT _O_BINARY is 0x8000. Only new JSON stdout selects binary
// mode; literal/default mutation, stdin, stderr and global fmode stay untouched.
#cfg(all(target="native", platform="windows"))
extern "C" fn json_setmode(fd : Int32, mode : Int32) -> Int32 = "_setmode"

///|
#cfg(all(target="native", platform="windows"))
fn prepare_json_stdout() -> Int32 {
  json_setmode(1, 0x8000)
}

///|
#cfg(not(all(target="native", platform="windows")))
fn prepare_json_stdout() -> Int32 {
  0
}

///|
fn json_output(payload : String) -> Unit {
  if prepare_json_stdout() < 0 {
    failure_exit()
  } else {
    println(payload)
  }
}

///|
fn presentation_reason(error : Error) -> String {
  match error {
    PresentationError(reason) => reason
    _ => error.to_string()
  }
}

///|
/// As in host/platform/js.mbt, return so Node drains pending stdout writes.
#cfg(target="js")
extern "js" fn failure_exit() -> Unit =
  #| () => { process.exitCode = 1; }

///|
#cfg(not(target="js"))
fn failure_exit() -> Unit {
  @sys.exit(1)
}
