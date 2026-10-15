///|
/// ArgParser receives explicit argv; host IO and process exit stay in main.
struct Cli {
  command : String
  flags : Map[String, Bool]
  entries : Map[String, Array[String]]
  forwarded : Array[String]?
  help : Bool
  help_text : String
}

///|
struct CliSchema {
  flags : Array[String]
  options : Array[String]
  repeatable : Array[String]
  positional : Bool
  children : Array[String]
}

///|
let pipeline_options : Array[String] = [
  "project", "frontend", "frontend-provider", "frontend-profile", "backend", "output",
  "config", "checkpoint-format", "validation", "target", "build-provider", "build-helper",
  "build-node", "sdk", "home", "timeout", "component",
]

///|
let execution_options : Array[String] = [
  "suite", "suite-format", "model-format", "unit-id", "target", "execution-helper",
  "home", "node", "dependency", "timeout", "log-file", "log-format", "toolchain-pin",
  "telemetry-adapter", "cancel-file", "build-mode", "comparison", "absolute-tolerance",
  "relative-tolerance", "otel-binary", "otel-pin", "otel-helper", "otel-endpoint",
  "otel-protocol", "otel-flush-timeout",
]

///|
let conformance_options : Array[String] = [
  "cases", "cases-format", "evaluators", "require-evaluator", "rust-evaluator", "rust-evaluator-pin",
  "rust-helper", "receipt", "receipt-format",
]

///|
let global_flags : Array[String] = ["help", "json", "json-lines"]

///|
fn command_schema(path : String) -> CliSchema {
  let mut flags = []
  let mut options = []
  let mut repeatable = []
  let mut positional = false
  let mut children = []
  match path {
    "" =>
      children = [
        "run", "workspace", "execute", "verify", "conform", "project", "toolchain",
      ]
    "run" => {
      flags = ["all", "dry-run", "file", "directory", "log"]
      options = pipeline_options +
        [
          "log-file", "log-format", "metadata-grants", "metadata-timeout", "cancel-file",
        ]
      repeatable = pipeline_options
      positional = true
    }
    "workspace" => {
      flags = ["all", "dry-run", "file", "directory"]
      options = pipeline_options
      repeatable = pipeline_options
      positional = true
    }
    "execute" | "verify" => {
      flags = ["dry-run", "log"]
      options = execution_options
      repeatable = ["dependency"]
      positional = true
    }
    "conform" => {
      flags = ["dry-run", "log"]
      options = execution_options + conformance_options
      repeatable = ["dependency"]
      positional = true
    }
    "project" => children = ["list"]
    "project list" => {
      options = ["frontend", "target", "config"]
      repeatable = options
      positional = true
    }
    "toolchain" => children = ["info", "setup", "build", "run", "exec"]
    "toolchain info" => options = ["home", "timeout"]
    "toolchain setup" => {
      flags = ["yes"]
      options = ["home", "timeout"]
    }
    "toolchain build" => {
      options = ["home", "target", "timeout"]
      positional = true
    }
    "toolchain run" => {
      options = ["home", "target", "timeout", "package"]
      positional = true
    }
    "toolchain exec" => {
      options = ["home", "timeout"]
      positional = true
    }
    _ => ()
  }
  { flags, options, repeatable, positional, children, }
}

///|
fn render_help(path : String) -> String {
  let schema = command_schema(path)
  let name = if path == "" { "morphir" } else { "morphir " + path }
  let mut text = "Usage: " + name
  if !schema.children.is_empty() {
    text += " <command>"
  }
  if schema.positional {
    text += if path == "execute" || path == "verify" || path == "conform" {
      " <model>"
    } else {
      " [path]"
    }
  }
  text += " [options]\n"
  if !schema.children.is_empty() {
    text += "\nCommands:\n  " + schema.children.join("\n  ") + "\n"
  }
  text += "\nOptions:\n  -h, --help\n  --json\n  --json-lines\n"
  for name in schema.flags {
    text += "  --" + name + "\n"
  }
  for name in schema.options {
    text += "  --" + name + " <value>\n"
  }
  if path == "toolchain run" || path == "toolchain exec" {
    text += "  -- <program arguments>\n"
  }
  text
}

///|
/// Tokens after -- are opaque child-process data, including empty strings.
fn option_args(args : Array[String]) -> Array[String] {
  match args.search_by(arg => arg == "--") {
    Some(i) => args[:i].to_owned()
    None => args
  }
}

///|
/// Parse failures still owe callers their requested machine error envelope.
fn error_output_mode(args : Array[String]) -> OutputMode {
  let head = option_args(args)
  if head.contains("--json-lines") {
    JSONLines
  } else if head.contains("--json") {
    JSON
  } else {
    Human
  }
}

