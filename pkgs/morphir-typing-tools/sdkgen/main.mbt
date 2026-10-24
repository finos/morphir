///|
enum SdkCommand {
  Bootstrap(String, String)
  Generate
  Check
} derive(Eq)

///|
fn sdk_command(json_mode~ : Bool = false) -> @argparse.Command {
  @argparse.Command(
    "sdkgen",
    about="Generate and check SDK bindings",
    disable_help_flag=true,
    disable_help_subcommand=true,
    subcommand_required=!json_mode,
    flags=if json_mode {
      [
        @argparse.FlagArg("json", required=true),
        @argparse.FlagArg("help", short='h', global=true),
      ]
    } else {
      []
    },
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
  let argv = @env.args()[1:]
  match argv {
    ["--json", ..] => {
      json_main(argv)
      return
    }
    _ => ()
  }
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
        let (message, _, _) = bootstrap(bindings, out)
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

///|
fn json_command() -> @argparse.Command {
  sdk_command(json_mode=true)
}

///|
fn parse_json_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  let normalized = match argv {
    ["--json", "bootstrap", .. data] => ["--json", "bootstrap", "--", ..data]
    _ => argv.to_owned()
  }
  let parsed = json_command().parse(argv=normalized, env=Map([]))
  if parsed.subcommand is None && !parsed.flags.get("help").unwrap_or(false) {
    // Let the required-command grammar supply the syntax diagnostic.
    ignore(sdk_command().parse(argv=[], env=Map([])))
  }
  parsed
}

///|
fn success(command : String, result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": command,
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
fn failure(
  command : String,
  exit_code : Int32,
  code : String,
  message : String,
  diagnostics~ : Array[Json] = [],
) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": command,
    "state": "failed",
    "exitCode": exit_code,
    "error": { "code": code, "message": message },
    "diagnostics": diagnostics,
  }
}

///|
// JSON owns stdout only on this path. UCRT text mode translates println's LF;
// _O_BINARY (0x8000) preserves the existing compact JSON bytes on Windows.
#cfg(all(target="native", platform="windows"))
extern "C" fn json_stdout_setmode(fd : Int32, mode : Int32) -> Int32 = "_setmode"

///|
#cfg(all(target="native", platform="windows"))
fn prepare_json_stdout() -> Bool {
  json_stdout_setmode(1, 0x8000) >= 0
}

///|
#cfg(not(all(target="native", platform="windows")))
fn prepare_json_stdout() -> Bool {
  true
}

///|
fn json_main(argv : ArrayView[String]) -> Unit {
  // Prepare before parse refusal, help, domain work or the first JSON write.
  // A failed mode change must not emit a success record or perform file writes.
  if !prepare_json_stdout() {
    @sys.exit(1)
    return
  }
  let matches = parse_json_arguments(argv) catch {
    e => {
      println(failure("morphir.sdkgen", 2, "syntax", e.to_string()).stringify())
      @sys.exit(2)
      return
    }
  }
  if matches.flags.get("help").unwrap_or(false) {
    println(
      success("morphir.sdkgen", { "help": json_command().render_help() }).stringify(),
    )
    return
  }
  let invocation = sdk_invocation(matches)
  let command = match invocation {
    Bootstrap(_, _) => "morphir.sdkgen.bootstrap"
    Generate => "morphir.sdkgen.generate"
    Check => "morphir.sdkgen.check"
  }
  try {
    match invocation {
      Bootstrap(bindings, out) => {
        let (_, values, modules) = bootstrap(bindings, out)
        println(
          success(command, {
            "bindingsPath": bindings,
            "writtenPaths": [out],
            "valueCount": values,
            "moduleCount": modules,
          }).stringify(),
        )
      }
      Generate => {
        ignore(generate())
        println(
          success(command, {
            "sourcePath": scm_path,
            "writtenPaths": [data_path],
          }).stringify(),
        )
      }
      Check => {
        let (problems, count) = check()
        if problems.is_empty() {
          println(
            success(command, {
              "bindingCount": count,
              "checkedPaths": [bindings_path, scm_path, data_path],
              "passed": true,
            }).stringify(),
          )
        } else {
          let diagnostics : Array[Json] = problems.map(p => {
            "severity": "error",
            "message": p,
          })
          println(
            failure(
              command,
              1,
              "sdkgen.differences",
              "sdkgen: \{problems.length()} differences",
              diagnostics~,
            ).stringify(),
          )
          @sys.exit(1)
        }
      }
    }
  } catch {
    BootstrapError(message) | ToolError(message) => {
      println(failure(command, 1, "sdkgen.failed", message).stringify())
      @sys.exit(1)
    }
    e => {
      println(failure(command, 1, "sdkgen.failed", e.to_string()).stringify())
      @sys.exit(1)
    }
  }
}
