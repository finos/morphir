///|
/// The section of `apps/morphir/docs/extension.md` that explains how to
/// rewrite an old pin. It is a URL, because the npm package ships no docs.
let extension_migration : String = "https://github.com/finos/morphir-moonbit/blob/main/apps/morphir/docs/extension.md#migrate-a-pin"

///|
let extension_pin_contract : String = "0.2.0"

///|
/// The source snapshot bounds of `extension compile`: documents read, bytes
/// of one file, bytes read in total, directory entries listed and directory
/// depth. Each bound is inclusive.
priv struct ExtensionSourceLimits {
  files : Int32
  file_bytes : Int32
  bytes : Int32
  entries : Int32
  depth : Int32
}

///|
let extension_source_limits : ExtensionSourceLimits = {
  files: 1024,
  file_bytes: 1048576,
  bytes: 2097152,
  entries: 16384,
  depth: 32,
}

///|
/// The directories that the source walk skips, with every other hidden
/// directory: version control, build output and dependencies.
let extension_skipped_directories : Array[String] = [
  ".git", ".mooncakes", "_build", "node_modules", ".venv",
]

///|
/// The three commands that run an extension on the worker host.
priv enum ExtensionCommand {
  Describe
  Compile
  Generate
}

///|
fn ExtensionCommand::of(command : String) -> ExtensionCommand? {
  match command {
    "extension describe" => Some(Describe)
    "extension compile" => Some(Compile)
    "extension generate" => Some(Generate)
    _ => None
  }
}

///|
/// The stable command name of the report.
fn ExtensionCommand::name(self : ExtensionCommand) -> String {
  match self {
    Describe => "extension.describe"
    Compile => "extension.compile"
    Generate => "extension.generate"
  }
}

///|
/// How a command that did not succeed ends. Each status has one exit code,
/// in human and JSON mode.
priv enum ExtensionStatus {
  /// A pin, identity, claim, negotiation or local input check refused the
  /// work before an operation.
  Refused
  /// The guest answered `success: false`, the session failed or the output
  /// could not be published.
  Failed
  /// The session deadline passed.
  TimedOut
  /// The user cancelled the command.
  Cancelled
}

///|
fn ExtensionStatus::exit_code(self : ExtensionStatus) -> Int32 {
  match self {
    Refused => 2
    Failed => 1
    TimedOut => 124
    Cancelled => cancellation_exit_code()
  }
}

///|
/// The error codes of the extension commands. The worker host's own codes
/// keep their names.
priv enum ExtensionCode {
  Worker(@worker.FailureCode)
  PinRequired
  PinInvalid
  PinRetired
  OptionRetired
  DescriptorInvalid
  InputInvalid
  IrVersionMismatch
  OutputExists
  GuestError
  OperationUnsuccessful
  ResultInvalid
  OutputFailed
  HostFailed
  DeadlinePassed
  OperationCancelled
}

///|
fn ExtensionCode::name(self : ExtensionCode) -> String {
  match self {
    Worker(code) => code.to_string()
    PinRequired => "extension.pin_required"
    PinInvalid => "extension.pin_invalid"
    PinRetired => "extension.pin_retired"
    OptionRetired => "extension.option_retired"
    DescriptorInvalid => "extension.descriptor_invalid"
    InputInvalid => "extension.input_invalid"
    IrVersionMismatch => "extension.ir_version_mismatch"
    OutputExists => "extension.output_exists"
    GuestError => "extension.guest_error"
    OperationUnsuccessful => "extension.operation_unsuccessful"
    ResultInvalid => "extension.result_invalid"
    OutputFailed => "extension.output_failed"
    HostFailed => "extension.host_failed"
    DeadlinePassed => "extension.deadline"
    OperationCancelled => "extension.cancelled"
  }
}

///|
priv suberror ExtensionError {
  ExtensionError(
    status~ : ExtensionStatus,
    code~ : ExtensionCode,
    message~ : String
  )
}

///|
fn refused(code : ExtensionCode, message : String) -> ExtensionError {
  ExtensionError(status=Refused, code~, message~)
}

///|
fn failed(code : ExtensionCode, message : String) -> ExtensionError {
  ExtensionError(status=Failed, code~, message~)
}

///|
fn input_invalid(message : String) -> ExtensionError {
  refused(InputInvalid, message)
}

///|
/// The error for the way a worker session ended.
fn ending_error(ending : @worker.Ending) -> ExtensionError {
  match ending {
    Refused(code~, message~) => refused(Worker(code.code()), message)
    Failed(Host(code~, message~)) => failed(Worker(code.code()), message)
    Failed(Guest(code~, message~, ..)) =>
      failed(GuestError, "the guest answered error \{code}: \{message}")
    Deadline =>
      ExtensionError(
        status=TimedOut,
        code=DeadlinePassed,
        message="the session deadline passed",
      )
    Cancelled =>
      ExtensionError(
        status=Cancelled,
        code=OperationCancelled,
        message="the command was cancelled",
      )
  }
}

///|
fn refusal_error(refusal : @worker.Refusal) -> ExtensionError {
  match refusal {
    Refusal(code~, message~) => refused(Worker(code.code()), message)
  }
}

///|
/// An explicit worker pin in contract 0.2.0: the artifact and its runtime,
/// the same shape the installed catalog records, an optional release
/// descriptor and the origin.
priv struct ExtensionPin {
  spec : @worker.WorkerSpec
  descriptor : @worker.ArtifactRef?
  origin : String
}

///|
let extension_pin_fields : Array[String] = [
  "contractVersion", "artifact", "runtime", "descriptor", "origin",
]

///|
/// Decodes a pin at the boundary. A retired contract, an unknown field, a
/// relative path or a missing digest is refused, never ignored.
fn ExtensionPin::decode(
  value : Json,
  style : @worker.PathStyle,
) -> ExtensionPin raise ExtensionError {
  guard value is Object(fields) else {
    raise refused(PinInvalid, "the pin is not a JSON object")
  }
  match fields.get("contractVersion") {
    Some(String("0.2.0")) => ()
    Some(String("0.1.0" | "0.1.0-draft.1" as old)) =>
      raise refused(
        PinRetired,
        "pin contract \{old} is retired: write a contract \{extension_pin_contract} pin with an artifact and a runtime (see \{extension_migration})",
      )
    _ =>
      raise refused(
        PinInvalid,
        "the pin needs contractVersion \{extension_pin_contract}",
      )
  }
  for name, _ in fields {
    guard extension_pin_fields.contains(name) else {
      raise refused(
        PinInvalid,
        "the pin has the field \{name}, which contract \{extension_pin_contract} does not have",
      )
    }
  }
  guard fields.get("origin") is Some(String(origin)) &&
    origin != "" &&
    origin.length() <= 2048 &&
    !origin.contains_char('\u0000') else {
    raise refused(PinInvalid, "the pin needs an origin of 1 to 2048 characters")
  }
  let spec = @worker.WorkerSpec::from_json(value, style) catch {
    error => raise refused(PinInvalid, "the pin is not valid: \{error}")
  }
  let descriptor = match fields.get("descriptor") {
    None => None
    Some(descriptor) =>
      Some(
        @worker.ArtifactRef::from_json(descriptor, style) catch {
          error =>
            raise refused(
              PinInvalid,
              "the pin descriptor is not valid: \{error}",
            )
        },
      )
  }
  { spec, descriptor, origin, }
}

