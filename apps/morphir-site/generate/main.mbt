///|
/// Encode every token identically so only exact option names have CLI meaning.
/// In particular, raw `--`, equals forms and help remain literal data.
fn encoded_argument(token : String) -> String {
  "--token-" + @hex.encode(@utf8.encode(token))
}

///|
fn ignored_arguments() -> @argparse.PositionArg {
  @argparse.PositionArg(
    "ignored",
    num_args=@argparse.ValueRange(lower=0),
    allow_hyphen_values=true,
  )
}

///|
/// Each old option lookup was independent: another option can be both a value
/// here and a recognized name in its own parser. Append retains the first value.
fn first_option(argv : Array[String], name : String) -> String? raise {
  let command = @argparse.Command(
    "morphir-site generate",
    disable_help_flag=true,
    disable_help_subcommand=true,
    options=[
      @argparse.OptionArg(
        "value",
        long=encoded_argument(name)[2:],
        action=Append,
        allow_hyphen_values=true,
      ),
    ],
    positionals=[ignored_arguments()],
  )
  // No original token encodes to this sentinel. Appending it gives a terminal
  // option a value without scanning argv or losing an earlier duplicate value.
  let normalized = [..argv.map(encoded_argument), "missing-value"]
  let parsed = command.parse(argv=normalized)
  match parsed.values.get("value") {
    Some([value, ..]) if value != "missing-value" =>
      Some(@utf8.decode(@hex.decode(value[8:])))
    _ => None
  }
}

///|
fn generate_options(argv : Array[String]) -> (String, String, Bool) raise {
  let root = first_option(argv, "--root").unwrap_or("../..")
  let out = first_option(argv, "--out").unwrap_or("\{root}/_site")
  // The old global contains lookup also sees --main when another option takes
  // it as a pathname value. Its independent flag-only parser must see all argv.
  let main_flag = @argparse.Command(
    "morphir-site generate",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[@argparse.FlagArg("main", long=encoded_argument("--main")[2:])],
    positionals=[ignored_arguments()],
  ).parse(argv=argv.map(encoded_argument))
  (root, out, main_flag.flags.get("main").unwrap_or(false))
}

///|
async fn main {
  let argv = @env.args()
  match argv[1:] {
    ["--json", ..] => {
      json_main(argv[1:])
      return
    }
    ["--forward-argv", "--", .. raw] => {
      // Validate the bounded owned prefix; the raw segment stays untouched.
      let prefix = @argparse.Command(
        "morphir-site generate",
        disable_help_flag=true,
        disable_help_subcommand=true,
        flags=[@argparse.FlagArg("forward-argv", required=true)],
      )
      ignore(prefix.parse(argv=argv[1:2], env=Map([]))) catch {
        e => {
          println("error: \{e}")
          @sys.exit(1)
          return
        }
      }
      legacy_main(raw.to_owned())
      return
    }
    _ => legacy_main(argv)
  }
}

///|
async fn legacy_main(argv : Array[String]) -> Unit {
  let (root, out, main_build) = generate_options(argv) catch {
    error => {
      println("error: \{error}")
      @sys.exit(1)
      return
    }
  }
  let warnings = generate(root, out, main_build) catch {
    @model.Invalid(problems) => {
      for p in problems {
        println("error: \{p.render()}")
      }
      println("site: \{problems.length()} problem(s)")
      @sys.exit(1)
      []
    }
    error => {
      println("error: \{error}")
      @sys.exit(1)
      []
    }
  }
  for w in warnings {
    println("warning: \{w.render()}")
  }
  println("site: wrote \{out}")
}

///|
enum SitePresentation {
  Help
  Run(Array[String])
}

///|
fn json_command() -> @argparse.Command {
  @argparse.Command(
    "morphir-site generate",
    about="Use --json -- LEGACY_ARGS for machine output. The legacy segment retains exact option lookup, first duplicates, missing values and ignored tokens. Use --forward-argv -- RAW for an entirely literal legacy invocation.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[
      @argparse.FlagArg("json", required=true),
      @argparse.FlagArg("help", short='h'),
    ],
  )
}

///|
/// The reserved delimiter is unwrapped once. The library never consumes the raw tail.
fn json_presentation(argv : ArrayView[String]) -> SitePresentation raise {
  match argv {
    ["--json", "--", .. raw] => {
      ignore(json_command().parse(argv=argv[:1], env=Map([])))
      Run(raw.to_owned())
    }
    _ => {
      let parsed = json_command().parse(argv~, env=Map([]))
      if parsed.flags.get("help").unwrap_or(false) {
        Help
      } else {
        Run([])
      }
    }
  }
}

///|
fn success(result : Json, diagnostics~ : Array[Json] = []) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.site.generate",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": diagnostics,
  }
}

///|
fn failure(
  code : String,
  message : String,
  diagnostics~ : Array[Json] = [],
) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.site.generate",
    "state": "failed",
    "exitCode": 1,
    "error": { "code": code, "message": message },
    "diagnostics": diagnostics,
  }
}

///|
async fn json_write(text : String) -> Unit {
  @stdio.stdout.write(text + "\n")
}

///|
async fn json_main(argv : ArrayView[String]) -> Unit {
  let presentation = json_presentation(argv) catch {
    e => {
      json_write(failure("syntax", e.to_string()).stringify())
      @sys.exit(1)
      return
    }
  }
  match presentation {
    Help =>
      json_write(success({ "help": json_command().render_help() }).stringify())
    Run(raw) =>
      try {
        let (root, out, main_build) = generate_options(raw)
        let (warnings, written) = generate_report(root, out, main_build)
        let diagnostics : Array[Json] = warnings.map(w => {
          "severity": "warning",
          "message": w.render(),
        })
        for w in warnings {
          @stdio.stderr.write("warning: \{w.render()}\n")
        }
        json_write(
          success(
            {
              "root": root,
              "outputDirectory": out,
              "mainBuild": main_build,
              "writtenPaths": written,
            },
            diagnostics~,
          ).stringify(),
        )
      } catch {
        @model.Invalid(problems) => {
          let diagnostics : Array[Json] = problems.map(p => {
            "severity": "error",
            "message": p.render(),
          })
          json_write(
            failure(
              "site.invalid",
              "site: \{problems.length()} problem(s)",
              diagnostics~,
            ).stringify(),
          )
          @sys.exit(1)
        }
        e => {
          json_write(failure("site.generate_failed", e.to_string()).stringify())
          @sys.exit(1)
        }
      }
  }
}
