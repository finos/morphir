///|
/// A value from outside the host that does not fit its domain type. Decoders
/// at the boundary raise it; the CLI maps it to its own refusal codes.
pub(all) suberror ValueError {
  InvalidSha256(String)
  InvalidArtifactPath(String)
  UnknownPlatform(String)
  UnknownWasmAbi(String)
  InvalidExtensionId(String)
  InvalidExtensionVersion(String)
  UnknownOperation(String)
  UnknownProtocolLine(String)
  UnknownModelTuplePart(String)
  InvalidLimit(String)
  InvalidDeadline(Int32)
  EmptyLanguageClaim(String)
  InvalidIrVersionName(String)
  InvalidRuntime(String)
  InvalidArtifact(String)
} derive(Eq, Debug)

///|
pub extend ValueError with Eq::{equal, not_equal}

///|
pub extend ValueError with @debug.Debug::{to_repr}
