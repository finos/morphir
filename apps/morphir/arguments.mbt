///|
/// The parser receives explicit argv; host IO and process exit stay in main.
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
let evaluation_options : Array[String] = [
  "suite", "suite-format", "model-format", "unit-id", "provider", "checking-policy",
  "timeout", "cancel-file",
]

///|
let worksheet_options : Array[String] = [
  "source-id", "source-revision", "timeout", "cancel-file",
]

///|
let connected_options : Array[String] = [
  "provider", "connection", "connected-helper", "node", "timeout", "cancel-file",
]

///|
let generation_cli_options : Array[String] = [
  "target", "model-format", "unit-id", "output", "project", "validation", "build-target",
  "backend-option", "build-provider", "build-helper", "build-node", "home", "sdk",
  "timeout", "cancel-file", "log-file", "log-format",
]

///|
let model_options : Array[String] = ["model-format", "unit-id", "filename"]

///|
let extension_options : Array[String] = [
  "extension-pin", "extension-helper", "node", "timeout", "cancel-file",
]

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
        "run", "workspace", "execute", "verify", "conform", "eval", "worksheet",
        "generate", "model", "connected", "project", "toolchain", "mck", "extension",
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
      children = ["init"]
      positional = true
    }
    "workspace init" => options = ["project", "language", "profile"]
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
    "eval" => {
      options = evaluation_options
      positional = true
    }
    "worksheet" => {
      options = worksheet_options
      positional = true
    }
    "connected" => children = ["connect", "run", "artifacts", "originals"]
    "connected connect" => {
      options = connected_options + ["connection-scope"]
      positional = true
    }
    "connected run" => {
      options = connected_options
      positional = true
    }
    "connected artifacts" => {
      options = [
        "provider", "connection", "output", "transfer-helper", "node", "timeout",
        "cancel-file",
      ]
      positional = true
    }
    "connected originals" => {
      flags = ["list"]
      options = [
        "provider", "connection", "output", "originals-helper", "node", "timeout",
        "cancel-file",
      ]
      positional = true
    }
    "generate" => {
      flags = ["dry-run"]
      options = generation_cli_options
      repeatable = ["backend-option"]
      positional = true
    }
    "model" => children = ["inspect", "export-original"]
    "mck" =>
      options = ["runner-pin", "mck-helper", "node", "timeout", "cancel-file"]
    "extension" => children = ["describe", "compile", "generate"]
    "extension describe" => options = extension_options
    "extension compile" => {
      options = extension_options +
        ["package", "frontend-profile", "model-format", "output"]
      positional = true
    }
    "extension generate" => {
      options = extension_options + ["target", "output"]
      positional = true
    }
    "model inspect" => {
      options = model_options
      positional = true
    }
    "model export-original" => {
      flags = ["overwrite"]
      options = model_options + ["output"]
      positional = true
    }
    "project" => children = ["list", "add", "remove"]
    "project add" => {
      options = ["name", "language", "profile"]
      positional = true
    }
    "project remove" => {
      flags = ["delete"]
      positional = true
    }
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
    text += if path == "execute" ||
      path == "verify" ||
      path == "conform" ||
      path == "eval" {
      " <model>"
    } else if path == "worksheet" {
      " <file|->"
    } else if path == "extension compile" {
      " <source.mbt>"
    } else if path == "extension generate" {
      " <model-envelope.json>"
    } else {
      " [path]"
    }
  }
  text += " [options]\n"
  if path == "eval" {
    text += "\nEvaluate public model functions with the local Scheme provider.\n"
    text += "Checking policy: strict (whole model) or permissive (as code executes).\n"
    text += "Model formats: JSON, YAML, Ion text, Ion binary; stdin requires --model-format.\n"
    text += "Invocation suite codecs are selected separately with --suite-format.\n"
  } else if path == "worksheet" {
    text += "\nEvaluate Scheme expressions with shared definitions and typed source ranges.\n"
  } else if path == "mck" {
    text += "\nDelegate to an explicitly pinned canonical MCK runner.\n"
    text += "Place runner controls before the canonical MCK command; all later arguments are opaque.\n"
    text += "Commands: check, coverage, schema check, kit status/vendor/update, run,\n"
    text += "  report check/render/compare, package, workbench, node-address.\n"
    text += "Canonical report compare covers IR reports; suite-specific checks retain their own contracts.\n"
    text += "Coverage is a vocabulary-presence heuristic: pending cases count.\n"
    text += "It does not see members nested under entry-point documents.\n"
    text += "No runner, interpreter or kit is acquired automatically.\n"
    text += "\nExample: morphir mck --runner-pin runner.json workbench check --kit KIT --report REPORT\n"
  } else if path.has_prefix("extension") {
    text += "\nRun one fresh MEP session with an explicitly pinned extension binding.\n"
    text += "Binding: core-wasm-process, a saved core-Wasm guest in the pinned Node host.\n"
    text += "The pin fixes the runtime, host modules, guest Wasm/manifest and execution profile.\n"
    text += "Component Model, native and Extism bindings are not dispatched by this command.\n"
    text += "compile writes model-envelope.json plus model.ionb (Ion, default) or model.json.\n"
    text += "generate reads a model envelope and writes the returned artifacts.\n"
    text += "Wire cancellation is unsupported; cancellation terminates the guest process.\n"
    text += "\nExample: morphir extension compile src/main.mbt --extension-pin pin.json --package my/pkg --output out\n"
  }
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
/// Options whose values may start with `-`, such as a negative tolerance.
let hyphen_options : Array[String] = [
  "absolute-tolerance", "relative-tolerance",
]

