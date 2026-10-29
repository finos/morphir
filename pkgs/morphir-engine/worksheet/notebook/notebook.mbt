///|
pub const PROFILE : String = "morphir/worksheet-notebook"

///|
pub const VERSION : String = "0.1.0"

///|
pub(all) enum Format {
  Ipynb
  Dib
} derive(Eq, Debug)

///|
pub fn Format::parse(name : String) -> Format raise {
  match name {
    "ipynb" => Ipynb
    "dib" => Dib
    _ => raise UnsupportedFormat(name)
  }
}

///|
pub fn Format::name(self : Format) -> String {
  match self {
    Ipynb => "ipynb"
    Dib => "dib"
  }
}

///|
pub suberror Invalid {
  UnsupportedFormat(String)
  OutputsRequireJupyter
  StaleObservations
  TooManyForms
} derive(Debug)

///|
pub fn Invalid::code(self : Invalid) -> String {
  match self {
    UnsupportedFormat(_) => "notebook.unsupported_format"
    OutputsRequireJupyter => "notebook.outputs_require_jupyter"
    StaleObservations => "notebook.stale_observations"
    TooManyForms => "worksheet.input_limit"
  }
}

///|
pub fn Invalid::message(self : Invalid) -> String {
  match self {
    UnsupportedFormat(name) => "Unsupported notebook format: " + name
    OutputsRequireJupyter =>
      "Saved outputs require Jupyter; DIB preserves source only"
    StaleObservations => "Observations belong to another worksheet source"
    TooManyForms => "Too many worksheet forms"
  }
}

///|
pub struct Exported {
  priv content : String
  priv cells : Int32
}

///|
pub enum SkipReason {
  OtherLanguage(String)
  Raw
  Unknown(String)
} derive(Eq, Debug)

///|
pub struct SkippedCell {
  priv index : Int32
  priv name : String
  priv reason : SkipReason
} derive(Eq, Debug)

///|
pub fn SkippedCell::to_json(self : SkippedCell) -> Json {
  let reason = match self.reason {
    OtherLanguage(language) => "Cell language is " + language
    Raw => "Raw cell"
    Unknown(kind) => "Unknown cell type: " + kind
  }
  { "index": self.index, "name": self.name, "reason": reason }
}

///|
pub struct Imported {
  priv source : String
  priv cells : Int32
  priv skipped : Array[SkippedCell]
}

///|
priv enum CellSource {
  Form(String, @worksheet.Utf16Range)
  Comment(String)
}

///|
fn inventory(
  source : @worksheet.CapturedWorksheetSource,
) -> Array[CellSource] raise {
  let text = source.text()
  let offsets = [0]
  let mut units = 0
  for character in text.iter() {
    units += if character.to_int() > 65535 { 2 } else { 1 }
    offsets.push(units)
  }
  let (forms, comments) = @scheme.parse_program_with_comments(text)
  if forms.length() > 1000 {
    raise TooManyForms
  }
  let cells = []
  let mut next_comment = 0
  fn collect_comments(before : Int32) {
    let block : Array[String] = []
    let mut last_end : Int32? = None
    while next_comment < comments.length() &&
          comments[next_comment].scalar_start() < before {
      let comment = comments[next_comment]
      let (start, end) = (comment.scalar_start(), comment.scalar_end())
      if last_end is Some(last) &&
        text[offsets[last]:offsets[start]].iter().filter(c => c == '\n').count() !=
        1 {
        cells.push(Comment(block.join("\n")))
        block.clear()
      }
      let raw = text[offsets[start] + 2:offsets[end]]
      let raw = if raw.has_suffix("\r") { raw[:raw.length() - 1] } else { raw }
      block.push(
        if raw.has_prefix(" ") {
          raw[1:].to_owned()
        } else {
          raw.to_owned()
        },
      )
      last_end = Some(end)
      next_comment += 1
    }
    if !block.is_empty() {
      cells.push(Comment(block.join("\n")))
    }
  }
  for form in forms {
    collect_comments(form.scalar_start())
    let range = @worksheet.Utf16Range::new(
      source,
      offsets[form.scalar_start()],
      offsets[form.scalar_end()],
    )
    cells.push(Form(range.slice(source), range))
  }
  collect_comments(offsets.length())
  cells
}

