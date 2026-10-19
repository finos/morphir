///|
/// Directory enumeration is bounded before appending names. The entry limit is
/// inclusive, from zero for empty directories through 65536. Each name is at most 4096
/// UTF-16 units and the complete result at most 1 MiB of UTF-16 units. Names are
/// decoded strictly, preserving Unicode instead of replacing invalid bytes.
pub fn list_bounded(path : String, limit : Int32) -> Array[String] raise {
  directory_request(path, limit)
  directory_list(path, limit)
}

///|
fn directory_request(path : String, limit : Int32) -> Unit raise {
  if limit < 0 || limit > 65536 || path.contains("\u0000") {
    raise IOError("directory.invalid_request")
  }
}

///|
fn directory_name(name : String, units : Int32) -> Int32 raise {
  if name.length() > 4096 || name.length() > 1048576 - units {
    raise IOError("directory.name_limit")
  }
  units + name.length()
}
