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
  let (root, out, main_build) = generate_options(@env.args()) catch {
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
