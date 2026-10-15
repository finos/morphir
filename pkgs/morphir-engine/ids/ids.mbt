///|
/// Text that is non-empty, at most 256 characters and has no control characters.
fn bounded(text : String, kind : String) -> String raise @config.Invalid {
  if text == "" ||
    text.length() > 256 ||
    text.to_array().any(c => c.to_int() < 32 || c.to_int() == 127) {
    raise @config.Invalid(
      "frontend.invalid_" + kind + ": Expected a bounded nonempty identifier",
    )
  }
  text
}

///|
/// A lowercase letter, then lowercase letters, digits and `-`, at most 64 characters.
fn word(text : String, kind : String) -> String raise @config.Invalid {
  let chars = text.to_array()
  let valid = chars.length() > 0 &&
    chars.length() <= 64 &&
    chars[0] >= 'a' &&
    chars[0] <= 'z' &&
    chars.all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')
  if !valid {
    raise @config.Invalid(
      "frontend.invalid_" +
      kind +
      ": Expected a lowercase letter, then lowercase letters, digits and '-': " +
      text,
    )
  }
  text
}

///|
/// A source language, for example `elm`.
pub struct LanguageId(String) derive(Eq, Compare, Hash, Debug)

///|
pub fn LanguageId::parse(text : String) -> LanguageId raise @config.Invalid {
  LanguageId(word(text, "language"))
}

///|
pub impl Show for LanguageId with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend LanguageId with Eq::{equal, not_equal}

///|
pub extend LanguageId with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend LanguageId with Hash::{hash, hash_combine}

///|
pub extend LanguageId with @debug.Debug::{to_repr}

///|
pub extend LanguageId with Show::{to_string, output}

///|
/// A source provider, for example `finos/morphir-elm`. A frontend from `register_frontend` uses its language name.
pub struct ProviderId(String) derive(Eq, Compare, Hash, Debug)

///|
pub fn ProviderId::parse(text : String) -> ProviderId raise @config.Invalid {
  ProviderId(bounded(text, "provider"))
}

///|
pub impl Show for ProviderId with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend ProviderId with Eq::{equal, not_equal}

///|
pub extend ProviderId with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend ProviderId with Hash::{hash, hash_combine}

///|
pub extend ProviderId with @debug.Debug::{to_repr}

///|
pub extend ProviderId with Show::{to_string, output}

///|
/// A source profile, for example `library`.
pub struct ProfileId(String) derive(Eq, Compare, Hash, Debug)

///|
pub fn ProfileId::parse(text : String) -> ProfileId raise @config.Invalid {
  ProfileId(word(text, "profile"))
}

///|
pub impl Show for ProfileId with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend ProfileId with Eq::{equal, not_equal}

///|
pub extend ProfileId with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend ProfileId with Hash::{hash, hash_combine}

///|
pub extend ProfileId with @debug.Debug::{to_repr}

///|
pub extend ProfileId with Show::{to_string, output}

///|
/// A generation or output backend, for example `moonbit`.
pub struct BackendId(String) derive(Eq, Compare, Hash, Debug)

///|
pub fn BackendId::parse(text : String) -> BackendId raise @config.Invalid {
  BackendId(word(text, "backend"))
}

///|
pub impl Show for BackendId with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend BackendId with Eq::{equal, not_equal}

///|
pub extend BackendId with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend BackendId with Hash::{hash, hash_combine}

///|
pub extend BackendId with @debug.Debug::{to_repr}

///|
pub extend BackendId with Show::{to_string, output}

///|
/// A file extension with its leading dot, for example `.elm`.
pub struct FileExtension(String) derive(Eq, Compare, Hash, Debug)

///|
pub fn FileExtension::parse(
  text : String,
) -> FileExtension raise @config.Invalid {
  let valid = text.length() > 1 &&
    text.length() <= 256 &&
    text.has_prefix(".") &&
    !text.to_array().any(c => c.to_int() < 32 || c.to_int() == 127) &&
    !text.contains("/") &&
    !text.contains("\\") &&
    !text.contains(":")
  if !valid {
    raise @config.Invalid("frontend.invalid_extensions: " + text)
  }
  FileExtension(text)
}

///|
pub impl Show for FileExtension with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend FileExtension with Eq::{equal, not_equal}

///|
pub extend FileExtension with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend FileExtension with Hash::{hash, hash_combine}

///|
pub extend FileExtension with @debug.Debug::{to_repr}

///|
pub extend FileExtension with Show::{to_string, output}

///|
/// A source file path relative to the source directory, with `/` separators, for example `My/Pkg/Api.elm`.
pub struct SourcePath(String) derive(Eq, Compare, Hash, Debug)

///|
pub fn SourcePath::parse(text : String) -> SourcePath raise @config.Invalid {
  let parts = text.split("/").map(StringView::to_owned).collect()
  let valid = text.length() <= 4096 &&
    !text
    .to_array()
    .any(c => c.to_int() < 32 || c.to_int() == 127 || c == '\\' || c == ':') &&
    parts.all(p => p != "" && p != "." && p != "..")
  if !valid {
    raise @config.Invalid("frontend.invalid_source_path: " + text)
  }
  SourcePath(text)
}

///|
pub impl Show for SourcePath with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend SourcePath with Eq::{equal, not_equal}

///|
pub extend SourcePath with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend SourcePath with Hash::{hash, hash_combine}

///|
pub extend SourcePath with @debug.Debug::{to_repr}

///|
pub extend SourcePath with Show::{to_string, output}

///|
/// A module name in the source language's own syntax, as `morphir.json` writes it, for example `Sub.Util`.
pub struct SourceModuleName(String) derive(Eq, Compare, Hash, Debug)

///|
pub fn SourceModuleName::parse(
  text : String,
) -> SourceModuleName raise @config.Invalid {
  let checked = bounded(text, "module")
  if checked.to_array().any(c => c == ' ' || c == '/' || c == '\\') {
    raise @config.Invalid("frontend.invalid_module: " + text)
  }
  SourceModuleName(checked)
}

///|
pub impl Show for SourceModuleName with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
pub extend SourceModuleName with Eq::{equal, not_equal}

///|
pub extend SourceModuleName with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend SourceModuleName with Hash::{hash, hash_combine}

///|
pub extend SourceModuleName with @debug.Debug::{to_repr}

///|
pub extend SourceModuleName with Show::{to_string, output}

///|
/// A package name as written in the project configuration, for example `Parity.Modules`. The source language
/// matches module headers against this text; `to_path` gives the canonical Morphir path.
pub struct SourcePackageName {
  priv text : String
  priv path : @ir.Path
} derive(Eq, Compare, Hash, Debug)

///|
pub fn SourcePackageName::parse(
  text : String,
) -> SourcePackageName raise @config.Invalid {
  let checked = bounded(text, "package")
  let path = @ir.Path::parse(canonical_path(checked)) catch {
    _ => raise @config.Invalid("frontend.invalid_package: " + text)
  }
  { text: checked, path, }
}

///|
/// The canonical Morphir path of the package, computed once by `parse`.
pub fn SourcePackageName::to_path(self : SourcePackageName) -> @ir.Path {
  self.path
}

///|
pub impl Show for SourcePackageName with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend SourcePackageName with Eq::{equal, not_equal}

///|
pub extend SourcePackageName with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend SourcePackageName with Hash::{hash, hash_combine}

///|
pub extend SourcePackageName with @debug.Debug::{to_repr}

///|
pub extend SourcePackageName with Show::{to_string, output}
