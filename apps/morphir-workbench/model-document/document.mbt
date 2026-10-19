///|
/// Preserve the Workbench import boundary. Original bytes, revisions and
/// lifecycle decisions have one application-independent owner.
pub using @shared {
  type DocumentError,
  type SourceCodec,
  type OriginalFilename,
  type OriginalFile,
  type OriginalPath,
  type OriginalTree,
  type ProjectionReason,
  type Source,
  type Document,
  type OpenAttempt,
  type DocumentRevision,
  type HostRetention,
  type BeginDecision,
  type CloseDecision,
  type State,
}