///|
/// ArgParser's automatic --help handler raises immediately. Use a private
/// alias so help is an ordinary flag and the entire Morphir segment is checked.
/// Reject the alias in user input; never expose it in generated help.
let help_alias : String = "--morphir-internal-help"

///|
fn parse_cli(args : Array[String]) -> Cli raise {
  let head = option_args(args)
  let command = Ref("")
  let flags : Map[String, Bool] = Map([])
  let entries : Map[String, Array[String]] = Map([])
  let names = (pipeline_options +
  execution_options +
  conformance_options +
  ["package", "metadata-grants", "metadata-timeout"]).fold(
    (names : Array[String], name) => {
      if !names.contains(name) {
        names.push(name)
      }
      names
    },
    init=[],
  )
  let specs : Array[(String, String, @argparser.Spec, String)] = []
  for
    name in global_flags + ["all", "dry-run", "file", "directory", "yes", "log"] {
    let token = if name == "help" { help_alias } else { "--" + name }
    specs.push(
      (
        token,
        token,
        @argparser.Unit(() => {
          if !global_flags.contains(name) &&
            !command_schema(command.val).flags.contains(name) {
            raise @config.Invalid(
              "Unexpected option: --" + name + "\n" + render_help(command.val),
            )
          }
          flags[name] = true
        }),
        "",
      ),
    )
  }
  for name in names {
    let token = "--" + name
    specs.push(
      (
        token,
        token,
        @argparser.String(input => {
          let schema = command_schema(command.val)
          if !schema.options.contains(name) {
            raise @config.Invalid(
              "Unexpected option: " + token + "\n" + render_help(command.val),
            )
          }
          if input == "" ||
            (
              input.has_prefix("-") &&
              name != "absolute-tolerance" &&
              name != "relative-tolerance"
            ) {
            raise @config.Invalid("Missing value for " + token)
          }
          if entries.contains(name) && !schema.repeatable.contains(name) {
            raise @config.Invalid("Repeated option: " + token)
          }
          let previous = entries.get(name).unwrap_or([])
          previous.push(input)
          entries[name] = previous
        }),
        "",
      ),
    )
  }
  let normalized : Array[String] = []
  for token in head {
    if token == help_alias {
      raise @config.Invalid("Unexpected argument: " + token)
    } else if token == "--help" || token == "-h" {
      normalized.push(help_alias)
    } else if token.has_prefix("--") &&
      token.split_once("=") is Some((name, input)) &&
      names.contains(name[2:].to_owned()) {
      normalized.push(name.to_owned())
      normalized.push(input.to_owned())
    } else {
      normalized.push(token)
    }
  }
  @argparser.parse(
    specs,
    token => {
      let schema = command_schema(command.val)
      if !schema.children.is_empty() && schema.children.contains(token) {
        command.val = if command.val == "" {
          token
        } else {
          command.val + " " + token
        }
      } else if token.has_prefix("-") ||
        !schema.positional ||
        entries.contains("path") {
        raise @config.Invalid(
          "Unexpected argument: " + token + "\n" + render_help(command.val),
        )
      } else {
        entries["path"] = [token]
      }
    },
    "",
    normalized,
  ) catch {
    @argparser.ErrorMsg(message) =>
      raise @config.Invalid(message + "\n" + render_help(command.val))
    error => raise error
  }
  if flags.contains("json") && flags.contains("json-lines") {
    raise @config.Invalid("--json and --json-lines cannot be combined")
  }
  if flags.contains("all") && entries.contains("project") {
    raise @config.Invalid("--all and --project cannot be combined")
  }
  if flags.contains("file") && flags.contains("directory") {
    raise @config.Invalid("--file and --directory cannot be combined")
  }
  let forwarded = if head.length() < args.length() {
    if command.val != "toolchain run" && command.val != "toolchain exec" {
      raise @config.Invalid("Program arguments require toolchain run or exec")
    }
    Some(args[head.length() + 1:].to_owned())
  } else {
    None
  }
  let help = flags.contains("help") || command.val == ""
  if !command_schema(command.val).children.is_empty() &&
    command.val != "" &&
    !help {
    raise @config.Invalid("A subcommand is required for " + command.val)
  }
  {
    command: command.val,
    flags,
    entries,
    forwarded,
    help,
    help_text: render_help(command.val),
  }
}

///|
fn flag(cli : Cli, name : String) -> Bool {
  cli.flags.get(name).unwrap_or(false)
}

///|
fn values(cli : Cli, name : String) -> Array[String] {
  cli.entries.get(name).unwrap_or([])
}

///|
fn value(cli : Cli, name : String, fallback? : String = "") -> String {
  let entries = values(cli, name)
  entries.get(entries.length() - 1).unwrap_or(fallback)
}
