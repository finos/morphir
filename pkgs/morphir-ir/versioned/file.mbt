///|
/// A file retains its version-specific model. No migration is implicit.
#derive(Eq, Debug)
pub(all) enum IRFile {
  V1(@v1.IRFile)
  V2(@v2.IRFile)
  V3(@v3.IRFile)
  V4(@v4.IRFile)
}

///|
pub extend IRFile with Eq::{equal, not_equal}

///|
pub extend IRFile with @debug.Debug::{to_repr}

///|
pub fn IRFile::format_version(self : IRFile) -> @version.FormatVersion {
  match self {
    V1(file) => file.format_version
    V2(file) => file.format_version
    V3(file) => file.format_version
    V4(file) => file.format_version
  }
}
