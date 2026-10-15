///|
fn cstring(s : String) -> Bytes {
  @utf8.encode(s[:]) + b"\x00"
}

///|
#borrow(path)
extern "C" fn kind_c(path : Bytes) -> Int = "morphir_host_kind"

///|
#borrow(a, b)
extern "C" fn rename_c(a : Bytes, b : Bytes) -> Int = "morphir_host_rename"

///|
#borrow(text)
extern "C" fn stderr_c(text : Bytes) -> Unit = "morphir_host_stderr"

///|
extern "C" fn exit_c(code : Int) -> Unit = "morphir_host_exit"

///|
pub fn kind(path : String) -> Int raise {
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
pub fn stderr(text : String) -> Unit {
  stderr_c(cstring(text))
}

///|
pub fn exit(code : Int) -> Unit {
  exit_c(code)
}

///|
pub fn arguments() -> Array[String] {
  args()[1:].to_owned()
}

///|
extern "C" fn system_c() -> Int = "morphir_host_system"

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
extern "C" fn size_c(path : Bytes) -> Int = "morphir_host_size"

///|
fn size(path : String) -> Int {
  size_c(cstring(path))
}

///|
pub fn mkdir(path : String) -> Unit raise {
  @fs.create_dir(path)
}

///|
extern "C" fn architecture_c() -> Int = "morphir_host_architecture"

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
  count : Int,
  cwd : Bytes,
  home : Bytes,
  timeout : Int,
) -> Bytes = "morphir_host_process"

///|
pub fn process(
  program : String,
  args : Array[String],
  cwd : String,
  home : String,
  timeout : Int,
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
  fn word(i : Int) -> Int {
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
  length : Int,
  timeout : Int,
  root : Bytes,
) -> Int = "morphir_flush_file"

///|
pub fn flush_file(
  path : String,
  data : Bytes,
  timeout : Int,
  root? : String = "",
) -> Bool {
  flush_file_c(cstring(path), data, data.length(), timeout, cstring(root)) == 0
}

///|
#borrow(path)
extern "C" fn file_open_c(path : Bytes, limit : Int) -> Int = "morphir_host_file_open"

///|
fn file_open(path : String, limit : Int) -> Int {
  file_open_c(cstring(path), limit)
}

///|
#borrow(buffer)
extern "C" fn file_read(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "morphir_host_file_read"

///|
extern "C" fn file_close(fd : Int) -> Int = "morphir_host_file_close"