///|
/// Refuses the options of the retired helper routes. The worker host needs
/// no helper and no Node runtime.
fn extension_retired_options(cli : Cli) -> Unit raise ExtensionError {
  for option in ["extension-helper", "node"] {
    if !values(cli, option).is_empty() {
      raise refused(
        OptionRetired,
        "--\{option} is retired: the CLI runs extensions on its own worker host. Remove the option (see \{extension_migration})",
      )
    }
  }
}

///|
/// The local inputs of one command, checked before any worker starts.
priv struct ExtensionInputs {
  path : String
  output : String
  package_name : String
  codec : @worker.ModelCodec?
  profile : String
  /// `--ir-version`: an exact IR version, or a major version.
  ir_version : @worker.IrVersionName?
  target : String
  timeout_ms : Int32
  /// `--language`: the claimed language to compile, when the extension
  /// claims several.
  language : @ids.LanguageId?
  /// `--source-base`: the directory that document URIs are relative to.
  source_base : String?
}

///|
fn ExtensionInputs::read(
  cli : Cli,
  command : ExtensionCommand,
) -> ExtensionInputs raise ExtensionError {
  let path = value(cli, "path")
  let model_format = value(cli, "model-format")
  let timeout_ms = build_timeout(value(cli, "timeout", fallback="60000")) catch {
    _ => raise input_invalid("--timeout needs a whole number of milliseconds")
  }
  ignore(
    @worker.Deadline::of_ms(timeout_ms) catch {
      _ => raise input_invalid("--timeout allows at most 594000 ms")
    },
  )
  let ir_version = match value(cli, "ir-version") {
    "" => None
    text =>
      Some(
        @worker.IrVersionName::parse(text) catch {
          _ => raise input_invalid("--ir-version \{text} is not an IR version")
        },
      )
  }
  let inputs : ExtensionInputs = {
    path,
    output: "",
    package_name: value(cli, "package"),
    codec: None,
    profile: value(cli, "frontend-profile"),
    ir_version,
    target: value(cli, "target"),
    timeout_ms,
    language: None,
    source_base: None,
  }
  match command {
    Describe => {
      if path != "" {
        raise input_invalid("describe takes no input")
      }
      if value(cli, "output") != "" {
        raise input_invalid("describe writes no output")
      }
      inputs
    }
    Compile | Generate => {
      if path == "" || path == "-" {
        raise input_invalid(
          if command is Compile {
            "compile needs a source file or directory"
          } else {
            "generate needs a model file"
          },
        )
      }
      if command is Compile && inputs.package_name == "" {
        raise input_invalid("compile needs --package")
      }
      let codec : @worker.ModelCodec? = match (command, model_format) {
        (_, "") => None
        (Compile, "ion" | "ion-binary") => Some(IonBinary)
        (Compile, "json" | "morphir-json") => Some(MorphirJson)
        (Compile, other) =>
          raise input_invalid(
            "--model-format \{other} is not ion-binary or morphir-json",
          )
        (_, _) =>
          raise input_invalid("generate takes the model format from its input")
      }
      let output = value(cli, "output")
      if output == "" {
        raise input_invalid("\{command.name()} needs --output")
      }
      let output = fresh_output(output) catch {
        @config.Invalid(message) => raise refused(OutputExists, message)
        error => raise failed(OutputFailed, @host.error_message(error))
      }
      let parent = output_parent(output)
      guard (@platform.kind(parent) catch { _ => -1 }) == 2 else {
        raise input_invalid(
          "the parent directory \{parent} of --output \{output} does not exist",
        )
      }
      let language = match value(cli, "language") {
        "" => None
        text =>
          Some(
            @ids.LanguageId::parse(text) catch {
              _ =>
                raise input_invalid("--language \{text} is not a language ID")
            },
          )
      }
      let source_base = match value(cli, "source-base") {
        "" => None
        base => Some(base)
      }
      { ..inputs, codec, output, language, source_base, }
    }
  }
}

///|
/// The parent directory of an output path: `.` for a bare name, the root for
/// a path directly under it.
fn output_parent(output : String) -> String {
  let slash = output.rev_find("/")
  let backslash = output.rev_find("\\")
  let index = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) | (None, Some(a)) => Some(a)
    (None, None) => None
  }
  match index {
    None => "."
    Some(0) => output[:1].to_owned()
    // A drive root such as `C:\` keeps its separator.
    Some(at) if at == 2 && output[1:2] == ":" => output[:3].to_owned()
    Some(at) => output[:at].to_owned()
  }
}

///|
/// One source document of a compile request.
priv struct ExtensionSource {
  uri : String
  text : String
}

///|
/// One source file that the walk found: its document URI, its path relative
/// to the source base for messages, and its path on the host.
priv struct ExtensionSourceFile {
  uri : String
  relative : String
  path : String
}

///|
/// Encodes one name as an RFC 3986 path segment. Unreserved characters
/// (letters, digits, `-`, `.`, `_` and `~`) stay as they are; every other
/// byte of the UTF-8 name is percent-encoded with uppercase digits, so a
/// URI never holds a raw `%`, `?`, `#`, `\`, `:`, space, control character
/// or non-ASCII character.
fn extension_uri_segment(name : String) -> String {
  let digits : FixedArray[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  ]
  let builder = StringBuilder()
  for byte in @utf8.encode(name) {
    match byte.to_char() {
      'a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-' | '.' | '_' | '~' as char =>
        builder.write_char(char)
      _ => {
        let code = byte.to_int()
        builder.write_char('%')
        builder.write_char(digits[code / 16])
        builder.write_char(digits[code % 16])
      }
    }
  }
  builder.to_string()
}

///|
/// The URI of a single file without `--source-base`. A clean relative path
/// keeps its nesting; otherwise only the file name is declared. Absolute
/// host paths never enter the model's source provenance. Each segment is
/// percent-encoded.
fn extension_document_uri(path : String) -> String {
  let parts = path
    .replace_all(old="\\", new="/")
    .split("/")
    .map(part => part.to_owned())
    .to_array()
  let name = parts[parts.length() - 1]
  let kept = if mck_absolute(path) ||
    parts.any(part => {
      part == "" || part == "." || part == ".." || part.contains(":")
    }) {
    [name]
  } else {
    parts
  }
  kept.map(extension_uri_segment).join("/")
}

///|
/// The directory that document URIs are relative to (SRC-1): `--source-base`
/// when the user gives it, else the input directory itself. The current
/// directory makes relative paths absolute.
priv struct ExtensionSourceBase {
  given : String?
  cwd : String
  style : @worker.PathStyle
}

///|
/// The names from the source base down to `path`, which must be the base or
/// below it. Both paths are made absolute against the current directory and
/// normalized without reading the file system. Without `--source-base` the
/// input is its own base, so there are no names.
fn ExtensionSourceBase::segments(
  self : ExtensionSourceBase,
  path : String,
) -> Array[String] raise ExtensionError {
  guard self.given is Some(base) else { return [] }
  let relative = match self.style {
    Posix => {
      let absolute = (text : String) => {
        let path = @path_posix.Path(text)
        let path = if path.is_absolute() {
          path
        } else {
          @path_posix.Path(self.cwd).join(path)
        }
        path.normalize()
      }
      let relative = absolute(path).relative(base=absolute(base))
      if relative.is_absolute() {
        None
      } else {
        Some(relative.0)
      }
    }
    Windows => {
      let absolute = (text : String) => {
        let path = @path_windows.Path(text)
        let path = if path.is_absolute() {
          path
        } else {
          @path_windows.Path(self.cwd).join(path)
        }
        path.normalize()
      }
      let relative = absolute(path).relative(base=absolute(base))
      if relative.is_absolute() {
        None
      } else {
        Some(relative.0.replace_all(old="\\", new="/"))
      }
    }
  }
  let segments = match relative {
    Some(text) =>
      text
      .split("/")
      .filter(part => part != "" && part != ".")
      .map(part => part.to_owned())
      .collect()
    None => [".."]
  }
  if segments.contains("..") {
    raise input_invalid(
      "\{path} is not at or below the source base \{base}; give a --source-base that contains it",
    )
  }
  segments
}

