///|
/// The kernel functions that the crafted Extism guests import, as functions
/// 0 to 6. A guest's own imports follow, from function 7.
pub fn kernel_imports() -> Array[ImportedFunction] {
  let env = "extism:host/env"
  [
    ImportedFunction::new(env, "input_length", [], [I64]),
    ImportedFunction::new(env, "input_load_u8", [I64], [I32]),
    ImportedFunction::new(env, "alloc", [I64], [I64]),
    ImportedFunction::new(env, "store_u8", [I64, I32], []),
    ImportedFunction::new(env, "output_set", [I64, I64], []),
    ImportedFunction::new(env, "length", [I64], [I64]),
    ImportedFunction::new(env, "error_set", [I64], []),
  ]
}

///|
/// The function index of the first import after the kernel functions.
pub let first_extra_import : Int32 = 7

///|
fn i64_const(value : Int32) -> Array[Byte] {
  [b'\x42', ..sleb(value)]
}

///|
fn i32_const(value : Int32) -> Array[Byte] {
  [b'\x41', ..sleb(value)]
}

///|
fn call(index : Int32) -> Array[Byte] {
  [b'\x10', ..sleb(index)]
}

///|
fn local_get(index : Int32) -> Array[Byte] {
  [b'\x20', ..sleb(index)]
}

///|
fn local_set(index : Int32) -> Array[Byte] {
  [b'\x21', ..sleb(index)]
}

///|
/// Code that allocates a kernel block with `text` and keeps its handle in
/// slot `slot`.
pub fn kernel_text(text : Bytes, slot : Int32) -> Array[Byte] {
  let code = i64_const(text.length())..append(call(2))..append(local_set(slot))
  for index, byte in text {
    code
    ..append(local_get(slot))
    ..append(i64_const(index))
    ..push(b'\x7c') // i64.add
    ..append(i32_const(byte.to_int()))
    .append(call(3))
  }
  code
}

///|
/// Code that sets the output to the kernel block in slot `slot`.
pub fn output_block(slot : Int32) -> Array[Byte] {
  local_get(slot)..append(local_get(slot))..append(call(5))..append(call(4))
}

///|
/// An Extism guest with the kernel imports, `extra` imports and a `handle`
/// that runs `code` and returns 0. It has five `i64` locals and one page of
/// memory, which it exports.
pub fn extism_guest(
  code : Array[Byte],
  extra~ : Array[ImportedFunction] = [],
  result~ : Int32 = 0,
) -> Bytes {
  module_(
    imports=kernel_imports()..append(extra),
    functions=[
      DefinedFunction::new(
        export_name="handle",
        locals=[I64, I64, I64, I64, I64],
        Bytes::from_array(code..append(i32_const(result))),
      ),
    ],
    memory=Memory::new(1),
  )
}

///|
/// An Extism guest that answers each request with the request.
pub fn extism_echo_guest() -> Bytes {
  let code : Array[Byte] = [
    ..call(0),
    ..local_set(0), // len = input_length()
    ..local_get(0),
    ..call(2),
    ..local_set(1), // off = alloc(len)
    b'\x02',
    b'\x40',
    b'\x03',
    b'\x40', // block loop
    ..local_get(2),
    ..local_get(0),
    b'\x5a',
    b'\x0d',
    b'\x01', // i >= len: break
    ..local_get(1),
    ..local_get(2),
    b'\x7c', // off + i
    ..local_get(2),
    ..call(1), // input_load_u8(i)
    ..call(3), // store_u8
    ..local_get(2),
    ..i64_const(1),
    b'\x7c',
    ..local_set(2), // i += 1
    b'\x0c',
    b'\x00',
    b'\x0b',
    b'\x0b', // continue; end end
    ..local_get(1),
    ..local_get(0),
    ..call(4), // output_set(off, len)
  ]
  extism_guest(code)
}

///|
/// An Extism guest that writes `text` as its output and returns `result`.
pub fn extism_text_guest(text : Bytes, result~ : Int32 = 0) -> Bytes {
  extism_guest(kernel_text(text, 0)..append(output_block(0)), result~)
}

