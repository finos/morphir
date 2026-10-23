///|
enum SdkCommand {
  Bootstrap(String, String)
  Generate
  Check
} derive(Eq)

///|
fn sdk_command() -> @argparse.Command {
  @argparse.Command(
    "sdkgen",
    about="Generate and check SDK bindings",
    disable_help_flag=true,
    disable_help_subcommand=true,
    subcommand_required=true,
    subcommands=[
      @argparse.Command("bootstrap", disable_help_flag=true, positionals=[
        @argparse.PositionArg(
          "bindings",
          num_args=@argparse.ValueRange::single(),
          allow_hyphen_values=true,
        ),
        @argparse.PositionArg(
          "out",
          num_args=@argparse.ValueRange::single(),
          allow_hyphen_values=true,
        ),
      ]),
      @argparse.Command("generate", disable_help_flag=true),
      @argparse.Command("check", disable_help_flag=true),
    ],
  )
}

///|
/// Keep the command boundary fixed and every following token literal. The
/// synthetic delimiter belongs to the adapter; user-supplied delimiters are data.
fn parse_sdk_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  let normalized = match argv {
    [command, .. data] => [command, "--", ..data]
    [] => []
  }
  sdk_command().parse(argv=normalized, env=Map([]))
}

///|
fn sdk_invocation(matches : @argparse.Matches) -> SdkCommand {
  match matches.subcommand {
    Some(("bootstrap", args)) =>
      Bootstrap(args.values["bindings"][0], args.values["out"][0])
    Some(("generate", _)) => Generate
    Some(("check", _)) => Check
    _ => abort("sdkgen command selection invariant")
  }
}

///|
fn main {
  // This native filesystem tool owns the program-path prefix, as before.
  let matches = parse_sdk_arguments(@env.args()[1:]) catch {
    _ => {
      println("usage: sdkgen bootstrap <bindings.json> <out.scm>")
      println("       sdkgen generate | check")
      @sys.exit(2)
      return
    }
  }
  match sdk_invocation(matches) {
    Bootstrap(bindings, out) =>
      try {
        let message = bootstrap(bindings, out)
        println(message)
      } catch {
        BootstrapError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        ToolError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        e => {
          println("sdkgen: \{e}")
          @sys.exit(1)
        }
      }
    Generate =>
      println(generate()) catch {
        ToolError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        e => {
          println("sdkgen: \{e}")
          @sys.exit(1)
        }
      }
    Check =>
      try {
        let (problems, count) = check()
        if problems.is_empty() {
          println("sdk.scm matches \{count} bindings; sdk_data.mbt is current")
        } else {
          for problem in problems {
            println(problem)
          }
          println("sdkgen: \{problems.length()} differences")
          @sys.exit(1)
        }
      } catch {
        ToolError(message) => {
          println("sdkgen: \{message}")
          @sys.exit(1)
        }
        e => {
          println("sdkgen: \{e}")
          @sys.exit(1)
        }
      }
  }
}