///|
/// The language of a compile (SEL-3): the only language that the extension
/// claims, or the claimed language that `--language` names. The CLI holds
/// no list of languages.
fn extension_language(
  claims : @worker.Claims,
  selected : @ids.LanguageId?,
) -> @worker.LanguageClaim raise ExtensionError {
  let names = claims.languages
    .map(language => language.language_id.to_string())
    .join(", ")
  match selected {
    Some(id) =>
      match claims.languages.search_by(language => language.language_id == id) {
        Some(index) => claims.languages[index]
        None =>
          raise refused(
            Worker(CapabilityUnavailable),
            "\{claims.extension_id} does not claim the language \{id}; it claims \{if names == "" { "no language" } else { names }}",
          )
      }
    None =>
      match claims.languages {
        [only] => only
        [] =>
          raise refused(
            Worker(CapabilityUnavailable),
            "\{claims.extension_id} claims no source language",
          )
        _ =>
          raise input_invalid(
            "\{claims.extension_id} claims the languages \{names}: select one with --language",
          )
      }
  }
}

///|
/// A frontend that does not claim `multiDocument` compiles exactly one
/// document for each request, so a snapshot with more is refused before any
/// session.
fn extension_document_count(
  claims : @worker.Claims,
  documents : Array[ExtensionSource],
) -> Unit raise ExtensionError {
  if documents.length() > 1 && !claims.frontend_flags.multi_document {
    raise refused(
      Worker(CapabilityUnavailable),
      "\{claims.extension_id} \{claims.version} does not claim multiDocument and compiles one source file for each request; the sources have \{documents.length()} files",
    )
  }
}

///|
/// Order by UTF-16 code unit, so that `app` comes before `nested`. `String`
/// compares lengths first. A URI is ASCII, so this is its byte order.
fn extension_name_order(left : String, right : String) -> Int32 {
  let length = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<length {
    if left.code_unit_at(index) != right.code_unit_at(index) {
      return left.code_unit_at(index).compare(right.code_unit_at(index))
    }
  }
  left.length().compare(right.length())
}

///|
/// Why a directory entry name cannot become a URI segment, or `None` when it
/// can. An empty name, `.` or `..` would make the URI traverse, and a name
/// with `/` or NUL is not one entry. Every other name is percent-encoded.
fn extension_source_name(name : String) -> String? {
  if name == "" || name == "." || name == ".." {
    Some("is empty, . or ..")
  } else if name.contains("/") {
    Some("contains a path separator")
  } else if name.contains_char('\u0000') {
    Some("contains NUL")
  } else {
    None
  }
}

///|
/// Sorts the files by the whole URI in byte order and refuses two files
/// with the same URI.
fn extension_source_order(
  files : Array[ExtensionSourceFile],
) -> Array[ExtensionSourceFile] raise ExtensionError {
  let sorted = files.copy()
  sorted.sort_by((left, right) => extension_name_order(left.uri, right.uri))
  for index in 1..<sorted.length() {
    if sorted[index].uri == sorted[index - 1].uri {
      raise input_invalid(
        "the source files \{sorted[index - 1].relative} and \{sorted[index].relative} have the same URI \{sorted[index].uri}",
      )
    }
  }
  sorted
}

///|
/// Reads a bounded snapshot of the source file or directory. Only files with
/// a claimed extension are read. Each URI is the path relative to the source
/// base, with percent-encoded segments. Without `--source-base`, a directory
/// is its own base and a single file keeps the rule of
/// `extension_document_uri`. Hidden, build and dependency directories are
/// skipped; a link, a special entry or an unsafe name is refused. The
/// documents are in URI byte order.
fn extension_sources(
  path : String,
  extensions : Array[String],
  check : () -> Unit raise ExtensionError,
  base~ : ExtensionSourceBase,
  limits~ : ExtensionSourceLimits = extension_source_limits,
) -> Array[ExtensionSource] raise ExtensionError {
  let files : Array[ExtensionSourceFile] = []
  let mut entries = 0
  let claimed = (name : String) => {
    extensions.any(extension => name.has_suffix(extension))
  }
  fn walk(
    directory : String,
    names : Array[String],
    depth : Int32,
  ) -> Unit raise ExtensionError {
    check()
    if depth > limits.depth {
      raise input_invalid(
        "the source directory \{names.join("/")} is deeper than the limit of \{limits.depth} directories",
      )
    }
    let listed = @platform.list_bounded(directory, 4096) catch {
      error =>
        raise input_invalid(
          "cannot list \{directory}: \{@host.error_message(error)}",
        )
    }
    listed.sort_by(extension_name_order)
    for name in listed {
      entries += 1
      if entries > limits.entries {
        raise input_invalid(
          "the source directory has more entries than the limit of \{limits.entries} entries",
        )
      }
      let relative = [..names, name]
      if extension_source_name(name) is Some(reason) {
        raise input_invalid(
          "the source entry \{repr(name)} in \{names.join("/")} \{reason}",
        )
      }
      let full = directory + "/" + name
      match (@platform.kind(full) catch { _ => -1 }) {
        1 =>
          if claimed(name) {
            files.push({
              uri: relative.map(extension_uri_segment).join("/"),
              relative: relative.join("/"),
              path: full,
            })
          }
        2 =>
          if !name.has_prefix(".") &&
            !extension_skipped_directories.contains(name) {
            walk(full, relative, depth + 1)
          }
        _ =>
          raise input_invalid(
            "\{relative.join("/")} is a link or a special file",
          )
      }
    }
  }

  // An explicit source base is checked before the input is read.
  let explicit = match base.given {
    Some(_) => Some(base.segments(path))
    None => None
  }
  match (@platform.kind(path) catch { _ => -1 }) {
    1 => {
      if !claimed(path) {
        raise input_invalid(
          "\{path} does not have a claimed file extension (\{extensions.join(", ")})",
        )
      }
      let file : ExtensionSourceFile = match explicit {
        None => { uri: extension_document_uri(path), relative: path, path, }
        Some([]) =>
          raise input_invalid(
            "\{path} is the source base itself; give a --source-base above it",
          )
        Some(names) =>
          {
            uri: names.map(extension_uri_segment).join("/"),
            relative: names.join("/"),
            path,
          }
      }
      files.push(file)
    }
    2 => walk(path, explicit.unwrap_or([]), 0)
    _ => raise input_invalid("\{path} is not a regular file or a directory")
  }
  if files.is_empty() {
    raise input_invalid(
      "no source file in \{path} has a claimed file extension (\{extensions.join(", ")})",
    )
  }
  if files.length() > limits.files {
    raise input_invalid(
      "the sources have \{files.length()} documents, more than the limit of \{limits.files} documents",
    )
  }
  let documents : Array[ExtensionSource] = []
  let mut total = 0
  for file in extension_source_order(files) {
    check()
    let bytes = @platform.read_input(file.path, limits.file_bytes) catch {
      @platform.IOError("input.limit") =>
        raise input_invalid(
          "the source file \{file.uri} is larger than the limit of \{limits.file_bytes} bytes for one file",
        )
      error =>
        raise input_invalid(
          "cannot read \{file.relative}: \{@host.error_message(error)}",
        )
    }
    total += bytes.length()
    if total > limits.bytes {
      raise input_invalid(
        "the sources are larger than the limit of \{limits.bytes} bytes of source text in total",
      )
    }
    let text = @utf8.decode(bytes[:]) catch {
      _ => raise input_invalid("the source file \{file.uri} is not UTF-8 text")
    }
    documents.push({ uri: file.uri, text, })
  }
  documents
}

