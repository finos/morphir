///|
/// The parser receives explicit argv; host IO and process exit stay in main.
priv struct Cli {
  command : String
  flags : Map[String, Bool]
  entries : Map[String, Array[String]]
  forwarded : Array[String]?
  help : Bool
  help_text : String
}

///|
priv struct CliSchema {
  flags : Array[String]
  options : Array[String]
  repeatable : Array[String]
  positional : Bool
  children : Array[String]
}

///|
let pipeline_options : Array[String] = [
  "project", "frontend", "frontend-provider", "frontend-profile", "backend", "output",
  "config-script", "checkpoint-format", "validation", "target", "build-provider",
  "build-helper", "build-node", "sdk", "home", "timeout", "component",
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
/// `extension-helper` and `node` stay declared so that the commands can
/// refuse them with `extension.option_retired`.
let extension_options : Array[String] = [
  "extension-pin", "extension-helper", "node", "timeout", "cancel-file",
]

///|
let catalog_options : Array[String] = [
  "services-pin", "services-helper", "home", "node", "timeout", "cancel-file", "log-file",
  "log-format",
]

///|
let configuration_option_names : Array[String] = [
  "config", "profiles", "suppress-warning", "discovery-boundary", "log-level",
]

///|
fn configuration_arguments(global : Bool) -> Array[@argparse.OptionArg] {
  configuration_option_names.map(name => {
    @argparse.OptionArg(
      name,
      global~,
      action=Append,
      conflicts_with=if name == "profiles" { ["no-profiles"] } else { [] },
    )
  })
}

///|
fn configuration_flags(global : Bool) -> Array[@argparse.FlagArg] {
  [
    @argparse.FlagArg("isolated", global~),
    @argparse.FlagArg("no-profiles", global~, conflicts_with=["profiles"]),
  ]
}

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
        "compile", "generate", "model", "connected", "project", "toolchain", "mck",
        "notebook", "extension",
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
    "notebook" => children = ["export", "import"]
    "notebook export" => {
      flags = ["evaluate"]
      options = ["output", "format"]
      positional = true
    }
    "notebook import" => {
      options = ["output"]
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
    "compile" => {
      flags = ["file", "directory", "types-only", "log"]
      options = [
        "input", "project", "package", "output", "version", "language", "provider",
        "profile", "model-format", "cancel-file", "log-file", "log-format",
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
    "extension" =>
      children = [
        "describe", "compile", "generate", "bundle", "install", "list", "search",
        "update", "uninstall", "repository",
      ]
    "extension repository" =>
      children = [
        "init", "add", "list", "inspect", "enable", "disable", "remove", "publish",
        "verify",
      ]
    "extension repository init"
    | "extension repository inspect"
    | "extension repository enable"
    | "extension repository disable"
    | "extension repository remove"
    | "extension repository verify" => {
      options = catalog_options
      positional = true
    }
    "extension repository add" => {
      options = catalog_options + ["directory"]
      positional = true
    }
    "extension repository publish" => {
      options = catalog_options + ["repository"]
      positional = true
    }
    "extension repository list" | "extension list" => options = catalog_options
    "extension install" | "extension update" => {
      options = catalog_options + ["repository", "version"]
      positional = true
    }
    "extension search" | "extension uninstall" => {
      options = catalog_options
      positional = true
    }
    "extension bundle" =>
      options = catalog_options +
        [
          "executable", "sha256", "extension-id", "short-id", "version", "platform",
          "output",
        ]
    "extension describe" => options = extension_options
    "extension compile" => {
      options = extension_options +
        ["package", "frontend-profile", "model-format", "output", "ir-version"]
      positional = true
    }
    "extension generate" => {
      options = extension_options +
        ["target", "output", "model-format", "ir-version"]
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
      options = ["frontend", "target", "config-script"]
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
      " <source>"
    } else if path == "extension generate" {
      " <model>"
    } else {
      " [path]"
    }
  }
  text += " [options]\n"
  if path == "compile" {
    text += "\nCompile with the embedded rich engine and publish admitted checkpoints.\n"
    text += "--input is an alternative to the positional project/directory/file path.\n"
    text += "--project selects a workspace member; --package sets the model package name.\n"
    text += "--output is a workspace-relative output root containing compile.dest.\n"
    text += "Languages/providers: moonbit / finos/morphir-moonbit-frontend; elm / finos/morphir-elm.\n"
    text += "Profiles: moonbit-model-stable-v1, moonbit-model-experimental-v1; library, library-origins.\n"
    text += "Defaults retain origins: stable MoonBit or Elm library-origins, Ion binary.\n"
    text += "Formats: ion-binary, ion-text, morphir-json (checked loss refusal).\n"
    text += "Only draft IR version 4 is supported; types-only and provider-specific options refuse.\n"
    text += "JSON returns morphir/command-result 0.1.0; diagnostics go to stderr.\n"
    text += "Validation/compilation failures exit 1; argument syntax errors exit 2.\n"
  } else if path == "eval" {
    text += "\nEvaluate public model functions with the local Scheme provider.\n"
    text += "Checking policy: strict (whole model) or permissive (as code executes).\n"
    text += "Model formats: JSON, YAML, Ion text, Ion binary; stdin requires --model-format.\n"
    text += "Invocation suite codecs are selected separately with --suite-format.\n"
  } else if path == "worksheet" {
    text += "\nEvaluate Scheme expressions with shared definitions and typed source ranges.\n"
  } else if path.has_prefix("notebook") {
    text += "\nShare Scheme worksheets as Jupyter (.ipynb) or source-only DIB (.dib).\n"
    text += "Export accepts --format ipynb|dib, -o/--output and --evaluate. Jupyter is the default.\n"
    text += "DIB --evaluate is refused before evaluation or file writes; saved outputs require Jupyter.\n"
    text += "Import infers its format from the input extension and accepts -o/--output.\n"
    text += "JSON returns morphir/command-result 0.1.0 with outputPath, format, cellCount, skippedCells and evaluated.\n"
    text += "Help returns result.help without effects. JSON-lines wraps one result in the existing result record.\n"
    text += "Diagnostics and skipped-cell warnings use stderr. Invalid input/syntax exits 2, write or timeout failure 1, cancellation 130.\n"
    text += "Evaluation uses the existing worksheet limits and a 120-second deadline; WASI permits source-only export.\n"
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
    text += "\ndescribe, compile and generate run a pinned extension on the CLI's worker host.\n"
    text += "A contract 0.2.0 pin names the artifact (path, sha256), its runtime and an optional descriptor.\n"
    text += "The host probes the worker, then runs one fresh session; no helper or Node runtime is used.\n"
    text += "Process and WASM runtimes run on the native and npm CLIs; WASI builds refuse them with extension.runtime_unavailable.\n"
    text += "Sources and operations come from the extension's claims: compile reads the claimed file extensions.\n"
    text += "compile writes model-envelope.json and model.ionb or model.json, or morphir-ir.json on MEP 0.1.\n"
    text += "generate reads a model envelope or Morphir IR JSON and writes the returned artifacts.\n"
    text += "JSON returns morphir/command-result 0.1.0; diagnostics and guest stderr go to stderr.\n"
    text += "Exit 0 success, 1 failure, 2 refusal, 124 deadline, 130 cancellation, 143 SIGTERM, in every mode.\n"
    text += "Old pins, --extension-helper and --node are refused; see https://github.com/finos/morphir-moonbit/blob/main/apps/morphir/docs/extension.md#migrate-a-pin.\n"
    text += "Local repository/bundle commands use --services-pin and --services-helper.\n"
    text += "They return morphir/command-result 0.1.0, with logs on stderr; failures exit 1.\n"
    text += "Install/update require an exact --version and enabled --repository.\n"
    text += "Only local native process artifacts on the current platform are supported.\n"
    text += "Remote repositories, channel selection and cross-platform probing are not provided.\n"
    text += "\nExample: morphir extension compile src/main.mbt --extension-pin pin.json --package my/pkg --output out\n"
    if path == "extension" {
      text += "\nworker: internal subcommand that the native CLI starts as the WASM worker runtime; users do not run it.\n"
    }
  }
  if !schema.children.is_empty() {
    text += "\nCommands:\n  " + schema.children.join("\n  ") + "\n"
  }
  text += "\nOptions:\n  -h, --help\n  --json\n  --json-lines\n"
  text += "\nConfiguration: --config FILE, --profiles NAME[,NAME] (repeatable), --no-profiles, --suppress-warning CODE (repeatable), --discovery-boundary DIR, --isolated. Diagnostic logging: --log-level trace|debug|info|warn|error|fatal|off. These support --json; help reads no configuration. For mck, place Morphir controls before mck; its child argv remains literal.\n"
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
    flags.append(configuration_flags(true))
  }
  let options = schema.options.map(option => {
    let short = if path.has_prefix("notebook ") && option == "output" {
      Some('o')
    } else {
      None
    }
    @argparse.OptionArg(
      option,
      short?,
      action=Append,
      allow_hyphen_values=hyphen_options.contains(option),
    )
  })
  if path == "" {
    options.append(configuration_arguments(true))
  }
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
fn mck_syntax_spec(routing~ : Bool = false) -> @argparse.Command {
  @argparse.Command(
    "morphir",
    flags=[
      if routing {
        @argparse.FlagArg("help", global=true)
      } else {
        @argparse.FlagArg("help", short='h', global=true)
      },
      @argparse.FlagArg("json", global=true),
      @argparse.FlagArg("json-lines", global=true),
      @argparse.FlagArg("no-banner", global=true, hidden=true),
      ..configuration_flags(false),
    ],
    options=configuration_arguments(false),
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
    if values.length() > 1 &&
      !schema.repeatable.contains(name) &&
      !["profiles", "suppress-warning"].contains(name) {
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
  let cli = {
    command,
    flags,
    entries,
    forwarded,
    help,
    help_text: render_help(command),
  }
  ignore(diagnostic_level(cli))
  ignore(configuration_profiles(cli))
  if values(cli, "config").last() is Some(path) {
    if path.has_suffix(".scm") {
      raise @config.Invalid(
        "Use --config-script for Scheme configuration scripts: " + path,
      )
    }
    if ![".toml", ".yaml", ".yml", ".json", ".json5"].any(extension => {
        path.has_suffix(extension)
      }) {
      raise @config.Invalid("Unsupported configuration format: " + path)
    }
  }
  cli
}

///|
fn diagnostic_level(cli : Cli) -> @diagnostics.DiagnosticLevel? raise {
  values(cli, "log-level")
  .last()
  .map(text => {
    @diagnostics.DiagnosticLevel::parse(text) catch {
      error => raise @config.Invalid(error.message())
    }
  })
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

///|
fn configuration_profiles(cli : Cli) -> @lander_config.ProfileSelection raise {
  if flag(cli, "no-profiles") {
    return Disabled
  }
  let profiles = values(cli, "profiles")
  if profiles.is_empty() {
    Unspecified
  } else {
    Selected(@lander_config.ProfileNames::parse_csv(profiles.join(","))) catch {
      error => raise @config.Invalid(error.message())
    }
  }
}

///|
fn configuration_controls(
  cli : Cli,
  location : @host.Location,
  environment : Map[String, String],
) -> @workspace.ConfigurationOptions raise {
  let selected = values(cli, "config").last()
  @host.configuration_options(
    location,
    environment,
    selected?,
    profiles=configuration_profiles(cli),
    isolated=flag(cli, "isolated"),
    suppress=values(cli, "suppress-warning"),
  )
}
