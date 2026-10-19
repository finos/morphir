///|
pub(all) suberror DocumentError {
  InvalidFilename
  InvalidCodec
  InvalidVersion
  InvalidBytes
  TooLarge
  InvalidReply
  RevisionLimit
} derive(Eq, Debug)

///|
pub extend DocumentError with @debug.Debug::{to_repr}

///|
pub extend DocumentError with Eq::{equal, not_equal}

///|
pub fn DocumentError::code(self : DocumentError) -> String {
  match self {
    InvalidFilename => "model.invalid_filename"
    InvalidCodec => "model.invalid_codec"
    InvalidVersion => "model.invalid_version"
    InvalidBytes => "model.invalid_bytes"
    TooLarge => "model.capacity"
    InvalidReply => "model.invalid_reply"
    RevisionLimit => "model.revision_limit"
  }
}

///|
pub extend SourceCodec with Eq::{equal, not_equal}

///|
pub extend SourceCodec with @debug.Debug::{to_repr}

///|
pub extend OriginalFilename with Eq::{equal, not_equal}

///|
pub extend OriginalFilename with @debug.Debug::{to_repr}

///|
pub extend OriginalFile with Eq::{equal, not_equal}

///|
pub extend OriginalFile with @debug.Debug::{to_repr}

///|
pub extend ProjectionReason with Eq::{equal, not_equal}

///|
pub extend ProjectionReason with @debug.Debug::{to_repr}

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend Source with @debug.Debug::{to_repr}

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend OpenAttempt with Eq::{equal, not_equal}

///|
pub extend OpenAttempt with @debug.Debug::{to_repr}

///|
pub extend DocumentRevision with Eq::{equal, not_equal}

///|
pub extend DocumentRevision with @debug.Debug::{to_repr}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend State with @debug.Debug::{to_repr}

///|
pub extend HostRetention with Eq::{equal, not_equal}

///|
pub extend HostRetention with @debug.Debug::{to_repr}

///|
pub(all) enum SourceCodec {
  MorphirJson
  MorphirYaml
  IonText
  IonBinary
} derive(Eq, Debug)

///|
pub fn SourceCodec::parse(text : String) -> SourceCodec raise DocumentError {
  let format = @data.ModelFormat::from_control(text) catch {
    _ => raise InvalidCodec
  }
  if format.codec_id() != text {
    raise InvalidCodec
  }
  match format {
    JSON => MorphirJson
    YAML => MorphirYaml
    IonText => IonText
    IonBinary => IonBinary
  }
}

///|
/// Compatibility names remain at the document boundary; format decisions use
/// the shared closed model-format domain.
pub fn SourceCodec::format(self : SourceCodec) -> @data.ModelFormat {
  match self {
    MorphirJson => JSON
    MorphirYaml => YAML
    IonText => IonText
    IonBinary => IonBinary
  }
}

///|
pub fn SourceCodec::to_string(self : SourceCodec) -> String {
  self.format().codec_id()
}

///|
pub struct OriginalFilename(String) derive(Eq, Debug)

///|
pub fn OriginalFilename::to_string(self : OriginalFilename) -> String {
  let OriginalFilename(value) = self
  value
}

///|
pub fn OriginalFilename::parse(
  text : String,
) -> OriginalFilename raise DocumentError {
  let mut length = 0
  for character in text {
    length += 1
    if character < ' ' ||
      character == '\u007f' ||
      character == '/' ||
      character == '\\' {
      raise InvalidFilename
    }
  }
  if length == 0 || length > 256 || text == "." || text == ".." {
    raise InvalidFilename
  }
  OriginalFilename(text)
}

///|
pub struct OriginalFile {
  filename : OriginalFilename
  codec : SourceCodec
  format_version : @version.FormatVersion
  priv bytes : Bytes
} derive(Eq, Debug)

///|
fn copy_bytes(bytes : Bytes) -> Bytes {
  Bytes::from_array(bytes.iter().collect())
}