///|
/// The line of a compile, from the shared decision of the host package
/// (`LineChoice::compile`). `--model-format` and `--ir-version` each narrow the
/// offer of the model line, and together they intersect. No matching tuple runs
/// on MEP 0.1 with a warning when the claims show that the extension serves the
/// request there, and is `extension.tuple_unavailable` otherwise.
/// `--frontend-profile` has no meaning on MEP 0.1, so it needs a tuple. For an
/// extension that claims only MEP 0.1, `--ir-version` selects from the claimed
/// frontend IR versions (`extension_ir_version`).
fn extension_compile_offer(
  claims : @worker.Claims,
  codec : @worker.ModelCodec?,
  ir_version : @worker.IrVersionName?,
  model_only~ : Bool = false,
) -> @worker.LineChoice raise ExtensionError {
  if claims.compile_operation() is Compile && codec is Some(IonBinary) {
    raise input_invalid(
      "\{claims.extension_id} compiles on MEP 0.1, which returns Morphir JSON",
    )
  }
  @worker.LineChoice::compile(claims, codec?, ir_version?, model_only~) catch {
    refusal => raise refusal_error(refusal)
  }
}

///|
/// The line of a generate and what it sends, from the shared decision of the
/// host package (`GenerateChoice`). A model envelope and plain Morphir IR JSON
/// each go on the model line when the extension claims their tuple. Otherwise
/// they go on MEP 0.1 with a warning when the claims show that it serves their
/// IR version there, and are `extension.tuple_unavailable` when not.
fn extension_generate_input(
  inputs : ExtensionInputs,
  claims : @worker.Claims,
  bytes : Bytes,
  model : Json,
) -> @worker.GenerateChoice raise ExtensionError {
  match extension_envelope_tuple(model) {
    Some(tuple) =>
      @worker.GenerateChoice::of_envelope(claims, model, tuple) catch {
        @worker.Refusal(..) as refusal => raise refusal_error(refusal)
        @worker.InvalidModelEnvelope(_) as error =>
          raise input_invalid("\{inputs.path}: \{error}")
        error => raise failed(HostFailed, @host.error_message(error))
      }
    None => {
      guard !claims.on_model_line() ||
        extension_format_version(model) is Some(_) else {
        raise input_invalid("\{inputs.path} has no formatVersion")
      }
      @worker.GenerateChoice::of_plain_ir(claims, bytes, model) catch {
        refusal => raise refusal_error(refusal)
      }
    }
  }
}

///|
/// The major part of an IR version name: `4` for `4.0.0`.
fn extension_ir_major(name : String) -> String {
  match name.find(".") {
    Some(index) => name[:index].to_owned()
    None => name
  }
}

///|
/// Two IR version names agree when they are equal, or when one of them names
/// only a major version and the majors are equal: `4` agrees with `4.0.0`,
/// `4.0.0` does not agree with `4.1.0`. It checks what a guest returned.
fn extension_ir_agrees(left : String, right : String) -> Bool {
  left == right ||
  (
    (!left.contains(".") || !right.contains(".")) &&
    extension_ir_major(left) == extension_ir_major(right)
  )
}

///|
/// The format version of a Morphir IR JSON document, as text: `3` for
/// `"formatVersion": 3`, `4.0.0` for `"formatVersion": "4.0.0"`.
fn extension_format_version(ir : Json) -> String? {
  guard ir is Object(fields) else { return None }
  match fields.get("formatVersion") {
    Some(String(text)) => Some(text)
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => Some(number.to_int().to_string())
    _ => None
  }
}

///|
/// The claimed IR version for a MEP 0.1 call: the one named by `--ir-version`,
/// or the only claimed version. An exact claimed name comes first. A
/// major-only name such as `4` selects the highest claimed version with that
/// major. A full name that is not claimed is refused, also when its major is
/// claimed.
fn extension_ir_version(
  claims : @worker.Claims,
  claimed : Array[@worker.IrVersionName],
  selected : @worker.IrVersionName?,
) -> String? raise ExtensionError {
  guard selected is Some(selected) else {
    let names = claimed.map(name => name.to_string())
    return match names {
      [] => None
      [only] => Some(only)
      _ =>
        raise input_invalid(
          "\{claims.extension_id} claims IR versions \{names.join(", ")}: select one with --ir-version",
        )
    }
  }
  if claimed.contains(selected) {
    return Some(selected.to_string())
  }
  match
    @worker.IrVersionName::highest(
      claimed.filter(name => name.serves(selected)),
    ) {
    Some(version) => Some(version.to_string())
    None =>
      raise refused(
        Worker(CapabilityUnavailable),
        "\{claims.extension_id} does not claim IR version \{selected}",
      )
  }
}

///|
/// The claimed target: `--target`, or the only claimed target.
fn extension_target(
  claims : @worker.Claims,
  selected : String,
) -> String raise ExtensionError {
  let targets = claims.targets.map(target => target.to_string())
  if selected == "" {
    guard targets is [only] else {
      raise input_invalid(
        "\{claims.extension_id} claims targets \{targets.join(", ")}: select one with --target",
      )
    }
    return only
  }
  guard targets.contains(selected) else {
    raise refused(
      Worker(CapabilityUnavailable),
      "\{claims.extension_id} does not claim the target \{selected}",
    )
  }
  selected
}

///|
fn extension_documents(
  language : @ids.LanguageId,
  documents : Array[ExtensionSource],
) -> Json {
  {
    "documents": Json::array(
      documents.map(document => {
        "uri": document.uri,
        "languageId": language.to_string(),
        "version": 0,
        "text": document.text,
      }),
    ),
  }
}

///|
/// The parameters of a compile call: with the agreed tuple on the model line,
/// so `options.irVersion` and `contextDigest` follow that tuple, or with no
/// tuple on MEP 0.1, which sends the selected `ir_version`.
fn extension_compile_params(
  inputs : ExtensionInputs,
  claims : @worker.Claims,
  tuple : @worker.ModelTuple?,
  language : @ids.LanguageId,
  documents : Array[ExtensionSource],
  ir_version : String?,
) -> Map[String, Json] raise ExtensionError {
  match tuple {
    Some(tuple) => {
      let options : Map[String, Json] = {
        "typesOnly": false,
        "irVersion": tuple.ir_version.to_string(),
      }
      if inputs.profile != "" {
        options["profile"] = Json::string(inputs.profile)
      }
      // The declared context is the package and options; there are no
      // dependencies or incremental baselines.
      let context : Json = {
        "package": inputs.package_name,
        "options": Json::object(options),
      }
      {
        "languageId": language.to_string(),
        "sources": extension_documents(language, documents),
        "package": { "name": inputs.package_name },
        "options": Json::object(options),
        // The session adds the agreed tuple as the output.
        "contextDigest": extension_sha256(@utf8.encode(context.stringify())),
      }
    }
    None => {
      if inputs.profile != "" {
        raise input_invalid(
          "--frontend-profile needs a model compile, which \{claims.extension_id} does not claim",
        )
      }
      let options : Map[String, Json] = { "typesOnly": false }
      if ir_version is Some(version) {
        options["irVersion"] = Json::string(version)
      }
      {
        "languageId": language.to_string(),
        "sources": extension_documents(language, documents),
        "package": { "name": inputs.package_name },
        "dependencies": [],
        "options": Json::object(options),
      }
    }
  }
}