///|
/// The argparse command for `path`, built from `command_schema`. Help, version and the help subcommand are off:
/// help is an ordinary global flag, so the whole Morphir segment is checked and `render_help` writes the text.
fn command_spec(path : String, name : String) -> @argparse.Command {
  let schema = command_schema(path)
  let flags = schema.flags.map(flag => @argparse.FlagArg(flag))
  if path == "" {
    flags.push(@argparse.FlagArg("help", short='h', global=true))
    flags.push(@argparse.FlagArg("json", global=true))
    flags.push(@argparse.FlagArg("json-lines", global=true))
  }
  let options = schema.options.map(option => {
    @argparse.OptionArg(
      option,
      action=Append,
      allow_hyphen_values=hyphen_options.contains(option),
    )
  })
  let positionals = if schema.positional {
    [@argparse.PositionArg("path", num_args=@argparse.ValueRange(upper=1))]
  } else {
    []
  }
  let subcommands = schema.children.map(child => {
    command_spec(if path == "" { child } else { path + " " + child }, child)
  })
  @argparse.Command(
    name,
    flags~,
    options~,
    positionals~,
    subcommands~,
    disable_help_flag=true,
    disable_version_flag=true,
    disable_help_subcommand=true,
  )
}

///|
/// Validate only local MCK syntax before choosing an opaque raw tail. Set
/// rejects repeated controls and bounds candidate attempts. Domain checks and
/// successful help still use parse_cli_local. No-banner must be recognized here
/// before filtering, so it cannot be mistaken for a missing option's value.
fn mck_syntax_spec() -> @argparse.Command {
  @argparse.Command(
    "morphir",
    flags=[
      @argparse.FlagArg("help", short='h', global=true),
      @argparse.FlagArg("json", global=true),
      @argparse.FlagArg("json-lines", global=true),
      @argparse.FlagArg("no-banner", global=true, hidden=true),
    ],
    subcommands=[
      @argparse.Command(
        "mck",
        options=command_schema("mck").options.map(name => {
          @argparse.OptionArg(name, action=Set)
        }),
        disable_help_flag=true,
        disable_version_flag=true,
        disable_help_subcommand=true,
      ),
    ],
    disable_help_flag=true,
    disable_version_flag=true,
    disable_help_subcommand=true,
  )
}

///|
fn parse_cli(args : Array[String]) -> Cli raise {
  if mck_cli(args) is Some(cli) {
    return cli
  }
  parse_cli_local(args)
}

///|
fn parse_cli_local(args : Array[String]) -> Cli raise {
  let head = option_args(args)
  let matches = command_spec("", "morphir").parse(argv=head, env=Map([])) catch {
    error => raise @config.Invalid(error.to_string())
  }
  let mut command = ""
  let flags : Map[String, Bool] = Map([])
  let entries : Map[String, Array[String]] = Map([])
  let mut level = Some(matches)
  while level is Some(current) {
    for name, set in current.flags {
      if set {
        flags[name] = true
      }
    }
    for name, values in current.values {
      entries[name] = values
    }
    level = match current.subcommand {
      Some((name, child)) => {
        command = if command == "" { name } else { command + " " + name }
        Some(child)
      }
      None => None
    }
  }
  let schema = command_schema(command)
  if command == "workspace init" && entries.contains("path") {
    raise @config.Invalid(
      "workspace init creates in the current directory; no path argument is accepted",
    )
  }
  for name, values in entries {
    if name == "path" {
      continue
    }
    if values.any(value => value == "") {
      raise @config.Invalid("Missing value for --" + name)
    }
    if values.length() > 1 && !schema.repeatable.contains(name) {
      raise @config.Invalid("Repeated option: --" + name)
    }
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
    if command != "toolchain run" && command != "toolchain exec" {
      raise @config.Invalid("Program arguments require toolchain run or exec")
    }
    Some(args[head.length() + 1:].to_owned())
  } else {
    None
  }
  let help = flags.contains("help") || command == ""
  if !schema.children.is_empty() &&
    command != "" &&
    command != "workspace" &&
    !help {
    raise @config.Invalid("A subcommand is required for " + command)
  }
  { command, flags, entries, forwarded, help, help_text: render_help(command), }
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
fn value(cli : Cli, name : String, fallback~ : String = "") -> String {
  let entries = values(cli, name)
  entries.get(entries.length() - 1).unwrap_or(fallback)
}