///|
pub fn OriginalFile::new(
  filename : OriginalFilename,
  codec : SourceCodec,
  format_version : @version.FormatVersion,
  bytes : Bytes,
) -> OriginalFile raise DocumentError {
  format_version.check_supported() catch {
    _ => raise InvalidVersion
  }
  if bytes.length() > 16 * 1024 * 1024 {
    raise TooLarge
  }
  { filename, codec, format_version, bytes: copy_bytes(bytes), }
}

///|
pub fn OriginalFile::byte_length(self : OriginalFile) -> Int32 {
  self.bytes.length()
}

///|
/// A fresh copy for consumers; no caller can mutate the retained source.
pub fn OriginalFile::copy_bytes(self : OriginalFile) -> Bytes {
  copy_bytes(self.bytes)
}

///|
/// The local download boundary. It does not acquire filesystem authority.
pub fn OriginalFile::download(self : OriginalFile) -> Json {
  let OriginalFilename(filename) = self.filename
  {
    "path": filename,
    "content": @base64.encode(self.bytes[:]),
    "binary": true,
    "encoding": "base64",
  }
}

///|
pub(all) enum ProjectionReason {
  OriginalsNotProvided
  GeneratedModel
} derive(Eq, Debug)

///|
pub(all) enum Source {
  Original(OriginalFile)
  Tree(OriginalTree)
  Projection(ProjectionReason)
} derive(Eq, Debug)

///|
/// Semantic inspection remains the existing private JSON projection. Source
/// bytes have separate ownership; this is not a deep immutable IR snapshot.
pub struct Document {
  inspection : Json
  source : Source
} derive(Eq, Debug)

///|
fn field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn string(value : Json) -> String raise DocumentError {
  match value {
    String(text) => text
    _ => raise InvalidReply
  }
}

///|
fn source_version(text : String) -> @version.FormatVersion raise DocumentError {
  let value = try {
    match text {
      "1.0.0" => @version.FormatVersion::baseline(1U)
      "2.0.0" => @version.FormatVersion::baseline(2U)
      _ => @version.FormatVersion::parse(text)
    }
  } catch {
    _ => raise InvalidVersion
  }
  value.check_supported() catch {
    _ => raise InvalidVersion
  }
  value
}

///|
/// Decode a source offer at the private inspection boundary. Missing provenance
/// means a semantic projection, including every frozen connected-v1 response.
pub fn Document::from_reply(reply : Json) -> Document raise DocumentError {
  guard reply is Object(fields) else { raise InvalidReply }
  let source = match fields.get("modelSource") {
    None => Projection(OriginalsNotProvided)
    Some(Object(source)) => {
      let value = Json::object(source)
      match string(field(value, "kind")) {
        "original-file" => {
          if source.length() != 5 {
            raise InvalidReply
          }
          let filename = OriginalFilename::parse(
            string(field(value, "filename")),
          )
          let codec = SourceCodec::parse(string(field(value, "codec")))
          let version_text = string(field(value, "formatVersion"))
          if field(reply, "sourceFormatVersion") != Json::string(version_text) {
            raise InvalidVersion
          }
          let version = source_version(version_text)
          let encoded = string(field(value, "contentBase64"))
          if encoded.length() > 22369624 {
            raise TooLarge
          }
          let bytes = @base64.decode(encoded[:]) catch {
            _ => raise InvalidBytes
          }
          if @base64.encode(bytes[:]) != encoded {
            raise InvalidBytes
          }
          Original(OriginalFile::new(filename, codec, version, bytes))
        }
        "semantic-projection" => {
          if source.length() != 2 {
            raise InvalidReply
          }
          Projection(
            match string(field(value, "reason")) {
              "originals-not-provided" => OriginalsNotProvided
              "generated-model" => GeneratedModel
              _ => raise InvalidReply
            },
          )
        }
        "original-tree" =>
          Tree(tree_from_reply(value, field(reply, "sourceFormatVersion")))
        _ => raise InvalidReply
      }
    }
    _ => raise InvalidReply
  }
  let view = fields.copy()
  // Strip only private envelope members, never similarly named model data.
  view.remove("modelSource") |> ignore
  view.remove("originalArtifact") |> ignore
  let inspection = @json.parse(Json::object(view).stringify()) catch {
    _ => raise InvalidReply
  }
  { inspection, source, }
}

///|
pub struct OpenAttempt(Int32) derive(Eq, Debug)

