///|
fn finite_success(result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir-extension.acceptance",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
async fn finite_failure(error : Error) -> Unit {
  @stdio.stdout.write(
    (
      {
        "profile": "morphir/command-result",
        "contractVersion": "0.1.0",
        "command": "morphir-extension.acceptance",
        "state": "failed",
        "exitCode": 1,
        "error": { "code": "command.failed", "message": error.to_string() },
        "diagnostics": [],
      } : Json).stringify() +
    "\n",
  )
  @sys.exit(1)
}

///|
fn finite_controls() -> @argparse.Command {
  @argparse.Command(
    "morphir-extension-acceptance --json",
    about="JSON help and parser self-test use morphir/command-result 0.1.0, with state, exitCode, result or error{code,message}, and diagnostics. Completed acceptance keeps its existing bare JSON receipt. One compact object plus LF goes to stdout; failures exit1. A complete legacy triple remains literal. Use --json -- GUEST REPOSITORY EVIDENCE to select JSON explicitly.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[@argparse.FlagArg("help", short='h'), @argparse.FlagArg("self-test")],
  )
}

///|
fn finite_self_test() -> Json raise {
  let cases = [
    ["", "λ😀", "--"],
    ["--json", "--help", "--"],
    ["guest", "repository", "evidence"],
  ]
  for argv in cases {
    let parsed = parse_acceptance_operands(argv)
    assert_eq(parsed.values["guest"], [argv[0]])
    assert_eq(parsed.values["repository"], [argv[1]])
    assert_eq(parsed.values["evidence"], [argv[2]])
  }
  { "passed": true, "cases": cases.length(), "checks": "literal-operands" }
}

///|
async fn main {
  let argv = @env.args()[1:]
  // A complete legacy triple is always literal, even when its guest is --json.
  // Reserve only the owned prefix, and unwrap its optional raw boundary once.
  if argv.length() != 3 && argv is ["--json", .. rest] {
    try {
      match rest {
        ["--", .. raw] =>
          println(finite_run(parse_acceptance_operands(raw)).stringify())
        ["--help"] | ["-h"] | ["--self-test"] => {
          let controls = finite_controls().parse(argv=rest)
          let result = if controls.flags.get("help").unwrap_or(false) {
            (
              {
                "help": acceptance_command().render_help(),
                "controls": finite_controls().render_help(),
              } : Json)
          } else {
            finite_self_test()
          }
          @stdio.stdout.write(finite_success(result).stringify() + "\n")
        }
        _ => println(finite_run(parse_acceptance_operands(rest)).stringify())
      }
    } catch {
      error => finite_failure(error)
    }
  } else {
    println(finite_run(parse_acceptance_operands(argv)).stringify())
  }
}