///|
fn metadata() -> @notebooks.Metadata raise {
  @notebooks.Metadata({
    "morphir": { "profile": PROFILE, "version": VERSION },
    "kernelspec": {
      "name": "scheme",
      "language": "scheme",
      "display_name": "Scheme",
    },
    "language_info": { "name": "scheme" },
  })
}

///|
fn registry() -> @dib.KernelRegistry raise {
  let standard = @dib.KernelRegistry::standard()
  let kernels = standard.kernels().iter().to_array()
  for name in ["scheme", "python", "r"] {
    kernels.push(@dib.KernelInfo(@dib.KernelName(name), language=Some(name)))
  }
  @dib.KernelRegistry(
    ReadOnlyArray::from_array(kernels[:]),
    default_kernel=standard.default_kernel(),
  )
}

///|
fn observation_output(
  row : @worksheet.Observation,
  encoded : Json,
  count : Int32,
) -> @nbformat.Output raise {
  match row.outcome() {
    Returned(_) =>
      @nbformat.Output::Output(
        ExecuteResult(
          data=@nbformat.MimeBundle({
            "text/plain": row.preview(),
            "application/vnd.morphir.observation+json": encoded,
          }),
          metadata=@notebooks.Metadata::empty(),
          execution_count=Some(@nbformat.ExecutionCount(count)),
        ),
      )
    ModelError(message) =>
      @nbformat.Output::Output(
        Error(ename="ModelError", evalue=message, traceback=[]),
      )
    Failed(failure) =>
      @nbformat.Output::Output(
        Error(ename=failure.code, evalue=failure.message, traceback=[]),
      )
    Cancelled =>
      @nbformat.Output::Output(
        Error(ename="Cancelled", evalue="Worksheet evaluation was cancelled", traceback=[]),
      )
  }
}

///|
/// Convert a captured source and, optionally, observations from that exact source.
/// Evaluation belongs to the caller. DIB cannot persist observations.
pub fn export_notebook(
  source : @worksheet.CapturedWorksheetSource,
  format : Format,
  report? : @worksheet.WorksheetReport,
) -> Exported raise {
  if report is Some(_) {
    format.require_outputs()
  }
  if report is Some(report) && report.source() != source {
    raise StaleObservations
  }
  let sources = inventory(source)
  match format {
    Dib => {
      let cells = sources.map(cell => {
        match cell {
          Form(text, _) =>
            @dib.Cell::Cell(
              text,
              kernel=@dib.KernelName("scheme"),
              source_mode=Lossless,
            )
          Comment(text) =>
            @dib.Cell::Cell(
              text,
              kernel=@dib.KernelName("markdown"),
              source_mode=Lossless,
            )
        }
      })
      let notebook = @dib.Notebook::Notebook(
        ReadOnlyArray::from_array(cells[:]),
        metadata=metadata(),
        registry=registry(),
      )
      {
        content: notebook.to_string(source_mode=Lossless),
        cells: cells.length(),
      }
    }
    Ipynb => {
      let rows = report.map(r => r.observations()).unwrap_or([])
      let encoded_rows = match report {
        Some(report) =>
          match report.to_json() {
            Object(fields) =>
              match fields.get("observations") {
                Some(Array(values)) => values
                _ => []
              }
            _ => []
          }
        None => []
      }
      let cells = sources.mapi((index, cell) => {
        let content = match cell {
          Comment(text) => @nbformat.Markdown(source=text, attachments=None)
          Form(text, range) => {
            let outputs = []
            let mut count = None
            for i, row in rows {
              if row.range() == range {
                count = Some(@nbformat.ExecutionCount(i + 1))
                outputs.push(observation_output(row, encoded_rows[i], i + 1))
              }
            }
            @nbformat.Code(
              source=text,
              execution_count=count,
              outputs=ReadOnlyArray::from_array(outputs[:]),
            )
          }
        }
        @nbformat.Cell::Cell(
          content,
          id=Some(@nbformat.CellId("cell-" + index.to_string())),
          metadata=@notebooks.Metadata({ "language": "scheme" }),
        )
      })
      let notebook = @nbformat.Notebook::Notebook(
        ReadOnlyArray::from_array(cells[:]),
        metadata=metadata(),
      )
      { content: notebook.to_string(), cells: cells.length(), }
    }
  }
}

