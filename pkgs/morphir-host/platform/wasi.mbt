///|
/// WASI Preview 1 ABI. All paths are relative to preopened fd 3.
#unsafe_skip_stub_check
#borrow(bytes)
fn address(bytes : FixedArray[Byte]) -> Int32 = "(func (param i32) (result i32) local.get 0)"

///|
fn sizes(args : Bool, out : FixedArray[Byte], size : FixedArray[Byte]) -> Int32 {
  if args {
    args_sizes(out, size)
  } else {
    env_sizes(out, size)
  }
}

///|
#unsafe_skip_stub_check
#borrow(a, b)
fn args_sizes(a : FixedArray[Byte], b : FixedArray[Byte]) -> Int32 = "wasi_snapshot_preview1" "args_sizes_get"

///|
#unsafe_skip_stub_check
#borrow(a, b)
fn env_sizes(a : FixedArray[Byte], b : FixedArray[Byte]) -> Int32 = "wasi_snapshot_preview1" "environ_sizes_get"

///|
#unsafe_skip_stub_check
#borrow(a, b)
fn args_get(a : FixedArray[Byte], b : FixedArray[Byte]) -> Int32 = "wasi_snapshot_preview1" "args_get"

///|
#unsafe_skip_stub_check
#borrow(a, b)
fn env_get(a : FixedArray[Byte], b : FixedArray[Byte]) -> Int32 = "wasi_snapshot_preview1" "environ_get"

///|
#unsafe_skip_stub_check
#borrow(path, result)
fn open_ffi(
  fd : Int32,
  flags : Int32,
  path : FixedArray[Byte],
  length : Int32,
  oflags : Int32,
  rights : Int64,
  inheriting : Int64,
  fdflags : Int32,
  result : FixedArray[Byte],
) -> Int32 = "wasi_snapshot_preview1" "path_open"

///|
fn close_ffi(fd : Int32) -> Int32 = "wasi_snapshot_preview1" "fd_close"

///|
#unsafe_skip_stub_check
#borrow(vectors, result)
fn read_ffi(
  fd : Int32,
  vectors : FixedArray[Byte],
  count : Int32,
  result : FixedArray[Byte],
) -> Int32 = "wasi_snapshot_preview1" "fd_read"

///|
#unsafe_skip_stub_check
#borrow(vectors, result)
fn write_ffi(
  fd : Int32,
  vectors : FixedArray[Byte],
  count : Int32,
  result : FixedArray[Byte],
) -> Int32 = "wasi_snapshot_preview1" "fd_write"

///|
#unsafe_skip_stub_check
#borrow(path, result)
fn stat_ffi(
  fd : Int32,
  flags : Int32,
  path : FixedArray[Byte],
  length : Int32,
  result : FixedArray[Byte],
) -> Int32 = "wasi_snapshot_preview1" "path_filestat_get"

///|
#unsafe_skip_stub_check
#borrow(path)
fn mkdir_ffi(fd : Int32, path : FixedArray[Byte], length : Int32) -> Int32 = "wasi_snapshot_preview1" "path_create_directory"

///|
#unsafe_skip_stub_check
#borrow(path)
fn unlink_ffi(fd : Int32, path : FixedArray[Byte], length : Int32) -> Int32 = "wasi_snapshot_preview1" "path_unlink_file"

///|
#unsafe_skip_stub_check
#borrow(path)
fn rmdir_ffi(fd : Int32, path : FixedArray[Byte], length : Int32) -> Int32 = "wasi_snapshot_preview1" "path_remove_directory"

///|
#unsafe_skip_stub_check
#borrow(a, b)
fn rename_ffi(
  fd : Int32,
  a : FixedArray[Byte],
  alen : Int32,
  fd2 : Int32,
  b : FixedArray[Byte],
  blen : Int32,
) -> Int32 = "wasi_snapshot_preview1" "path_rename"

///|
#unsafe_skip_stub_check
#borrow(buffer, result)
fn readdir_ffi(
  fd : Int32,
  buffer : FixedArray[Byte],
  length : Int32,
  cookie : Int64,
  result : FixedArray[Byte],
) -> Int32 = "wasi_snapshot_preview1" "fd_readdir"

///|
pub fn exit(code : Int32) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
fn word(b : FixedArray[Byte], i : Int32) -> Int32 {
  b[i].to_int() |
  (b[i + 1].to_int() << 8) |
  (b[i + 2].to_int() << 16) |
  (b[i + 3].to_int() << 24)
}

///|
fn put(b : FixedArray[Byte], i : Int32, value : Int32) -> Unit {
  for n = 0; n < 4; n = n + 1 {
    b[i + n] = ((value >> (n * 8)) & 255).to_byte()
  }
}

