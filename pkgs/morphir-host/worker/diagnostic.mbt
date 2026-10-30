///|
/// How serious a guest diagnostic is.
pub(all) enum Severity {
  Error
  Warning
  Info
  Hint
} derive(Eq, Debug)

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
let severities : Array[Severity] = [Error, Warning, Info, Hint]

///|
pub fn Severity::parse(text : String) -> Severity raise ValueError {
  match severities.search_by(severity => severity.to_string() == text) {
    Some(index) => severities[index]
    None => raise InvalidDiagnostic("unknown severity \{text}")
  }
}

///|
pub impl Show for Severity with fn output(self, logger) {
  logger.write_string(
    match self {
      Error => "error"
      Warning => "warning"
      Info => "info"
      Hint => "hint"
    },
  )
}

///|
pub extend Severity with Show::{to_string, output}

///|
/// A zero-based position. `character` counts UTF-16 code units from the start
/// of the line, as in the Language Server Protocol.
pub struct SourcePosition {
  line : Int64
  character : Int64
} derive(Eq, Debug)

///|
pub extend SourcePosition with Eq::{equal, not_equal}

///|
pub extend SourcePosition with @debug.Debug::{to_repr}

///|
/// A half-open range in a source document, identified by URI.
pub struct SourceLocation {
  uri : String
  start : SourcePosition
  end : SourcePosition
} derive(Eq, Debug)

///|
pub extend SourceLocation with Eq::{equal, not_equal}

///|
pub extend SourceLocation with @debug.Debug::{to_repr}

///|
/// More information about a diagnostic, at another location.
pub struct RelatedInformation {
  location : SourceLocation
  message : String
} derive(Eq, Debug)

///|
pub extend RelatedInformation with Eq::{equal, not_equal}

///|
pub extend RelatedInformation with @debug.Debug::{to_repr}

///|
/// A diagnostic from a guest. The host keeps every member as the guest sent
/// it: the code, severity, location, message, related information and the
/// guest's own data.
pub struct Diagnostic {
  severity : Severity
  code : String?
  message : String
  location : SourceLocation?
  related : Array[RelatedInformation]
  data : Json?
} derive(Eq, Debug)

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
fn diagnostic_text(
  fields : Map[String, Json],
  name : String,
) -> String raise ValueError {
  guard fields.get(name) is Some(String(text)) else {
    raise InvalidDiagnostic("\{name} is not text")
  }
  text
}

///|
fn SourcePosition::decode(value : Json) -> SourcePosition raise ValueError {
  let read = (name : String) => {
    guard value is Object(fields) &&
      fields.get(name) is Some(Number(number, ..)) &&
      number >= 0.0 &&
      number <= 4294967295.0 &&
      number == number.floor() else {
      raise InvalidDiagnostic("position \{name} is not a line or column")
    }
    number.to_int64()
  }
  { line: read("line"), character: read("character"), }
}

///|
fn SourceLocation::decode(value : Json) -> SourceLocation raise ValueError {
  guard value is Object(fields) &&
    fields.get("range") is Some(Object(range)) &&
    range.get("start") is Some(start) &&
    range.get("end") is Some(end) else {
    raise InvalidDiagnostic("location has no range")
  }
  {
    uri: diagnostic_text(fields, "uri"),
    start: SourcePosition::decode(start),
    end: SourcePosition::decode(end),
  }
}

///|
/// Decodes one diagnostic from a guest answer.
pub fn Diagnostic::decode(value : Json) -> Diagnostic raise ValueError {
  guard value is Object(fields) else {
    raise InvalidDiagnostic("diagnostic is not an object")
  }
  let related = match fields.get("related") {
    None => []
    Some(Array(items)) =>
      items.map(item => {
        guard item is Object(entry) && entry.get("location") is Some(location) else {
          raise InvalidDiagnostic("related information has no location")
        }
        {
          location: SourceLocation::decode(location),
          message: diagnostic_text(entry, "message"),
        }
      })
    Some(_) => raise InvalidDiagnostic("related is not a list")
  }
  {
    severity: Severity::parse(diagnostic_text(fields, "severity")),
    code: match fields.get("code") {
      None => None
      Some(_) => Some(diagnostic_text(fields, "code"))
    },
    message: diagnostic_text(fields, "message"),
    location: fields.get("location").map(SourceLocation::decode),
    related,
    data: fields.get("data"),
  }
}

///|
pub extend SourceLocation with ToJson::{to_json}

///|
pub impl ToJson for SourceLocation with fn to_json(self) {
  let position = (position : SourcePosition) => {
    "line": position.line.to_double(),
    "character": position.character.to_double(),
  }
  {
    "uri": self.uri,
    "range": { "start": position(self.start), "end": position(self.end) },
  }
}

///|
pub extend Diagnostic with ToJson::{to_json}

///|
pub impl ToJson for Diagnostic with fn to_json(self) {
  let fields : Map[String, Json] = {
    "severity": self.severity.to_string(),
    "message": self.message,
  }
  if self.code is Some(code) {
    fields["code"] = Json::string(code)
  }
  if self.location is Some(location) {
    fields["location"] = location.to_json()
  }
  if !self.related.is_empty() {
    fields["related"] = Json::array(
      self.related.map(item => {
        "location": item.location.to_json(),
        "message": Json::string(item.message),
      }),
    )
  }
  if self.data is Some(data) {
    fields["data"] = data
  }
  Json::object(fields)
}