///|
/// The model tuple of a model envelope, or `None` for plain Morphir IR JSON.
fn extension_envelope_tuple(
  value : Json,
) -> @worker.ModelTuple? raise ExtensionError {
  guard value is Object(fields) && fields.contains("envelopeVersion") else {
    return None
  }
  guard fields.get("envelopeVersion") is Some(String(envelope)) &&
    fields.get("irVersion") is Some(String(ir)) &&
    fields.get("profile") is Some(String(profile)) &&
    fields.get("payload") is Some(Object(payload)) &&
    payload.get("codec") is Some(String(codec)) else {
    raise input_invalid("the model envelope has no complete tuple")
  }
  Some(
    @worker.ModelTuple::parse(
      "morphir.backend.generateModel", profile, codec, envelope, ir,
    ) catch {
      error =>
        raise input_invalid("the model envelope is not supported: \{error}")
    },
  )
}

///|
/// The parameters of a generate call on the negotiated line. A fallback has
/// checked the claimed version already, and `--ir-version` checks the model's
/// version as it does on the model line.
fn extension_generate_params(
  inputs : ExtensionInputs,
  claims : @worker.Claims,
  envelope : @worker.ModelTuple?,
  fallback : @worker.LegacyFallback?,
  model : Json,
) -> Map[String, Json] raise ExtensionError {
  let target = extension_target(claims, inputs.target)
  match envelope {
    Some(tuple) => {
      if inputs.ir_version is Some(selected) &&
        !tuple.ir_version.serves(selected) {
        raise refused(
          IrVersionMismatch,
          "--ir-version \{selected} differs from the model's IR \{tuple.ir_version}",
        )
      }
      let identity : Json = match model {
        Object(fields) =>
          {
            "target": target,
            "modelId": fields.get("modelId").unwrap_or(Json::null()),
            "revision": fields.get("revision").unwrap_or(Json::null()),
          }
        _ => Json::null()
      }
      {
        "model": model,
        "input": tuple.to_json(),
        "target": target,
        "contextDigest": extension_sha256(@utf8.encode(identity.stringify())),
      }
    }
    None if fallback is Some(fallback) => {
      if inputs.ir_version is Some(selected) && !fallback.serves(selected) {
        raise refused(
          IrVersionMismatch,
          "--ir-version \{selected} differs from the IR version of \{inputs.path}",
        )
      }
      { "ir": model, "target": target, "options": {} }
    }
    None => {
      // On MEP 0.1, irVersion is a frontend compile option: a backend reads
      // the IR version from the IR's formatVersion. --ir-version is a check
      // of the model's version, and the backend must claim that version.
      let claimed = claims.backend_ir_versions
      if inputs.ir_version is Some(_) || !claimed.is_empty() {
        guard extension_format_version(model) is Some(text) else {
          raise input_invalid("\{inputs.path} has no formatVersion")
        }
        let format = @worker.IrVersionName::parse(text) catch {
          _ =>
            raise input_invalid(
              "\{inputs.path} has formatVersion \{text}, which is not an IR version",
            )
        }
        if inputs.ir_version is Some(selected) && !format.serves(selected) {
          raise refused(
            IrVersionMismatch,
            "\{inputs.path} has formatVersion \{format}; the selected IR version is \{selected}",
          )
        }
        ignore(extension_ir_version(claims, claimed, Some(format)))
      }
      { "ir": model, "target": target, "options": {} }
    }
  }
}

///|
/// The decoded payload must match the tuple, length and digest that the
/// guest declared.
fn extension_model_bytes(
  result : Json,
  tuple : @worker.ModelTuple,
) -> (Json, Bytes) raise ExtensionError {
  guard result is Object(fields) &&
    fields.get("model") is Some(Object(model_fields) as model) &&
    model_fields.get("profile") == Some(Json::string(tuple.profile.to_string())) &&
    model_fields.get("envelopeVersion") ==
    Some(Json::string(tuple.envelope_version.to_string())) &&
    model_fields.get("irVersion") ==
    Some(Json::string(tuple.ir_version.to_string())) &&
    model_fields.get("payload") is Some(Object(payload)) &&
    payload.get("codec") == Some(Json::string(tuple.codec.to_string())) &&
    payload.get("content") is Some(String(content)) &&
    payload.get("sha256") is Some(String(digest)) &&
    payload.get("decodedByteLength") is Some(Number(length, ..)) else {
    raise failed(
      ResultInvalid,
      "the compile result has no model of the agreed tuple",
    )
  }
  let bytes = @base64.decode(content) catch {
    _ => raise failed(ResultInvalid, "the model payload is not base64")
  }
  guard bytes.length().to_double() == length &&
    extension_sha256(bytes) == digest else {
    raise failed(
      ResultInvalid,
      "the model payload does not match its declared length and SHA-256",
    )
  }
  (model, bytes)
}

///|
/// A Morphir JSON model must be of the agreed tuple's IR version: its
/// `formatVersion` must agree with the tuple, under the negotiated limits. The
/// host does not read an Ion payload; a consumer of the Ion model checks it.
fn extension_model_format(
  bytes : Bytes,
  tuple : @worker.ModelTuple,
  limits : @worker.ModelLimits,
) -> Unit raise ExtensionError {
  guard tuple.codec is MorphirJson else { return }
  let document = @utf8.decode(bytes[:]) catch {
    _ => raise failed(ResultInvalid, "the JSON model payload is not UTF-8 text")
  }
  let model = @model_wire.parse_bounded(
    document,
    max_depth=limits.depth,
    max_nodes=limits.nodes,
    max_string_units=limits.decoded_bytes,
  ) catch {
    _ =>
      raise failed(
        ResultInvalid,
        "the JSON model payload is not a bounded JSON document",
      )
  }
  guard extension_format_version(model) is Some(format) else {
    raise failed(ResultInvalid, "the JSON model payload has no formatVersion")
  }
  let expected = tuple.ir_version.to_string()
  if !extension_ir_agrees(format, expected) {
    raise failed(
      ResultInvalid,
      "the JSON model payload has formatVersion \{format}; the agreed tuple has IR \{expected}",
    )
  }
}

///|
/// The artifacts of a generate result, confined to the output directory.
fn extension_generated(
  result : Json,
) -> Array[(String, Bytes)] raise ExtensionError {
  extension_artifacts(result) catch {
    @config.Invalid(message) => raise failed(ResultInvalid, message)
    error => raise failed(ResultInvalid, @host.error_message(error))
  }
}

