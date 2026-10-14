///|
/// Migrate to the current model. Unrepresentable data is an error. Classic let placeholders
/// (`is_classic_placeholder`) get the unknown marker.
pub fn to_current(file : @versioned.IRFile) -> @current.IRFile raise {
  match file {
    V1(file) => mark_classic_let_placeholders(@m1.to_current(file))
    V2(file) => mark_classic_let_placeholders(@m2.to_current(file))
    V3(file) => mark_classic_let_placeholders(@m3.to_current(file))
    V4(file) => file
  }
}

///|
/// Convert explicitly to a supported release, refusing lossy downgrades.
pub fn migrate(
  file : @versioned.IRFile,
  target : @version.FormatVersion,
) -> @versioned.IRFile raise {
  target.check_supported()
  // Same-family changes retain all attributes, including classic input annotations.
  match (file, target.major) {
    (V1(file), 1U) =>
      @versioned.V1(@v1.IRFile::new(file.distribution, format_version=target))
    (V2(file), 2U) =>
      @versioned.V2(@v2.IRFile::new(file.distribution, format_version=target))
    (V3(file), 3U) =>
      @versioned.V3(@v3.IRFile::new(file.distribution, format_version=target))
    (V4(file), 4U) =>
      @versioned.V4(
        @current.IRFile::new(file.distribution, format_version=target),
      )
    _ => {
      let current = to_current(file)
      match target.major {
        1U => @versioned.V1(@m1.from_current(current, target))
        2U => @versioned.V2(@m2.from_current(current, target))
        3U => @versioned.V3(@m3.from_current(current, target))
        _ =>
          @versioned.V4(
            @current.IRFile::new(current.distribution, format_version=target),
          )
      }
    }
  }
}