///|
pub struct DocumentRevision(Int32) derive(Eq, Debug)

///|
pub fn OpenAttempt::to_string(self : OpenAttempt) -> String {
  let OpenAttempt(value) = self
  value.to_string()
}

///|
priv enum Phase {
  Empty
  Loaded(Document)
  Opening(OpenAttempt, Document?)
} derive(Eq, Debug)

///|
pub struct State {
  priv sequence : Int32
  priv revision : Int32
  priv phase : Phase
} derive(Eq, Debug)

///|
pub fn State::new() -> State {
  { sequence: 0, revision: 0, phase: Empty, }
}

///|
pub fn State::document(self : State) -> Document? {
  match self.phase {
    Empty => None
    Loaded(document) | Opening(_, Some(document)) => Some(document)
    Opening(_, None) => None
  }
}

///|
pub fn State::inspection(self : State) -> Json {
  match self.document() {
    Some(document) => document.inspection
    None => Json::null()
  }
}

///|
pub fn State::original(self : State) -> OriginalFile? {
  match self.document() {
    Some({ source: Original(file), .. }) => Some(file)
    _ => None
  }
}

///|
pub fn State::original_tree(self : State) -> OriginalTree? {
  match self.document() {
    Some({ source: Tree(tree), .. }) => Some(tree)
    _ => None
  }
}

///|
pub fn State::original_tree_for(
  self : State,
  revision : DocumentRevision,
) -> OriginalTree? {
  if self.current_revision() != Some(revision) {
    None
  } else {
    self.original_tree()
  }
}

///|
pub fn State::opening(self : State) -> OpenAttempt? {
  match self.phase {
    Opening(attempt, _) => Some(attempt)
    _ => None
  }
}

///|
pub fn State::current_revision(self : State) -> DocumentRevision? {
  match self.document() {
    Some(_) => Some(DocumentRevision(self.revision))
    None => None
  }
}

///|
pub fn State::original_for(
  self : State,
  revision : DocumentRevision,
) -> OriginalFile? {
  if self.current_revision() != Some(revision) {
    return None
  }
  self.original()
}

///|
pub fn State::is_current(self : State, attempt : OpenAttempt) -> Bool {
  self.opening() == Some(attempt)
}

///|
pub(all) enum HostRetention {
  Idle
  Submitting
  Running
  Disconnected
  UnknownSubmission
} derive(Eq, Debug)

///|
pub(all) enum BeginDecision {
  Started(State, OpenAttempt)
  Refused(HostRetention)
  Exhausted
}

///|
pub fn State::begin(self : State, host : HostRetention) -> BeginDecision {
  if host != Idle {
    return Refused(host)
  }
  if self.sequence == 2147483647 {
    return Exhausted
  }
  let attempt = OpenAttempt(self.sequence + 1)
  Started(
    {
      ..self,
      sequence: self.sequence + 1,
      phase: Opening(attempt, self.document()),
    },
    attempt,
  )
}

///|
pub fn State::reject(self : State, attempt : OpenAttempt) -> State {
  if !self.is_current(attempt) {
    return self
  }
  {
    ..self,
    phase: match self.document() {
      Some(document) => Loaded(document)
      None => Empty
    },
  }
}

///|
pub fn State::finish(
  self : State,
  attempt : OpenAttempt,
  reply : Json,
) -> State raise DocumentError {
  if !self.is_current(attempt) {
    return self
  }
  self.replace(reply)
}

///|
/// Adoption retires any picker/read attempt. The caller already owns the current
/// compile or inspection reply; malformed original offers never replace a model.
pub fn State::replace(self : State, reply : Json) -> State raise DocumentError {
  if self.revision == 2147483647 {
    raise RevisionLimit
  }
  {
    ..self,
    revision: self.revision + 1,
    phase: Loaded(Document::from_reply(reply)),
  }
}

///|
pub(all) enum CloseDecision {
  Closed(State, OpenAttempt?)
  Retained(HostRetention)
}

///|
pub fn State::close(self : State, host : HostRetention) -> CloseDecision {
  if host != Idle {
    return Retained(host)
  }
  Closed({ ..self, phase: Empty, }, self.opening())
}
