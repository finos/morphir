///|
fn read(bytes : Bytes) -> @wasm.WasmModule {
  @wasm.WasmModule::read(bytes) catch {
    error => abort("the module was not read: \{error}")
  }
}

///|
/// The classified profile, or the refusal with the import it names.
fn verdict(bytes : Bytes, declared? : @worker.WasmAbi) -> String {
  read(bytes).classify(declared?).to_string() catch {
    AbiUnsupported(name) => "unsupported \{name}"
    ExportMissing(name~, signature~) => "missing \{name} as \{signature}"
    AbiMismatch(declared~, classified~) =>
      "mismatch: declared \{declared}, classified \{classified}"
    error => "other: \{@debug.to_string(error)}"
  }
}

///|
fn handle_function() -> @fixtures.DefinedFunction {
  @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00")
}

///|
fn extism_import(
  module_name : String,
  name : String,
  params : Array[@fixtures.Type],
  results : Array[@fixtures.Type],
) -> @fixtures.ImportedFunction {
  @fixtures.ImportedFunction::new(module_name, name, params, results)
}

///|
/// A module of the Extism surface, as an Extism PDK builds it: kernel
/// functions, Extism host functions, Morphir host functions and WASI.
fn extism_guest(
  extra~ : Array[@fixtures.ImportedFunction] = [],
  handle~ : Bool = true,
) -> Bytes {
  @fixtures.module_(
    imports=[
      extism_import("extism:host/env", "input_length", [], [I64]),
      extism_import("extism:host/env", "input_load_u8", [I64], [I32]),
      extism_import("extism:host/env", "alloc", [I64], [I64]),
      extism_import("extism:host/env", "output_set", [I64, I64], []),
      extism_import("extism:host/env", "var_get", [I64], [I64]),
      extism_import("extism:host/env", "log_info", [I64], []),
      extism_import("extism:host/env", "http_request", [I64, I64], [I64]),
      extism_import("extism:host/user", "morphir_cache_ir", [I64, I64], []),
      extism_import("extism:host/user", "morphir_log", [I64, I64], []),
      extism_import("extism:host/user", "morphir_get_workspace_info", [], [I64]),
      extism_import(
        "wasi_snapshot_preview1",
        "fd_write",
        [I32, I32, I32, I32],
        [I32],
      ),
      extism_import(
        "wasi_snapshot_preview1",
        "clock_time_get",
        [I32, I64, I32],
        [I32],
      ),
      ..extra,
    ],
    functions=if handle { [handle_function()] } else { [] },
    memory=@fixtures.Memory::new(1),
  )
}

///|
test "the reader lists imports and exports with their types" {
  let wasm = read(@fixtures.echo_guest())
  assert_eq(wasm.imports().map(item => item.name.to_string()), [
    "morphir_bytes_v1.input_len", "morphir_bytes_v1.input_byte", "morphir_bytes_v1.output_byte",
  ])
  guard wasm.imports()[1].kind is Function(input_byte) else {
    fail("input_byte is not a function")
  }
  assert_eq(input_byte.to_string(), "(i32) -> (i32)")
  assert_eq(wasm.exports().map(item => item.name), ["handle", "memory"])
  assert_eq(
    wasm.export_function("handle").map(item => item.to_string()),
    Some("() -> (i32)"),
  )
  guard wasm.memories() is [memory] else { fail("not one memory") }
  assert_eq(memory.minimum, 1L)
  assert_eq(memory.maximum, None)
  assert_false(memory.shared || memory.memory64)
}

///|
test "the reader refuses bytes that are not a WASM module" {
  let refused = (bytes : Bytes) => {
    try @wasm.WasmModule::read(bytes) catch {
      Malformed(..) => true
    } noraise {
      _ => false
    }
  }
  assert_true(refused(b"\x00asm"))
  assert_true(refused(b"\x7fELF\x02\x01\x01\x00"))
  // A section that claims more bytes than the module has.
  assert_true(refused(b"\x00asm\x01\x00\x00\x00\x01\x10\x00"))
  // An import with a type index that does not exist.
  assert_true(refused(b"\x00asm\x01\x00\x00\x00\x02\x07\x01\x01m\x01f\x00\x05"))
}