///|
/// An Extism guest whose `handle` traps.
pub fn extism_trapping_guest() -> Bytes {
  extism_guest([b'\x00'])
}

///|
/// An Extism guest whose `handle` loops forever.
pub fn extism_runaway_guest() -> Bytes {
  extism_guest([b'\x03', b'\x40', b'\x0c', b'\x00', b'\x0b'])
}

///|
/// An Extism guest that sets an error and returns 1.
pub fn extism_error_guest() -> Bytes {
  extism_guest(
    kernel_text(b"no parser", 0)..append(local_get(0))..append(call(6)),
    result=1,
  )
}

///|
/// An Extism guest that, on each call, answers with the IR cached under
/// key `k` (`null` when none is), then caches the request under `k`.
pub fn extism_cache_guest() -> Bytes {
  let user = "extism:host/user"
  let cache = first_extra_import
  let cached = first_extra_import + 1
  let code = kernel_text(b"k", 0)
    ..append(local_get(0))
    ..append(call(cached))
    ..append(local_set(1))
    ..append(output_block(1))
    // Copy the request into a block, then cache it.
    ..append(call(0))
    ..append(local_set(2))
    ..append(local_get(2))
    ..append(call(2))
    ..append(local_set(3))
    ..append([b'\x42', b'\x00'])
    ..append(local_set(4))
    ..append([b'\x02', b'\x40', b'\x03', b'\x40'])
    ..append(local_get(4))
    ..append(local_get(2))
    ..append([b'\x5a', b'\x0d', b'\x01'])
    ..append(local_get(3))
    ..append(local_get(4))
    ..push(b'\x7c')
    ..append(local_get(4))
    ..append(call(1))
    ..append(call(3))
    ..append(local_get(4))
    ..append(i64_const(1))
    ..push(b'\x7c')
    ..append(local_set(4))
    ..append([b'\x0c', b'\x00', b'\x0b', b'\x0b'])
    ..append(local_get(0))
    ..append(local_get(3))
    ..append(call(cache))
  extism_guest(code, extra=[
    ImportedFunction::new(user, "morphir_cache_ir", [I64, I64], []),
    ImportedFunction::new(user, "morphir_get_cached_ir", [I64], [I64]),
  ])
}

///|
/// An Extism guest that logs through `morphir_log` and `log_info`, then
/// answers with the workspace information.
pub fn extism_workspace_guest() -> Bytes {
  let log = first_extra_import
  let log_info = first_extra_import + 1
  let workspace = first_extra_import + 2
  let code = kernel_text(b"info", 0)
    ..append(kernel_text(b"guest says hello", 1))
    ..append(local_get(0))
    ..append(local_get(1))
    ..append(call(log))
    ..append(kernel_text(b"extism log line", 2))
    ..append(local_get(2))
    ..append(call(log_info))
    ..append(call(workspace))
    ..append(local_set(3))
    ..append(output_block(3))
  extism_guest(code, extra=[
    ImportedFunction::new("extism:host/user", "morphir_log", [I64, I64], []),
    ImportedFunction::new("extism:host/env", "log_info", [I64], []),
    ImportedFunction::new(
      "extism:host/user",
      "morphir_get_workspace_info",
      [],
      [I64],
    ),
  ])
}

///|
/// An Extism guest that asks for an HTTP request, then answers `sent`.
pub fn extism_http_guest() -> Bytes {
  let http = first_extra_import
  let code = kernel_text(
      b"{\"url\":\"https://example.com/\",\"method\":\"GET\",\"headers\":{}}", 0,
    )
    ..append(local_get(0))
    ..append(i64_const(0))
    ..append(call(http))
    ..push(b'\x1a') // drop
    ..append(kernel_text(b"sent", 1))
    ..append(output_block(1))
  extism_guest(code, extra=[
    ImportedFunction::new("extism:host/env", "http_request", [I64, I64], [I64]),
  ])
}

