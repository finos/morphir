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
  InvalidDiagnostic(String)
  InvalidClaim(String)
} derive(Eq, Debug)

///|
pub extend ValueError with Eq::{equal, not_equal}

///|
pub extend ValueError with @debug.Debug::{to_repr}

///|
pub impl Show for ValueError with fn output(self, logger) {
  logger.write_string(
    match self {
      InvalidSha256(text) => "invalid SHA-256 digest \{text}"
      InvalidArtifactPath(text) => "invalid artifact path \{text}"
      UnknownPlatform(text) => "unknown platform \{text}"
      UnknownWasmAbi(text) => "unknown WASM ABI \{text}"
      InvalidExtensionId(text) => "invalid extension ID \{text}"
      InvalidExtensionVersion(text) => "invalid extension version \{text}"
      UnknownOperation(text) => "unknown operation \{text}"
      UnknownProtocolLine(text) => "unknown protocol version \{text}"
      UnknownModelTuplePart(text) => "unknown model tuple part \{text}"
      InvalidLimit(text) => "invalid limit \{text}"
      InvalidDeadline(ms) => "invalid deadline \{ms} ms"
      EmptyLanguageClaim(text) => "language \{text} has no file extensions"
      InvalidIrVersionName(text) => "invalid IR version name \{text}"
      InvalidRuntime(text) => "invalid runtime: \{text}"
      InvalidArtifact(text) => "invalid artifact: \{text}"
      InvalidDiagnostic(text) => "invalid diagnostic: \{text}"
      InvalidClaim(text) => "invalid claim: \{text}"
    },
  )
}

///|
pub extend ValueError with Show::{to_string, output}