///|
test "ABI classification: the portable guest's byte callbacks make it morphir-bytes-v1" {
  assert_eq(verdict(@fixtures.echo_guest()), "morphir-bytes-v1")
  assert_eq(
    verdict(@fixtures.echo_guest(), declared=MorphirBytesV1),
    "morphir-bytes-v1",
  )
}

///|
test "Extism import surface: kernel, host, Morphir and WASI imports make it extism-kernel-v1" {
  assert_eq(verdict(extism_guest()), "extism-kernel-v1")
  assert_eq(
    verdict(extism_guest(), declared=ExtismKernelV1),
    "extism-kernel-v1",
  )
  // Every Morphir host function of the SDK is in the surface.
  assert_eq(
    verdict(
      extism_guest(extra=[
        extism_import("extism:host/user", "morphir_get_cached_ir", [I64], [I64]),
      ]),
    ),
    "extism-kernel-v1",
  )
}

///|
test "import from an unknown namespace: env.open_socket is refused by name" {
  let guest = extism_guest(extra=[
    extism_import("env", "open_socket", [I32], [I32]),
  ])
  assert_eq(verdict(guest), "unsupported env.open_socket")
}

///|
test "an import of the surface with another signature is refused by name" {
  let guest = extism_guest(extra=[
    extism_import("extism:host/user", "morphir_log", [I32], []),
  ])
  assert_eq(verdict(guest), "unsupported extism:host/user.morphir_log")
  // A name that is not in a known namespace's surface.
  let guest = extism_guest(extra=[
    extism_import("extism:host/user", "lookup", [I64], [I64]),
  ])
  assert_eq(verdict(guest), "unsupported extism:host/user.lookup")
  let guest = extism_guest(extra=[
    extism_import("wasi_snapshot_preview1", "sock_open", [I32], [I32]),
  ])
  assert_eq(verdict(guest), "unsupported wasi_snapshot_preview1.sock_open")
}

///|
test "a module that mixes both profiles is refused at the first import outside its profile" {
  let guest = @fixtures.module_(
    imports=[
      ..@fixtures.byte_callbacks(),
      extism_import("extism:host/env", "input_length", [], [I64]),
    ],
    functions=[handle_function()],
  )
  assert_eq(verdict(guest), "unsupported extism:host/env.input_length")
}

///|
test "module without handle: kernel imports only and no handle export is refused" {
  assert_eq(verdict(extism_guest(handle=false)), "missing handle as () -> i32")
  // A handle of another type is refused too.
  let guest = @fixtures.module_(imports=@fixtures.byte_callbacks(), functions=[
    @fixtures.DefinedFunction::new(
      export_name="handle",
      params=[I32],
      b"\x41\x00",
    ),
  ])
  assert_eq(verdict(guest), "missing handle as () -> i32")
}

///|
test "declared ABI must agree: morphir-bytes-v1 declared for an Extism module" {
  assert_eq(
    verdict(extism_guest(), declared=MorphirBytesV1),
    "mismatch: declared morphir-bytes-v1, classified extism-kernel-v1",
  )
  assert_eq(
    verdict(@fixtures.echo_guest(), declared=ExtismKernelV1),
    "mismatch: declared extism-kernel-v1, classified morphir-bytes-v1",
  )
}

///|
test "a declaration does not widen the imports: a declared Extism module still may not import env" {
  let guest = @fixtures.module_(
    imports=[extism_import("env", "open_socket", [I32], [I32])],
    functions=[handle_function()],
  )
  assert_eq(
    verdict(guest, declared=ExtismKernelV1),
    "unsupported env.open_socket",
  )
  // A module with no imports takes the declared profile.
  let plain = @fixtures.module_(functions=[handle_function()])
  assert_eq(verdict(plain, declared=MorphirBytesV1), "morphir-bytes-v1")
  assert_eq(verdict(plain), "extism-kernel-v1")
}