///|
/// The plain Morphir IR JSON of a MEP 0.1 compile result. The IR version that
/// the result reports and the IR's format version must agree with the
/// selected IR version, and the IR must decode with the versioned JSON codec
/// of that version.
fn extension_ir_file(
  result : Json,
  selected : String?,
) -> Bytes raise ExtensionError {
  guard result is Object(fields) && fields.get("ir") is Some(Object(_) as ir) else {
    raise failed(ResultInvalid, "the compile result has no IR object")
  }
  guard extension_format_version(ir) is Some(format) else {
    raise failed(ResultInvalid, "the compile result's IR has no formatVersion")
  }
  let reported = match fields.get("irVersion") {
    None => None
    Some(String(version)) => Some(version)
    Some(_) => raise failed(ResultInvalid, "the result's irVersion is not text")
  }
  let expected = selected.unwrap_or(reported.unwrap_or(format))
  if reported is Some(version) && !extension_ir_agrees(version, expected) {
    raise failed(
      ResultInvalid,
      "the result reports IR version \{version}; the selected IR version is \{expected}",
    )
  }
  if !extension_ir_agrees(format, expected) {
    raise failed(
      ResultInvalid,
      "the result's IR has formatVersion \{format}; the selected IR version is \{expected}",
    )
  }
  ignore(
    @versioned_json.from_json(ir) catch {
      error =>
        raise failed(
          ResultInvalid,
          "the result's IR is not valid Morphir IR \{format} JSON: \{@host.error_message(error)}",
        )
    },
  )
  @utf8.encode(ir.stringify())
}

///|
/// The files that a successful call publishes, decided before anything is
/// written.
fn extension_files(
  command : ExtensionCommand,
  agreed : @worker.ModelTuple?,
  result : Json,
  ir_version : String?,
  limits : @worker.ModelLimits,
) -> Array[(String, Bytes)] raise ExtensionError {
  match (command, agreed) {
    (Compile, Some(tuple)) => {
      let (model, bytes) = extension_model_bytes(result, tuple)
      extension_model_format(bytes, tuple, limits)
      [
        ("model-envelope.json", @utf8.encode(model.stringify())),
        (
          if tuple.codec is IonBinary {
            "model.ionb"
          } else {
            "model.json"
          },
          bytes,
        ),
      ]
    }
    (Compile, None) =>
      [("morphir-ir.json", extension_ir_file(result, ir_version))]
    (Generate, _) => extension_generated(result)
    (Describe, _) => []
  }
}

///|
/// Reads the release descriptor of a pin before any worker starts: its
/// digest, the one entry for the pinned artifact and the claims recorded
/// there. A bad descriptor starts no process.
fn extension_descriptor(
  descriptor : @worker.ArtifactRef,
  artifact : @worker.Sha256,
) -> @worker.Claims raise ExtensionError {
  guard descriptor.source is File(path) else {
    raise refused(DescriptorInvalid, "the descriptor is not a file")
  }
  let bytes = @platform.read_input(path.to_string(), 1048576) catch {
    error =>
      raise refused(
        DescriptorInvalid,
        "cannot read the descriptor \{path}: \{@host.error_message(error)}",
      )
  }
  let actual = @worker.Sha256::of(bytes)
  guard actual == descriptor.sha256 else {
    raise refused(
      Worker(DigestMismatch),
      "the descriptor has SHA-256 \{actual}; the pin names \{descriptor.sha256}",
    )
  }
  let document = @utf8.decode(bytes[:]) catch {
    _ => raise refused(DescriptorInvalid, "the descriptor is not UTF-8 JSON")
  }
  let parsed = @model_wire.parse_bounded(
    document,
    max_depth=64,
    max_nodes=100000,
    max_string_units=1048576,
  ) catch {
    _ => raise refused(DescriptorInvalid, "the descriptor is not JSON")
  }
  guard parsed is Object(fields) &&
    fields.get("artifacts") is Some(Array(entries)) else {
    raise refused(DescriptorInvalid, "the descriptor has no artifact list")
  }
  let digest = Json::string(artifact.to_string())
  let matching = entries.filter(entry => {
    entry is Object(item) && item.get("sha256") == Some(digest)
  })
  guard matching is [Object(entry)] && entry.get("claims") is Some(recorded) else {
    raise refused(
      DescriptorInvalid,
      "the descriptor has no single entry with claims for the artifact \{artifact}",
    )
  }
  @worker.Claims::from_describe(recorded) catch {
    error =>
      raise refused(
        DescriptorInvalid,
        "the descriptor claims are not valid: \{error}",
      )
  }
}

///|
/// The claims that a descriptor records must equal the live claims.
fn extension_descriptor_matches(
  recorded : @worker.Claims,
  live : @worker.Claims,
) -> Unit raise ExtensionError {
  guard recorded == live else {
    raise refused(
      Worker(ClaimsMismatch),
      "the descriptor claims differ from the live describe of \{live.extension_id} \{live.version}",
    )
  }
}

///|
fn extension_claims_json(claims : @worker.Claims) -> Json {
  let strings = (items : Array[String]) => Json::array(items.map(Json::string))
  {
    "extension": {
      "id": claims.extension_id.to_string(),
      "version": claims.version.to_string(),
    },
    "protocolVersions": strings(
      claims.protocol_lines.map(line => line.to_string()),
    ),
    "operations": strings(
      claims.operations.map(operation => operation.to_string()),
    ),
    "languages": Json::array(
      claims.languages.map(language => {
        "id": language.language_id.to_string(),
        "fileExtensions": strings(
          language.file_extensions.map(extension => extension.to_string()),
        ),
      }),
    ),
    "frontendIrVersions": strings(
      claims.frontend_ir_versions.map(version => version.to_string()),
    ),
    "frontendFlags": {
      "incremental": claims.frontend_flags.incremental,
      "multiDocument": claims.frontend_flags.multi_document,
    },
    "targets": strings(claims.targets.map(target => target.to_string())),
    "backendIrVersions": strings(
      claims.backend_ir_versions.map(version => version.to_string()),
    ),
    "modelTuples": Json::array(
      claims.model_tuples.map(tuple => tuple.to_json()),
    ),
  }
}

///|
fn extension_worker_json(pin : ExtensionPin) -> Json {
  let fields : Map[String, Json] = {
    "kind": pin.spec.runtime.kind().to_string(),
    "runtime": pin.spec.runtime.to_json(),
    "artifact": {
      "path": match pin.spec.artifact.source {
        File(path) => Json::string(path.to_string())
        Memory(_) => Json::null()
      },
      "sha256": pin.spec.artifact.sha256.to_string(),
    },
    "origin": pin.origin,
  }
  if pin.descriptor is Some(descriptor) {
    fields["descriptorSha256"] = Json::string(descriptor.sha256.to_string())
  }
  Json::object(fields)
}

///|
fn extension_stderr_text(tail : @worker.StderrTail) -> String {
  @utf8.decode_lossy(tail.bytes()[:])
}

///|
/// The outcome of one command, before it is written.
priv struct ExtensionReport {
  command : ExtensionCommand
  outcome : Result[(Json, String), ExtensionError]
  diagnostics : Array[@worker.Diagnostic]
}

///|
fn ExtensionReport::failure(
  command : ExtensionCommand,
  error : ExtensionError,
  diagnostics~ : Array[@worker.Diagnostic] = [],
) -> ExtensionReport {
  { command, outcome: Err(error), diagnostics, }
}

