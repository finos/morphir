///|
pub fn args() -> Array[String] {
  @env.args()
}

///|
pub fn environment() -> Map[String, String] {
  @env.get_env_vars()
}

///|
pub fn cwd() -> String {
  @env.current_dir().unwrap_or(".")
}

///|
pub fn read_bytes(path : String) -> Bytes raise {
  if kind(path) != 1 {
    raise IOError("Input must be a regular file: " + path)
  }
  let length = size(path)
  if length < 0 || length > 16777216 {
    raise IOError("Unreadable file or file exceeds 16 MiB: " + path)
  }
  @fs.read_file_to_bytes(path)
}

///|
pub fn write(path : String, content : String) -> Unit raise {
  @fs.write_string_to_file(path, content)
}

///|
pub fn list(path : String) -> Array[String] raise {
  @fs.read_dir(path).to_owned()
}

///|
pub fn remove_file(path : String) -> Unit raise {
  @fs.remove_file(path)
}

///|
pub fn remove_dir(path : String) -> Unit raise {
  @fs.remove_dir(path)
}

///|
pub fn read(path : String) -> String raise {
  @utf8.decode(read_bytes(path)[:])
}

///|
pub fn write_bytes(path : String, content : Bytes) -> Unit raise {
  @fs.write_bytes_to_file(path, content)
}

///|
/// Scan a regular file in immutable chunks of at most 64 KiB. The complete
/// stream is capped at 512 MiB, separate from model payload read limits. The
/// descriptor is always closed, including consumer failures. Caller-owned paths
/// must remain stable under the portable host's filesystem assumptions.
pub fn file_chunks(
  path : String,
  limit : Int,
  consume : (Bytes) -> Unit raise,
) -> Unit raise {
  if path.contains("\u0000") ||
    limit < 1 ||
    limit > 536870912 ||
    kind(path) != 1 {
    raise IOError("metadata.restore_identity_unavailable")
  }
  let fd = file_open(path, limit)
  if fd < 0 {
    raise IOError("metadata.restore_identity_unavailable")
  }
  defer ignore(file_close(fd))
  let mut total = 0
  while true {
    let buffer = FixedArray::make(65536, b'\x00')
    let length = file_read(fd, buffer, 65536)
    if length < 0 || length > 65536 {
      raise IOError("metadata.restore_identity_unavailable")
    }
    if length == 0 {
      break
    }
    total += length
    if total > limit {
      raise IOError("metadata.restore_identity_limit")
    }
    consume(Bytes::from_array(buffer[:length].to_owned()))
  }
}

///|
/// Only indicates that bounded pin reads exist. The provider must still probe
/// its selected supervisor, byte channel, process lifecycle and restore profile.
#cfg(target="native")
pub fn file_chunks_supported() -> Bool {
  true
}
