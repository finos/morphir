///|
/// Exact IR format release, independent of the library's own release version.
pub struct FormatVersion {
  major : UInt32
  minor : UInt32
  patch : UInt32
} derive(Eq, Compare, Hash, Debug)

///|
pub(all) suberror VersionError {
  InvalidSyntax(String)
  OutOfRange(String)
  UnsupportedMajor(UInt32)
  UnsupportedMinor(UInt32, UInt32)
  FamilyMismatch(UInt32, UInt32)
  SpecsBefore3_1
} derive(Eq, Debug)

///|
pub fn FormatVersion::new(
  major : UInt32,
  minor : UInt32,
  patch : UInt32,
) -> FormatVersion raise VersionError {
  if major == 0 || (major < 3 && (minor != 0 || patch != 0)) {
    raise InvalidSyntax("Invalid historical format version")
  }
  { major, minor, patch, }
}

///|
fn parse_component(text : String) -> UInt32 raise VersionError {
  if text.is_empty() || (text.length() > 1 && text.has_prefix("0")) {
    raise InvalidSyntax(text)
  }
  let mut value = 0U
  for character in text {
    if character < '0' || character > '9' {
      raise InvalidSyntax(text)
    }
    let digit = (character.to_int() - 48).reinterpret_as_uint()
    if value > (4294967295U - digit) / 10U {
      raise OutOfRange(text)
    }
    value = value * 10U + digit
  }
  value
}

///|
/// Parse a release string. Historical v1 and v2 only have integer wire forms.
pub fn FormatVersion::parse(text : String) -> FormatVersion raise VersionError {
  let components = text.split(".").collect()
  if components.length() != 3 {
    raise InvalidSyntax(text)
  }
  let major = parse_component(components[0].to_owned())
  let minor = parse_component(components[1].to_owned())
  let patch = parse_component(components[2].to_owned())
  if major < 3 {
    raise InvalidSyntax(text)
  }
  FormatVersion::new(major, minor, patch)
}

///|
/// Baseline release for an integer formatVersion.
pub fn FormatVersion::baseline(
  major : UInt32,
) -> FormatVersion raise VersionError {
  FormatVersion::new(major, 0U, 0U)
}

///|
pub fn FormatVersion::to_release_string(self : FormatVersion) -> String {
  "\{self.major}.\{self.minor}.\{self.patch}"
}

///|
/// Model coverage: historical 1 and 2, [3.0.0,3.2.0), [4.0.0,4.1.0).
/// Historical v1 and v2 are supported in addition to the current upstream table.
pub fn FormatVersion::check_supported(
  self : FormatVersion,
) -> Unit raise VersionError {
  match self.major {
    1U | 2U => ()
    3U if self.minor < 2U => ()
    4U if self.minor == 0U => ()
    3U | 4U => raise UnsupportedMinor(self.major, self.minor)
    _ => raise UnsupportedMajor(self.major)
  }
}

///|
pub fn FormatVersion::check_family(
  self : FormatVersion,
  major : UInt32,
) -> Unit raise VersionError {
  self.check_supported()
  if self.major != major {
    raise FamilyMismatch(major, self.major)
  }
}