///|
fn ExtensionReport::exit_code(self : ExtensionReport) -> Int32 {
  match self.outcome {
    Ok(_) => 0
    Err(ExtensionError(status~, ..)) => status.exit_code()
  }
}

///|
/// One `morphir/command-result` 0.1.0 object: `result` on success, `error`
/// on failure.
fn ExtensionReport::to_json(self : ExtensionReport) -> Json {
  let fields : Map[String, Json] = {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": self.command.name(),
    "state": if self.outcome is Ok(_) {
      "succeeded"
    } else {
      "failed"
    },
    "exitCode": self.exit_code(),
    "diagnostics": Json::array(self.diagnostics.map(d => d.to_json())),
  }
  match self.outcome {
    Ok((result, _)) => fields["result"] = result
    Err(ExtensionError(code~, message~, ..)) =>
      fields["error"] = { "code": code.name(), "message": message }
  }
  Json::object(fields)
}

///|
fn extension_diagnostic_line(diagnostic : @worker.Diagnostic) -> String {
  let at = match diagnostic.location {
    Some(location) =>
      "\{location.uri}:\{location.start.line + 1}:\{location.start.character + 1}: "
    None => ""
  }
  let code = match diagnostic.code {
    Some(code) => " " + code
    None => ""
  }
  "\{at}\{diagnostic.severity}\{code}: \{diagnostic.message}"
}

///|
/// Writes the report. Diagnostics and failures go to stderr; stdout holds
/// only the summary, or the one JSON object.
fn ExtensionReport::emit(self : ExtensionReport, mode : OutputMode) -> Unit {
  for diagnostic in self.diagnostics {
    @platform.stderr(extension_diagnostic_line(diagnostic) + "\n")
  }
  if self.outcome is Err(ExtensionError(code~, message~, ..)) {
    @platform.stderr(code.name() + ": " + message + "\n")
  }
  match mode {
    JSON => println(self.to_json().stringify())
    JSONLines => emit_record("result", self.to_json())
    Human => if self.outcome is Ok((_, summary)) { println(summary) }
  }
}

///|
/// What a command needs from its run: the worker launchers and the stop
/// probe of the CLI's lifetime.
priv struct ExtensionRun {
  hosting : WorkerHosting
  stopped : () -> Bool
}

///|
/// Runs one command and returns its report. It never raises: every failure
/// is in the report with its exit status.
async fn extension_run(cli : Cli, run : ExtensionRun) -> ExtensionReport {
  guard ExtensionCommand::of(cli.command) is Some(command) else {
    return ExtensionReport::failure(
      Describe,
      input_invalid("unknown extension command \{cli.command}"),
    )
  }
  let diagnostics : Array[@worker.Diagnostic] = []
  // `catch` cannot see an async cancellation, so `handle_cancellation`
  // reports it: a cancelled command exits 130, never with host_failed. The
  // host stops the worker tree before the cancellation reaches this point.
  let outcome = try
    @async.handle_cancellation(() => {
      extension_execute(cli, command, run, diagnostics)
    })
  catch {
    ExtensionError(..) as error => Err(error)
    @platform.Interrupted => Err(ending_error(Cancelled))
    error => Err(failed(HostFailed, @host.error_message(error)))
  } noraise {
    Some(result) => Ok(result)
    None => Err(ending_error(Cancelled))
  }
  { command, outcome, diagnostics, }
}

