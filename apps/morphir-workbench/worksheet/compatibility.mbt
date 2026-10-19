///|
/// Compatibility boundary for existing Workbench consumers. The processor and
/// contract have one owner in the application-independent engine package.
pub using @shared {
  type WorksheetId,
  type SourceRevision,
  type CapturedWorksheetSource,
  type Utf16Offset,
  type Utf16Range,
  type WorksheetRequest,
  type FormId,
  type Observation,
  type WorksheetReport,
  type WorkerTermination,
  browser_command,
}

///|
pub const PROFILE : String = @shared.PROFILE

///|
pub const CONTRACT_VERSION : String = @shared.CONTRACT_VERSION