///|
/// An Extism guest that prints `hello` to stdout through WASI `fd_write`
/// and tries to open the file `hello` with `path_open`, then answers with the
/// errno of `path_open` as one byte.
pub fn extism_wasi_guest() -> Bytes {
  let fd_write = first_extra_import
  let path_open = first_extra_import + 1
  let store = (address : Int32, value : Int32) => {
    i32_const(address)
    ..append(i32_const(value))
    ..append([b'\x36', b'\x02', b'\x00'])
  }
  let code : Array[Byte] = []
  // The text at 16, the iovec at 0: { buf: 16, len: 5 }.
  for index, byte in b"hello" {
    code
    ..append(i32_const(16 + index))
    ..append(i32_const(byte.to_int()))
    .append([b'\x3a', b'\x00', b'\x00']) // i32.store8
  }
  code
  ..append(store(0, 16))
  ..append(store(4, 5))
  ..append(i32_const(1))
  ..append(i32_const(0))
  ..append(i32_const(1))
  ..append(i32_const(32))
  ..append(call(fd_write))
  ..push(b'\x1a')
  // path_open(3, 0, 16, 5, 0, 0, 0, 0, 40): the path "hello".
  ..append(i32_const(3))
  ..append(i32_const(0))
  ..append(i32_const(16))
  ..append(i32_const(5))
  ..append(i32_const(0))
  ..append([b'\x42', b'\x00', b'\x42', b'\x00'])
  ..append(i32_const(0))
  ..append(i32_const(40))
  ..append(call(path_open))
  ..push(b'\xad') // i64.extend_i32_u
  ..append(local_set(4))
  // Answer with the errno as one byte.
  ..append(i64_const(1))
  ..append(call(2))
  ..append(local_set(1))
  ..append(local_get(1))
  ..append(local_get(4))
  ..push(b'\xa7') // i32.wrap_i64
  ..append(call(3))
  .append(output_block(1))
  extism_guest(code, extra=[
    ImportedFunction::new(
      "wasi_snapshot_preview1",
      "fd_write",
      [I32, I32, I32, I32],
      [I32],
    ),
    ImportedFunction::new(
      "wasi_snapshot_preview1",
      "path_open",
      [I32, I32, I32, I32, I32, I64, I64, I32, I32],
      [I32],
    ),
  ])
}

///|
/// An Extism guest that answers with the level that `get_log_level` gives,
/// as one ASCII digit: 0 for trace to 4 for error.
pub fn extism_log_level_guest() -> Bytes {
  let get_log_level = first_extra_import
  let code = i64_const(1)
    ..append(call(2))
    ..append(local_set(0))
    ..append(local_get(0))
    ..append(call(get_log_level))
    ..append(i32_const(48))
    ..push(b'\x6a') // i32.add
    ..append(call(3))
    ..append(output_block(0))
  extism_guest(code, extra=[
    ImportedFunction::new("extism:host/env", "get_log_level", [], [I32]),
  ])
}

///|
/// How the call of `extism_logging_guest` ends after its logging.
pub(all) enum LoggingEnd {
  /// The call traps.
  Trap
  /// The call loops until its budget or its deadline ends it.
  Spin
}

///|
/// An Extism guest that logs `blocks` messages of 64 KiB with `log_info` on
/// each call, then ends as `ending` says.
pub fn extism_logging_guest(blocks : Int32, ending : LoggingEnd) -> Bytes {
  let log_info = first_extra_import
  let code = i64_const(65536)
    ..append(call(2))
    ..append(local_set(0))
    ..append(i64_const(0))
    ..append(local_set(1))
    ..append([b'\x02', b'\x40', b'\x03', b'\x40']) // block, loop
    ..append(local_get(1))
    ..append(i64_const(blocks))
    ..append([b'\x59', b'\x0d', b'\x01']) // i64.ge_s, br_if 1
    ..append(local_get(0))
    ..append(call(log_info))
    ..append(local_get(1))
    ..append(i64_const(1))
    ..push(b'\x7c') // i64.add
    ..append(local_set(1))
    ..append([b'\x0c', b'\x00', b'\x0b', b'\x0b']) // br 0, end, end
  match ending {
    Trap => code.push(b'\x00')
    Spin => code.append([b'\x03', b'\x40', b'\x0c', b'\x00', b'\x0b'])
  }
  extism_guest(code, extra=[
    ImportedFunction::new("extism:host/env", "log_info", [I64], []),
  ])
}