///|
async fn extension_execute(
  cli : Cli,
  command : ExtensionCommand,
  run : ExtensionRun,
  diagnostics : Array[@worker.Diagnostic],
) -> (Json, String) {
  extension_retired_options(cli)
  guard run.hosting.host() is Some(host) else {
    raise refused(
      Worker(RuntimeUnavailable),
      "this CLI build has no worker host; use the native or npm CLI",
    )
  }
  let pin_path = value(
    cli,
    "extension-pin",
    fallback=@platform.environment().get("MORPHIR_EXTENSION_PIN").unwrap_or(""),
  )
  if pin_path == "" {
    raise refused(
      PinRequired,
      "give a contract \{extension_pin_contract} pin with --extension-pin or MORPHIR_EXTENSION_PIN",
    )
  }
  let inputs = ExtensionInputs::read(cli, command)
  let pin_bytes = @platform.read_input(pin_path, 65536) catch {
    error =>
      raise refused(
        PinInvalid,
        "cannot read the pin \{pin_path}: \{@host.error_message(error)}",
      )
  }
  let pin_json = @json.parse(@utf8.decode(pin_bytes[:])) catch {
    _ => raise refused(PinInvalid, "the pin \{pin_path} is not UTF-8 JSON")
  }
  let pin = ExtensionPin::decode(pin_json, run.hosting.path_style())
  let kind = pin.spec.runtime.kind()
  guard run.hosting.kinds().contains(kind) else {
    raise refused(
      Worker(RuntimeUnavailable),
      "this CLI starts \{run.hosting.kinds().map(kind => kind.to_string()).join(" and ")} workers, not \{kind} workers",
    )
  }
  let started = @platform.monotonic_seconds()
  fn remaining() -> @worker.Deadline raise ExtensionError {
    let left = inputs.timeout_ms -
      ((@platform.monotonic_seconds() - started) * 1000.0).to_int()
    @worker.Deadline::of_ms(left) catch {
      _ => raise ending_error(Deadline)
    }
  }

  fn check() -> Unit raise ExtensionError {
    if (run.stopped)() {
      raise ending_error(Cancelled)
    }
    ignore(remaining())
  }

  // The descriptor is read and checked before the probe starts a worker.
  let recorded = pin.descriptor.map(descriptor => {
    extension_descriptor(descriptor, pin.spec.artifact.sha256)
  })
  let stop = @worker.StopSignal::new(run.stopped)
  let description = host.probe(pin.spec, deadline=remaining(), stop~) catch {
    @worker.Ended(ending, report~) => {
      // The guest's own logs go to stderr even when the session failed.
      if report.stop is Some(stop) {
        @platform.stderr(extension_stderr_text(stop.stderr))
      }
      raise ending_error(ending)
    }
    error => raise error
  }
  let claims = description.claims
  if recorded is Some(recorded) {
    extension_descriptor_matches(recorded, claims)
  }
  let worker = extension_worker_json(pin)
  let identity = "\{claims.extension_id} \{claims.version}"
  if command is Describe {
    let result : Json = {
      "worker": worker,
      "extension": {
        "id": claims.extension_id.to_string(),
        "version": claims.version.to_string(),
      },
      "claims": extension_claims_json(claims),
      "lifecycle": { "probe": "described", "workerStopped": true },
    }
    let lines = claims.protocol_lines.map(line => line.to_string()).join(", ")
    let operations = claims.operations
      .map(operation => operation.to_string())
      .join(", ")
    return (
      result,
      "\{identity}: \{pin.spec.runtime.kind()} worker; MEP \{lines}; \{operations}",
    )
  }
  // Inputs that need the claims are read after the probe, before any call.
  let (line, call, ir_version) = match command {
    Compile => {
      let line = extension_compile_offer(
        claims,
        inputs.codec,
        inputs.ir_version,
        model_only=inputs.profile != "",
      )
      let ir_version = match (line.offer, line.fallback) {
        // The decision has found the claimed name of the requested version.
        (Legacy, Some({ ir_version: Some(name), .. })) => Some(name.to_string())
        (Legacy, _) =>
          extension_ir_version(
            claims,
            claims.frontend_ir_versions,
            inputs.ir_version,
          )
        (Model(_), _) => None
      }
      let language = extension_language(claims, inputs.language)
      let documents = extension_sources(
        inputs.path,
        language.file_extensions.map(extension => extension.to_string()),
        check,
        base={
          given: inputs.source_base,
          cwd: @platform.cwd(),
          style: run.hosting.path_style(),
        },
      )
      let language = language.language_id
      extension_document_count(claims, documents)
      // The request follows the tuple that the session agrees on.
      let request = (tuple : @worker.ModelTuple?) => {
        let params = extension_compile_params(
          inputs, claims, tuple, language, documents, ir_version,
        )
        @worker.CompileRequest::new(params) catch {
          refusal => raise refusal_error(refusal)
        }
      }
      // An oversized request is refused before any worker starts. Every
      // offered tuple gives a request of about this size; the session checks
      // the one that it sends.
      ignore(request(line.offer.default_tuple()))
      (line, Ok(request), ir_version)
    }
    _ => {
      let bytes = @platform.read_input(inputs.path, 4194304) catch {
        error =>
          raise input_invalid(
            "cannot read \{inputs.path}: \{@host.error_message(error)}",
          )
      }
      let model = @worker.parse_model_document(bytes) catch {
        _ => raise input_invalid("\{inputs.path} is not a bounded JSON model")
      }
      let input = extension_generate_input(inputs, claims, bytes, model)
      let params = extension_generate_params(
        inputs,
        claims,
        input.tuple,
        input.line.fallback,
        input.model,
      )
      let request = @worker.GenerateRequest::new(params) catch {
        refusal => raise refusal_error(refusal)
      }
      (input.line, Err(request), None)
    }
  }
  check()
  let offer = line.offer
  // The warning stays in the report also when the session then fails.
  if line.fallback is Some(fallback) {
    diagnostics.push(fallback.diagnostic())
  }
  let (outcome, report) = host.with_session(
    pin.spec,
    expected=claims,
    offer~,
    deadline=remaining(),
    stop~,
    async fn(session) {
      let outcome = match call {
        Ok(request) => {
          let tuple = session.negotiated().bind(agreed => agreed.tuple)
          session.compile(request(tuple)).map(compiled => compiled.result)
        }
        Err(request) =>
          session.generate(request).map(generated => generated.result)
      }
      (outcome, session.close())
    },
  ) catch {
    @worker.Ended(ending, report~) => {
      // The guest's own logs go to stderr even when the session failed.
      if report.stop is Some(stop) {
        @platform.stderr(extension_stderr_text(stop.stderr))
      }
      raise ending_error(ending)
    }
    error => raise error
  }
  diagnostics.append(outcome.diagnostics)
  let stderr = match report.stop {
    Some(stop) => stop.stderr
    None => outcome.stderr
  }
  @platform.stderr(extension_stderr_text(stderr))
  let result = match outcome.class {
    Completed(result) => result
    Unsuccessful =>
      raise failed(OperationUnsuccessful, "\{identity} answered success: false")
    Failed(fault) => raise ending_error(Failed(fault))
    Refused(code~, message~) => raise ending_error(Refused(code~, message~))
    Deadline => raise ending_error(Deadline)
    Cancelled => raise ending_error(Cancelled)
  }
  if report.ending is Some(ending) {
    raise ending_error(ending)
  }
  // Publish only when the worker tree has stopped.
  guard report.stop is Some(stopped) && !(stopped.status is Unconfirmed(_)) else {
    raise failed(
      Worker(TreeTerminationFailed),
      "the host could not confirm that the worker tree stopped",
    )
  }
  // On the model line the session uses the first tuple that the extension
  // agreed on, which can differ from the host's default.
  let agreed = match (offer, report.negotiated) {
    (Legacy, _) => None
    (Model(_), Some({ tuple: Some(tuple), .. })) => Some(tuple)
    (Model(_), _) =>
      raise failed(ResultInvalid, "the session reports no agreed model tuple")
  }
  let limits = match report.negotiated {
    Some(negotiated) => negotiated.limits.model
    None => report.limits.model
  }
  let files = extension_files(command, agreed, result, ir_version, limits)
  let receipts = extension_publish(inputs.output, files, check=fn() raise {
    check()
  }) catch {
    ExtensionError(..) as error => raise error
    error =>
      raise failed(
        OutputFailed,
        "cannot publish \{inputs.output}: \{@host.error_message(error)}",
      )
  }
  let session = report.to_json()
  let negotiated : Map[String, Json] = {
    "protocolVersion": offer.line().to_string(),
  }
  if report.negotiated is Some(agreed) {
    if agreed.tuple is Some(tuple) {
      negotiated["tuple"] = tuple.to_json()
    }
    negotiated["limits"] = agreed.limits.model.to_json()
  }
  let bounds : Map[String, Json] = {
    "requestBytes": report.limits.request_bytes,
    "responseBytes": report.limits.response_bytes,
    "deadlineMs": inputs.timeout_ms,
    "stderrTailBytes": 65536,
  }
  if report.extism is Some(profile) {
    bounds["extism"] = profile.to_json()
  }
  // A WASM worker's host states which bounds it enforced: the memory
  // ceiling, the instruction budget and the per-call deadline.
  if report.bounds is Some(enforced) && enforced.to_json() is Object(fields) {
    for name, value in fields {
      bounds[name] = value
    }
  }
  if command is Compile {
    bounds["sourceFiles"] = Json::number(
      extension_source_limits.files.to_double(),
    )
    bounds["sourceBytes"] = Json::number(
      extension_source_limits.bytes.to_double(),
    )
  }
  let lifecycle : Map[String, Json] = {
    "probe": "described",
    "shutdown": "acknowledged",
    "workerStopped": true,
    "wireCancellation": false,
  }
  if session is Object({ "worker": stop, .. }) {
    lifecycle["worker"] = stop
  }
  let result : Json = {
    "worker": worker,
    "extension": {
      "id": claims.extension_id.to_string(),
      "version": claims.version.to_string(),
    },
    "protocolVersion": offer.line().to_string(),
    "negotiated": Json::object(negotiated),
    "bounds": Json::object(bounds),
    "output": { "directory": inputs.output, "files": Json::array(receipts) },
    "lifecycle": Json::object(lifecycle),
    "stderr": {
      "text": extension_stderr_text(stderr),
      "truncated": stderr.truncated(),
    },
  }
  (
    result,
    "\{identity} on MEP \{offer.line()}: wrote \{receipts.length()} file(s) to \{inputs.output}",
  )
}

///|
/// The entry of `extension describe|compile|generate`.
async fn extension_command(cli : Cli, context : CommandContext) -> Int32 {
  let cancel_path = value(cli, "cancel-file")
  let cancel_file = if cancel_path == "" {
    ""
  } else {
    @metadata_grants.host_path(
      cancel_path,
      @platform.cwd(),
      @platform.system_type(),
    )
  }
  // The worker host polls this probe, also in tasks that it has cancelled,
  // so it reads stop requests only: a cancellation of the command's task
  // reaches `extension_run` as a cancellation.
  let stopped = () => {
    @platform.interruption_requested() ||
    (context.stop_requested)() ||
    (cancel_file != "" && (@platform.kind(cancel_file) catch { _ => 1 }) != 0)
  }
  let report = extension_run(cli, { hosting: context.workers, stopped, })
  report.emit(context.mode)
  report.exit_code()
}
