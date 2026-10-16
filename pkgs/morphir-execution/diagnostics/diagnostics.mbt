///|
/// Parser coordinates, interpreted according to the warning's producer.
pub(all) struct Span {
  start_line : Int32
  start_column : Int32
  end_line : Int32
  end_column : Int32
} derive(Eq, Debug)

///|
/// Authored spelling and final allocation stay separate in each related location.
pub(all) struct Location {
  owner : String
  original : String
  allocated : String
  source : Span?
} derive(Eq, Debug)

///|
/// A recoverable diagnostic independent of optional observation sinks.
pub(all) struct Warning {
  code : String
  stage : String
  message : String
  locations : Array[Location]
  fix : String
} derive(Eq, Debug)

///|
pub(all) suberror DiagnosticError {
  InvalidDiagnostic(String)
} derive(Debug)

///|
pub extend Span with Eq::{equal, not_equal}

///|
pub extend Span with @debug.Debug::{to_repr}

///|
pub extend Location with Eq::{equal, not_equal}

///|
pub extend Location with @debug.Debug::{to_repr}

///|
pub extend Warning with Eq::{equal, not_equal}

///|
pub extend Warning with @debug.Debug::{to_repr}

///|
pub extend DiagnosticError with @debug.Debug::{to_repr}

///|
fn record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::new(Struct(fields.map(p => @ion.Field::new(p.0, p.1))))
}

///|
pub fn Warning::to_ion(self : Warning) -> @ion.IonValue {
  record([
    ("contract", @ion.IonValue::string("morphir-warning-v1")),
    ("severity", @ion.IonValue::string("warning")),
    ("code", @ion.IonValue::string(self.code)),
    ("stage", @ion.IonValue::string(self.stage)),
    ("message", @ion.IonValue::string(self.message)),
    ("fix", @ion.IonValue::string(self.fix)),
    (
      "locations",
      @ion.IonValue::list(
        self.locations.map(loc => {
          record([
            ("owner", @ion.IonValue::string(loc.owner)),
            ("original", @ion.IonValue::string(loc.original)),
            ("allocated", @ion.IonValue::string(loc.allocated)),
            (
              "source",
              match loc.source {
                None => @ion.IonValue::new(@ion.Null(@ion.Null))
                Some(s) =>
                  record([
                    ("start_line", @ion.IonValue::int(s.start_line)),
                    ("start_column", @ion.IonValue::int(s.start_column)),
                    ("end_line", @ion.IonValue::int(s.end_line)),
                    ("end_column", @ion.IonValue::int(s.end_column)),
                  ])
              },
            ),
          ])
        }),
      ),
    ),
  ]).with_annotation(@ion.SymbolToken::new("morphir_warning"))
}

///|
fn fields(
  value : @ion.IonValue,
  expected : Array[String],
) -> Map[String, @ion.IonValue] raise DiagnosticError {
  guard value.kind() is Struct(items) else {
    raise InvalidDiagnostic("Expected a diagnostic record")
  }
  let result : Map[String, @ion.IonValue] = Map([])
  for item in items {
    guard item.name().text() is Some(name) else {
      raise InvalidDiagnostic("Unresolved diagnostic field")
    }
    if !expected.contains(name) ||
      result.contains(name) ||
      item.value().has_annotations() {
      raise InvalidDiagnostic("Invalid diagnostic field: " + name)
    }
    result[name] = item.value()
  }
  if result.length() != expected.length() {
    raise InvalidDiagnostic("Missing diagnostic field")
  }
  result
}

///|
fn text(
  fields : Map[String, @ion.IonValue],
  name : String,
) -> String raise DiagnosticError {
  guard fields[name].kind() is String(value) else {
    raise InvalidDiagnostic("Expected diagnostic string: " + name)
  }
  value
}

///|
fn number(
  fields : Map[String, @ion.IonValue],
  name : String,
) -> Int32 raise DiagnosticError {
  guard fields[name].kind() is Int(value) else {
    raise InvalidDiagnostic("Expected diagnostic coordinate: " + name)
  }
  let n = @strconv.parse_int(value.to_string()) catch {
    _ => raise InvalidDiagnostic("Invalid diagnostic coordinate: " + name)
  }
  guard n >= 0 else {
    raise InvalidDiagnostic("Invalid diagnostic coordinate: " + name)
  }
  n
}

///|
/// Unknown provenance is preserved by the caller and is not a warning.
pub fn warning_from_ion(
  value : @ion.IonValue,
) -> Warning? raise DiagnosticError {
  if !value.annotations().any(a => a.text() == Some("morphir_warning")) {
    return None
  }
  if value.annotations().length() != 1 {
    raise InvalidDiagnostic("Unexpected warning annotation")
  }
  let f = fields(value, [
    "contract", "severity", "code", "stage", "message", "locations", "fix",
  ])
  if text(f, "contract") != "morphir-warning-v1" ||
    text(f, "severity") != "warning" {
    raise InvalidDiagnostic("Unsupported warning contract")
  }
  guard f["locations"].kind() is List(items) else {
    raise InvalidDiagnostic("Expected warning locations")
  }
  let locations = items.map(item => {
    if item.has_annotations() {
      raise InvalidDiagnostic("Annotated warning location")
    }
    let loc = fields(item, ["owner", "original", "allocated", "source"])
    let source = if loc["source"].kind() is Null(@ion.Null) {
      None
    } else {
      let s = fields(loc["source"], [
        "start_line", "start_column", "end_line", "end_column",
      ])
      let span : Span = {
        start_line: number(s, "start_line"),
        start_column: number(s, "start_column"),
        end_line: number(s, "end_line"),
        end_column: number(s, "end_column"),
      }
      if span.end_line < span.start_line ||
        (
          span.end_line == span.start_line &&
          span.end_column < span.start_column
        ) {
        raise InvalidDiagnostic("Reversed diagnostic span")
      }
      Some(span)
    }
    Location::{
      owner: text(loc, "owner"),
      original: text(loc, "original"),
      allocated: text(loc, "allocated"),
      source,
    }
  })
  Some({
    code: text(f, "code"),
    stage: text(f, "stage"),
    message: text(f, "message"),
    locations,
    fix: text(f, "fix"),
  })
}

///|
/// Length prefixes prevent separator-bearing owner strings from aliasing keys.
pub fn Warning::key(self : Warning) -> String {
  let parts = [self.code, self.stage]
  for loc in self.locations {
    parts.push(loc.owner)
    parts.push(loc.allocated)
  }
  parts.map(p => p.length().to_string() + ":" + p).join("")
}

///|
pub fn Warning::display(self : Warning) -> String {
  let lines = [self.code + ": " + self.message]
  for loc in self.locations {
    let span = match loc.source {
      Some(s) =>
        ":" + s.start_line.to_string() + ":" + s.start_column.to_string()
      None => ""
    }
    lines.push(
      "  " + loc.owner + span + ": " + loc.original + " -> " + loc.allocated,
    )
  }
  lines.push("  fix: " + self.fix)
  lines.join("\n")
}
