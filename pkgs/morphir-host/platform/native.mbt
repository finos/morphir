///|
fn cstring(s : String) -> Bytes {
  @utf8.encode(s[:]) + b"\x00"
}

///|
#borrow(path)
extern "C" fn kind_c(path : Bytes) -> Int32 = "morphir_host_kind"

///|
#borrow(a, b)
extern "C" fn rename_c(a : Bytes, b : Bytes) -> Int32 = "morphir_host_rename"

///|
#borrow(text)
extern "C" fn stderr_c(text : Bytes) -> Unit = "morphir_host_stderr"

///|
extern "C" fn exit_c(code : Int32) -> Unit = "morphir_host_exit"

///|
pub fn kind(path : String) -> Int32 raise {
  let result = kind_c(cstring(path))
  if result < 0 {
    raise IOError("Cannot inspect " + path)
  }
  result
}

///|
pub fn rename(a : String, b : String) -> Unit raise {
  check(rename_c(cstring(a), cstring(b)), "rename")
}

///|
#borrow(a, b)
extern "C" fn rename_directory_new_c(a : Bytes, b : Bytes) -> Int32 = "morphir_host_rename_directory_new"

///|
pub fn rename_directory_new(a : String, b : String) -> Unit raise {
  match rename_directory_new_c(cstring(a), cstring(b)) {
    0 => ()
    1 => raise IOError("publication.destination_unavailable: " + b)
    2 => raise IOError("publication.create_failed: " + b)
    _ => raise IOError("publication.reservation_cleanup_failed: " + b)
  }
}

///|
pub fn stderr(text : String) -> Unit {
  stderr_c(cstring(text))
}

///|
pub fn exit(code : Int32) -> Unit {
  exit_c(code)
}

///|
pub fn arguments() -> Array[String] {
  args()[1:].to_owned()
}

///|
extern "C" fn system_c() -> Int32 = "morphir_host_system"

///|
pub fn system_type() -> String {
  match system_c() {
    0 => "macos"
    1 => "windows"
    _ => "linux"
  }
}

///|
#borrow(path)
extern "C" fn size_c(path : Bytes) -> Int32 = "morphir_host_size"

///|
fn size(path : String) -> Int32 {
  size_c(cstring(path))
}

///|
pub fn mkdir(path : String) -> Unit raise {
  @fs.create_dir(path)
}

///|
extern "C" fn architecture_c() -> Int32 = "morphir_host_architecture"

///|
pub fn architecture() -> String {
  match architecture_c() {
    0 => "arm64"
    1 => "x64"
    _ => "unknown"
  }
}

///|
pub fn process_supported() -> Bool {
  system_type() != "windows"
}

///|
extern "C" fn temporary_c() -> Bytes = "morphir_host_temporary"

///|
pub fn temporary() -> String raise {
  let path = @utf8.decode(temporary_c()[:])
  if path == "" {
    raise IOError("Cannot create temporary directory")
  }
  path
}

///|
#borrow(program, args, cwd, home)
extern "C" fn process_c(
  program : Bytes,
  args : Bytes,
  count : Int32,
  cwd : Bytes,
  home : Bytes,
  timeout : Int32,
) -> Bytes = "morphir_host_process"

///|
pub fn process(
  program : String,
  args : Array[String],
  cwd : String,
  home : String,
  timeout : Int32,
) -> Json raise {
  let data = process_c(
    cstring(program),
    cstring(args.join("\u0000")),
    args.length(),
    cstring(cwd),
    cstring(home),
    timeout,
  )
  if data.length() < 8 {
    raise IOError("Invalid process response")
  }
  fn word(i : Int32) -> Int32 {
    data[i].to_int() |
    (data[i + 1].to_int() << 8) |
    (data[i + 2].to_int() << 16) |
    (data[i + 3].to_int() << 24)
  }
  let length = word(4)
  if length < 0 || length > data.length() - 8 {
    raise IOError("Invalid process output length")
  }
  process_result(
    word(0),
    @utf8.decode(data[8:8 + length]),
    @utf8.decode(data[8 + length:]),
  )
}

///|
pub extern "C" fn monotonic_seconds() -> Double = "morphir_monotonic_seconds"

///|
pub extern "C" fn wall_seconds() -> Double = "morphir_wall_seconds"

///|
extern "C" fn observation_nonce() -> UInt64 = "morphir_observation_nonce"

///|
pub fn observation_id() -> String {
  observation_nonce().to_string() + "-" + observation_nonce().to_string()
}

///|
#borrow(path, data, root)
extern "C" fn flush_file_c(
  path : Bytes,
  data : Bytes,
  length : Int32,
  timeout : Int32,
  root : Bytes,
) -> Int32 = "morphir_flush_file"

///|
pub fn flush_file(
  path : String,
  data : Bytes,
  timeout : Int32,
  root~ : String = "",
) -> Bool {
  flush_file_c(cstring(path), data, data.length(), timeout, cstring(root)) == 0
}

///|
#borrow(path)
extern "C" fn file_open_c(path : Bytes, limit : Int32) -> Int32 = "morphir_host_file_open"

///|
fn file_open(path : String, limit : Int32) -> Int32 {
  file_open_c(cstring(path), limit)
}

///|
#borrow(buffer)
extern "C" fn file_read(
  fd : Int32,
  buffer : FixedArray[Byte],
  length : Int32,
) -> Int32 = "morphir_host_file_read"

///|
extern "C" fn file_close(fd : Int32) -> Int32 = "morphir_host_file_close"

///|
#borrow(buffer)
extern "C" fn stdin_read(buffer : FixedArray[Byte], length : Int32) -> Int32 = "morphir_host_stdin_read"

///|
pub extern "C" fn interruption_start() -> Unit = "morphir_host_interruption_start"

///|
pub extern "C" fn interruption_stop() -> Unit = "morphir_host_interruption_stop"

///|
pub extern "C" fn interruption_requested() -> Bool = "morphir_host_interruption_requested"

///|
#borrow(path)
extern "C" fn list_bounded_c(path : Bytes, limit : Int32) -> Bytes = "morphir_host_list_bounded"

///|
fn directory_list(path : String, limit : Int32) -> Array[String] raise {
  let packed = list_bounded_c(cstring(path), limit)
  if packed.is_empty() || packed[0] != 0 {
    let code = if packed.is_empty() { 0 } else { packed[0].to_int() }
    raise IOError(
      match code {
        1 => "directory.entry_limit"
        2 => "directory.name_limit"
        4 => "directory.close_failed"
        5 => "directory.open_failed"
        6 => "Cancelled"
        _ => "directory.read_failed"
      },
    )
  }
  let names = []
  let mut start = 1
  let mut units = 0
  for i = 1; i < packed.length(); i = i + 1 {
    if packed[i] == 0 {
      if names.length() >= limit {
        raise IOError("directory.entry_limit")
      }
      let name = @utf8.decode(packed[start:i])
      units = directory_name(name, units)
      names.push(name)
      start = i + 1
    }
  }
  if start != packed.length() {
    raise IOError("directory.invalid_response")
  }
  names
}
