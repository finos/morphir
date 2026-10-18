///|
pub struct WorksheetId {
  priv text : String
} derive(Eq, Debug)

///|
pub struct SourceRevision {
  priv number : Int32
} derive(Eq, Debug)

///|
pub struct CapturedWorksheetSource {
  priv snapshot : @data.SourceSnapshot
  priv revision : SourceRevision
} derive(Eq, Debug)

///|
pub struct Utf16Offset {
  priv units : Int32
} derive(Eq, Debug)

///|
pub struct Utf16Range {
  priv start : Utf16Offset
  priv end : Utf16Offset
} derive(Eq, Debug)

///|
pub extend CapturedWorksheetSource with Eq::{equal, not_equal}

///|
pub extend Utf16Range with Eq::{equal, not_equal}

///|
pub extend WorksheetId with Eq::{equal, not_equal}

///|
pub extend SourceRevision with Eq::{equal, not_equal}

///|
pub extend Utf16Offset with Eq::{equal, not_equal}

///|
pub extend WorksheetId with @debug.Debug::{to_repr}

///|
pub extend SourceRevision with @debug.Debug::{to_repr}

///|
pub extend CapturedWorksheetSource with @debug.Debug::{to_repr}

///|
pub extend Utf16Offset with @debug.Debug::{to_repr}

///|
pub extend Utf16Range with @debug.Debug::{to_repr}

///|
fn well_formed(text : String) -> Bool {
  let mut index = 0
  while index < text.length() {
    let unit = text.code_unit_at(index).to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if index + 1 >= text.length() {
        return false
      }
      let next = text.code_unit_at(index + 1).to_int()
      if next < 0xDC00 || next > 0xDFFF {
        return false
      }
      index += 2
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      return false
    } else {
      index += 1
    }
  }
  true
}

///|
pub fn WorksheetId::parse(text : String) -> WorksheetId raise {
  if text == "" ||
    text.length() > 128 ||
    !well_formed(text) ||
    text
    .iter()
    .any(c => c.to_int() < 32 || (c.to_int() >= 127 && c.to_int() <= 159)) {
    raise @execution.Invalid("worksheet.invalid_request")
  }
  { text, }
}

///|
pub fn SourceRevision::new(number : Int32) -> SourceRevision raise {
  if number < 0 {
    raise @execution.Invalid("worksheet.invalid_request")
  }
  { number, }
}

///|
pub fn CapturedWorksheetSource::new(
  id : WorksheetId,
  revision : SourceRevision,
  text : String,
) -> CapturedWorksheetSource raise {
  if text.length() > 262144 || !well_formed(text) {
    raise @execution.Invalid("worksheet.invalid_request")
  }
  if @utf8.encode(text).length() > 1048576 {
    raise @execution.Invalid("worksheet.invalid_request")
  }
  { snapshot: { unit_id: id.text, content: @data.Text(text), }, revision, }
}

///|
pub fn CapturedWorksheetSource::text(self : CapturedWorksheetSource) -> String {
  match self.snapshot.content {
    Text(text) => text
    Binary(_) => abort("captured worksheet constructor accepts only text")
  }
}

///|
pub fn CapturedWorksheetSource::to_json(self : CapturedWorksheetSource) -> Json {
  {
    "id": self.snapshot.unit_id,
    "revision": self.revision.number,
    "text": self.text(),
  }
}

///|
fn object(
  value : Json,
  names : Array[String],
  code : String,
) -> Map[String, Json] raise {
  let fields = @wire.object(value) catch { _ => raise @execution.Invalid(code) }
  if fields.length() != names.length() ||
    names.any(name => !fields.contains(name)) {
    raise @execution.Invalid(code)
  }
  fields
}

///|
fn integer(value : Json, code : String) -> Int32 raise {
  if !@wire.is_integral_number(value) {
    raise @execution.Invalid(code)
  }
  match value {
    Number(number, ..) if number >= 0.0 && number <= 2147483647.0 =>
      number.to_int()
    _ => raise @execution.Invalid(code)
  }
}

///|
fn string(value : Json, code : String) -> String raise {
  @wire.string(value) catch {
    _ => raise @execution.Invalid(code)
  }
}

///|
pub fn CapturedWorksheetSource::from_json(
  value : Json,
) -> CapturedWorksheetSource raise {
  let code = "worksheet.invalid_request"
  let fields = object(value, ["id", "revision", "text"], code)
  CapturedWorksheetSource::new(
    WorksheetId::parse(string(fields["id"], code)),
    SourceRevision::new(integer(fields["revision"], code)),
    string(fields["text"], code),
  )
}

///|
fn boundary(text : String, offset : Int32) -> Bool {
  offset >= 0 &&
  offset <= text.length() &&
  !(offset > 0 &&
  offset < text.length() &&
  text.code_unit_at(offset).to_int() >= 0xDC00 &&
  text.code_unit_at(offset).to_int() <= 0xDFFF)
}

///|
pub fn Utf16Range::new(
  source : CapturedWorksheetSource,
  start : Int32,
  end : Int32,
) -> Utf16Range raise {
  let text = source.text()
  if start > end || !boundary(text, start) || !boundary(text, end) {
    raise @execution.Invalid("worksheet.invalid_range")
  }
  { start: { units: start, }, end: { units: end, }, }
}

///|
pub fn Utf16Range::to_json(self : Utf16Range) -> Json {
  { "start": self.start.units, "end": self.end.units }
}

///|
pub fn Utf16Range::slice(
  self : Utf16Range,
  source : CapturedWorksheetSource,
) -> String raise {
  // Revalidate against the supplied source; a range alone conveys no ownership.
  ignore(Utf16Range::new(source, self.start.units, self.end.units))
  source.text()[self.start.units:self.end.units].to_owned()
}