///|
fn field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn language(value : Json) -> String? {
  let direct = field(value, "language")
  if direct is String(name) {
    return Some(name)
  }
  for
    (owner, key) in [
      ("polyglot_notebook", "kernelName"),
      ("dotnet_interactive", "language"),
      ("vscode", "languageId"),
    ] {
    if field(field(value, owner), key) is String(name) {
      return Some(name)
    }
  }
  None
}

///|
fn comment_source(text : String) -> String {
  text
  .replace_all(old="\r\n", new="\n")
  .split("\n")
  .map(line => if line.is_empty() { ";;" } else { ";; " + line.to_owned() })
  .join("\n")
}

///|
/// Read through Moon-Lander notebook models; imported execution outputs confer
/// no evaluation authority and are never copied into the worksheet.
pub fn import_notebook(content : String, format : Format) -> Imported raise {
  let sources = []
  let skipped = []
  let count = match format {
    Ipynb => {
      let notebook = @nbformat.parse(content)
      let metadata = notebook.metadata().to_json()
      let default_language = match
        field(field(metadata, "language_info"), "name") {
        String(name) => name
        _ =>
          match field(field(metadata, "kernelspec"), "language") {
            String(name) => name
            _ => "unknown"
          }
      }
      for index, cell in notebook.cells() {
        let metadata = cell.metadata().to_json()
        let name = match cell.id() {
          Some(id) => id.to_string()
          None => "cell-" + index.to_string()
        }
        match cell.content() {
          Markdown(source~, ..) => sources.push(comment_source(source))
          Code(source~, ..) => {
            let selected = language(metadata).unwrap_or(default_language)
            if selected.to_lower() == "scheme" {
              sources.push(source)
            } else {
              skipped.push({ index, name, reason: OtherLanguage(selected), })
            }
          }
          Raw(..) => skipped.push({ index, name, reason: Raw, })
          Unknown(cell_type~, ..) =>
            skipped.push({ index, name, reason: Unknown(cell_type), })
        }
      }
      notebook.cells().length()
    }
    Dib => {
      let notebook = @dib.parse(
        content,
        registry=registry(),
        source_mode=Lossless,
      )
      for index, cell in notebook.cells() {
        let name = cell.kernel().to_string()
        match name {
          "markdown" => sources.push(comment_source(cell.source()))
          "scheme" => sources.push(cell.source())
          _ =>
            skipped.push({
              index,
              name: "cell-" + index.to_string(),
              reason: OtherLanguage(name),
            })
        }
      }
      notebook.cells().length()
    }
  }
  let source = if sources.is_empty() { "" } else { sources.join("\n\n") + "\n" }
  // Apply the worksheet's existing source bounds without evaluating it.
  ignore(
    @worksheet.CapturedWorksheetSource::new(
      @worksheet.WorksheetId::parse("notebook-import"),
      @worksheet.SourceRevision::new(0),
      source,
    ),
  )
  { source, cells: count, skipped, }
}

///|
pub extend Format with Eq::{equal, not_equal}

///|
pub extend Format with @debug.Debug::{to_repr}

///|
pub extend Invalid with @debug.Debug::{to_repr}

///|
pub extend SkipReason with Eq::{equal, not_equal}

///|
pub extend SkipReason with @debug.Debug::{to_repr}

///|
pub extend SkippedCell with Eq::{equal, not_equal}

///|
pub extend SkippedCell with @debug.Debug::{to_repr}

///|
pub fn Exported::content(self : Exported) -> String {
  self.content
}

///|
pub fn Exported::cells(self : Exported) -> Int32 {
  self.cells
}

///|
pub fn Imported::source(self : Imported) -> String {
  self.source
}

///|
pub fn Imported::cells(self : Imported) -> Int32 {
  self.cells
}

///|
pub fn Imported::skipped(self : Imported) -> Array[SkippedCell] {
  self.skipped.copy()
}

///|
pub fn SkippedCell::index(self : SkippedCell) -> Int32 {
  self.index
}

///|
pub fn SkippedCell::name(self : SkippedCell) -> String {
  self.name
}

///|
pub fn SkippedCell::reason(self : SkippedCell) -> SkipReason {
  self.reason
}

///|
/// Check output support before the caller starts evaluation or writes a file.
pub fn Format::require_outputs(self : Format) -> Unit raise Invalid {
  if self == Dib {
    raise OutputsRequireJupyter
  }
}