///|
fn strings(args : Bool) -> Array[String] raise {
  let count : FixedArray[Byte] = FixedArray::make(4, 0)
  let size : FixedArray[Byte] = FixedArray::make(4, 0)
  check(sizes(args, count, size), "argument sizes")
  let n = word(count, 0)
  let length = word(size, 0)
  if n < 0 || n > 65536 || length < 0 || length > 16777216 {
    raise IOError("Argument/environment limit exceeded")
  }
  let pointers : FixedArray[Byte] = FixedArray::make(n * 4, 0)
  let data : FixedArray[Byte] = FixedArray::make(length, 0)
  check(
    if args {
      args_get(pointers, data)
    } else {
      env_get(pointers, data)
    },
    "arguments",
  )
  let result = []
  for i = 0; i < n; i = i + 1 {
    let start = word(pointers, i * 4) - address(data)
    let mut end = start
    while end < length && data[end] != 0 {
      end = end + 1
    }
    result.push(@utf8.decode(Bytes::from_array(data[:])[start:end]))
  }
  result
}

///|
pub fn args() -> Array[String] {
  strings(true) catch {
    _ => []
  }
}

///|
pub fn environment() -> Map[String, String] {
  let result = Map([])
  let values = strings(false) catch { _ => [] }
  for value in values {
    let parts = value.split("=").map(StringView::to_owned).collect()
    if parts.length() > 1 {
      result[parts[0]] = parts[1:].to_owned().join("=")
    }
  }
  result
}

///|
pub fn cwd() -> String {
  "."
}

///|
fn open(path : String, flags : Int32, rights : Int64) -> Int32 raise {
  let data = encode(path)
  let result : FixedArray[Byte] = FixedArray::make(4, 0)
  check(
    open_ffi(3, 0, data, data.length(), flags, rights, rights, 0, result),
    "open " + path,
  )
  word(result, 0)
}

///|
pub fn kind(path : String) -> Int32 raise {
  let data = encode(path)
  let result : FixedArray[Byte] = FixedArray::make(64, 0)
  let code = stat_ffi(3, 0, data, data.length(), result)
  if code == 44 || code == 54 {
    return 0
  }
  check(code, "stat " + path)
  match result[16].to_int() {
    3 => 2
    4 => 1
    7 => 3
    _ => 4
  }
}

///|
fn vectors(data : FixedArray[Byte], offset : Int32) -> FixedArray[Byte] {
  let result : FixedArray[Byte] = FixedArray::make(8, 0)
  put(result, 0, address(data) + offset)
  put(result, 4, data.length() - offset)
  result
}

///|
pub fn read_bytes(path : String) -> Bytes raise {
  let fd = open(path, 0, 2L)
  defer ignore(close_ffi(fd))
  let buffer : FixedArray[Byte] = FixedArray::make(65536, 0)
  let result : FixedArray[Byte] = FixedArray::make(4, 0)
  let data : Array[Byte] = []
  while true {
    check(read_ffi(fd, vectors(buffer, 0), 1, result), "read " + path)
    let n = word(result, 0)
    if n == 0 {
      break
    }
    if data.length() + n > 16777216 {
      raise IOError("File exceeds 16 MiB: " + path)
    }
    for i = 0; i < n; i = i + 1 {
      data.push(buffer[i])
    }
  }
  Bytes::from_array(data)
}

///|
fn write_fd(fd : Int32, data : FixedArray[Byte]) -> Unit raise {
  let result : FixedArray[Byte] = FixedArray::make(4, 0)
  let mut offset = 0
  while offset < data.length() {
    check(write_ffi(fd, vectors(data, offset), 1, result), "write")
    let n = word(result, 0)
    if n == 0 {
      raise IOError("Write made no progress")
    }
    offset = offset + n
  }
}

///|
pub fn write(path : String, content : String) -> Unit raise {
  let fd = open(path, 9, 64L)
  defer ignore(close_ffi(fd))
  write_fd(fd, encode(content))
}

///|
pub fn mkdir(path : String) -> Unit raise {
  let data = encode(path)
  check(mkdir_ffi(3, data, data.length()), "mkdir " + path)
}

///|
pub fn remove_file(path : String) -> Unit raise {
  let data = encode(path)
  check(unlink_ffi(3, data, data.length()), "unlink " + path)
}

///|
pub fn remove_dir(path : String) -> Unit raise {
  let data = encode(path)
  check(rmdir_ffi(3, data, data.length()), "rmdir " + path)
}

///|
pub fn rename(a : String, b : String) -> Unit raise {
  let first = encode(a)
  let second = encode(b)
  check(
    rename_ffi(3, first, first.length(), 3, second, second.length()),
    "rename",
  )
}

///|
pub fn stderr(text : String) -> Unit {
  write_fd(2, encode(text)) catch {
    _ => ()
  }
}

///|
pub fn list(path : String) -> Array[String] raise {
  let fd = open(path, 2, 16384L)
  defer ignore(close_ffi(fd))
  let buffer : FixedArray[Byte] = FixedArray::make(65536, 0)
  let result : FixedArray[Byte] = FixedArray::make(4, 0)
  let names = []
  let mut cookie = 0L
  while true {
    check(
      readdir_ffi(fd, buffer, buffer.length(), cookie, result),
      "readdir " + path,
    )
    let n = word(result, 0)
    let mut offset = 0
    while offset + 24 <= n {
      let length = word(buffer, offset + 16)
      if offset + 24 + length > n {
        break
      }
      cookie = word(buffer, offset).reinterpret_as_uint().to_int64() |
        (word(buffer, offset + 4).to_int64() << 32)
      let name = @utf8.decode(
        Bytes::from_array(buffer[:])[offset + 24:offset + 24 + length],
      )
      if name != "." && name != ".." {
        names.push(name)
      }
      offset = offset + 24 + length
    }
    if n < buffer.length() {
      break
    }
    if offset == 0 {
      raise IOError("Directory entry exceeds buffer")
    }
  }
  names
}

