///|
pub const PROFILE : String = "morphir/workbench/worksheet"

///|
pub const CONTRACT_VERSION : String = "0.1.0-draft.1"

///|
pub struct WorksheetRequest {
  priv source : CapturedWorksheetSource
} derive(Eq)

///|
pub extend WorksheetRequest with Eq::{equal, not_equal}

///|
pub struct FormId {
  priv index : Int32
} derive(Eq, Debug)

///|
pub extend FormId with Eq::{equal, not_equal}

///|
pub extend FormId with @debug.Debug::{to_repr}

///|
priv struct WorksheetForm {
  id : FormId
  range : Utf16Range
  expression : String
  datum : @scheme.Datum
} derive(Eq)

///|
priv enum DocumentKind {
  RequestDocument
  ReportDocument
}

///|
fn json_strings_valid(value : Json) -> Bool {
  match value {
    String(text) => well_formed(text)
    Array(items) => items.all(json_strings_valid)
    Object(fields) =>
      fields
      .iter()
      .all(pair => well_formed(pair.0) && json_strings_valid(pair.1))
    _ => true
  }
}

///|
fn decode_json(source : String, kind : DocumentKind) -> Json raise {
  let limit = match kind {
    RequestDocument => "worksheet.input_limit"
    ReportDocument => "worksheet.output_limit"
  }
  if source.length() > 2097152 || @utf8.encode(source).length() > 2097152 {
    raise @execution.Invalid(limit)
  }
  if !well_formed(source) {
    raise @execution.Invalid("worksheet.invalid_json")
  }
  let value = @wire.parse_bounded(
    source,
    max_depth=160,
    max_nodes=500000,
    max_string_units=2097152,
  ) catch {
    _ => raise @execution.Invalid("worksheet.invalid_json")
  }
  if !json_strings_valid(value) {
    raise @execution.Invalid("worksheet.invalid_json")
  }
  value
}

///|
pub fn WorksheetRequest::new(
  source : CapturedWorksheetSource,
) -> WorksheetRequest raise {
  let request = WorksheetRequest::{ source, }
  if @utf8.encode(request.to_json().stringify()).length() > 2097152 {
    raise @execution.Invalid("worksheet.input_limit")
  }
  request
}

///|
pub fn WorksheetRequest::source(
  self : WorksheetRequest,
) -> CapturedWorksheetSource {
  self.source
}

///|
pub fn WorksheetRequest::to_json(self : WorksheetRequest) -> Json {
  {
    "profile": PROFILE,
    "contractVersion": CONTRACT_VERSION,
    "source": self.source.to_json(),
  }
}

///|
pub fn WorksheetRequest::decode(source : String) -> WorksheetRequest raise {
  let code = "worksheet.invalid_request"
  let fields = object(
    decode_json(source, RequestDocument),
    ["profile", "contractVersion", "source"],
    code,
  )
  if fields["profile"] != Json::string(PROFILE) ||
    fields["contractVersion"] != Json::string(CONTRACT_VERSION) {
    raise @execution.Invalid(code)
  }
  WorksheetRequest::new(CapturedWorksheetSource::from_json(fields["source"]))
}

///|
fn scalar_prefix(source : CapturedWorksheetSource) -> Array[Int32] {
  let offsets = [0]
  let mut units = 0
  for character in source.text().iter() {
    units += if character.to_int() > 65535 { 2 } else { 1 }
    offsets.push(units)
  }
  offsets
}

///|
fn inventory(source : CapturedWorksheetSource) -> Array[WorksheetForm] raise {
  let offsets = scalar_prefix(source)
  let forms = @scheme.parse_program_ranged(source.text())
  if forms.length() > 1000 {
    raise @execution.Invalid("worksheet.input_limit")
  }
  forms.mapi((index, form) => {
    let range = Utf16Range::new(
      source,
      offsets[form.scalar_start()],
      offsets[form.scalar_end()],
    )
    {
      id: { index, },
      range,
      expression: range.slice(source),
      datum: form.datum(),
    }
  })
}