///|
fn directory_list(path : String, limit : Int32) -> Array[String] raise {
  let fd = open(path, 2, 16384L)
  defer check(close_ffi(fd), "directory.close_failed")
  let buffer : FixedArray[Byte] = FixedArray::make(65536, 0)
  let result : FixedArray[Byte] = FixedArray::make(4, 0)
  let names = []
  let mut units = 0
  let mut cookie = 0L
  while true {
    check(
      readdir_ffi(fd, buffer, buffer.length(), cookie, result),
      "directory.read_failed",
    )
    let n = word(result, 0)
    if n < 0 || n > buffer.length() {
      raise IOError("directory.invalid_response")
    }
    if n == 0 {
      break
    }
    let mut offset = 0
    while n - offset >= 24 {
      let length = word(buffer, offset + 16)
      if length < 0 || length > 16384 {
        raise IOError("directory.name_limit")
      }
      if length > n - offset - 24 {
        break
      }
      cookie = word(buffer, offset).reinterpret_as_uint().to_int64() |
        (word(buffer, offset + 4).to_int64() << 32)
      let dot = (length == 1 && buffer[offset + 24] == 46) ||
        (length == 2 && buffer[offset + 24] == 46 && buffer[offset + 25] == 46)
      if !dot {
        if names.length() >= limit {
          raise IOError("directory.entry_limit")
        }
        let name = @utf8.decode(
          Bytes::from_array(buffer[offset + 24:offset + 24 + length]),
        )
        units = directory_name(name, units)
        names.push(name)
      }
      offset += 24 + length
    }
    if offset == n && n < buffer.length() {
      break
    }
    // Resume from the last complete entry if the host truncated its last entry.
    if offset == 0 {
      raise IOError("directory.invalid_response")
    }
  }
  names
}

///|
fn encode(s : String) -> FixedArray[Byte] {
  @utf8.encode(s[:]).to_fixedarray()
}

///|
pub fn arguments() -> Array[String] {
  let values = args()
  if values.is_empty() {
    []
  } else {
    values[1:].to_owned()
  }
}

///|
pub fn architecture() -> String {
  "wasm"
}

///|
pub fn system_type() -> String {
  "wasi"
}

///|
pub fn process_supported() -> Bool {
  false
}

///|
pub fn temporary() -> String raise {
  raise IOError("Host does not provide temporary directories")
}

///|
pub fn process(
  _program : String,
  _args : Array[String],
  _cwd : String,
  _home : String,
  _timeout : Int32,
) -> Json raise {
  raise IOError("WASI Preview 1 does not provide process execution")
}

///|
pub fn read(path : String) -> String raise {
  @utf8.decode(read_bytes(path)[:])
}

///|
pub fn write_bytes(path : String, content : Bytes) -> Unit raise {
  let fd = open(path, 9, 64L)
  defer ignore(close_ffi(fd))
  write_fd(fd, FixedArray::from_array(content.to_array()))
}

///|
pub fn read_input(path : String, limit : Int32) -> Bytes raise {
  if limit < 1 || limit > 16777216 {
    raise IOError("input.invalid_limit")
  }
  let fd = if path == "-" {
    0
  } else {
    if kind(path) != 1 {
      raise IOError("input.regular_file_required")
    }
    open(path, 0, 2L)
  }
  defer (if fd != 0 { ignore(close_ffi(fd)) })
  let data : Array[Byte] = []
  while true {
    let buffer = FixedArray::make(
      (limit - data.length() + 1).min(65536),
      b'\x00',
    )
    let result = FixedArray::make(4, b'\x00')
    check(read_ffi(fd, vectors(buffer, 0), 1, result), "input.read_failed")
    let count = word(result, 0)
    if count < 0 || count > buffer.length() {
      raise IOError("input.read_failed")
    }
    if count == 0 {
      break
    }
    if data.length() + count > limit {
      raise IOError("input.limit")
    }
    for byte in buffer[:count] {
      data.push(byte)
    }
  }
  Bytes::from_array(data)
}

///|
#unsafe_skip_stub_check
#borrow(result)
fn clock_time_ffi(
  clock : Int32,
  precision : Int64,
  result : FixedArray[Byte],
) -> Int32 = "wasi_snapshot_preview1" "clock_time_get"

///|
pub fn monotonic_seconds() -> Double {
  let result = FixedArray::make(8, b'\x00')
  if clock_time_ffi(1, 1000000L, result) != 0 {
    return 0.0
  }
  let mut nanos = 0UL
  for index = 7; index >= 0; index = index - 1 {
    nanos = (nanos << 8) | result[index].to_int().to_uint64()
  }
  nanos.to_double() / 1000000000.0
}
