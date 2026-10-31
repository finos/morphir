///|
/// The import module of the `morphir-bytes-v1` byte callbacks.
pub let bytes_namespace : String = "morphir_bytes_v1"

///|
/// The import module of the Extism host functions that an embedder registers.
/// The Morphir host functions are there.
pub let extism_user_namespace : String = "extism:host/user"

///|
/// The function that every guest of both profiles exports.
pub let handle_export : String = "handle"

///|
fn signature(
  params : Array[ValueType],
  results : Array[ValueType],
) -> FunctionType {
  { params, results, }
}

///|
/// The type of the `handle` export in both profiles.
fn handle_type() -> FunctionType {
  signature([], [I32])
}

///|
/// The three byte callbacks of `morphir-bytes-v1`.
fn bytes_import(name : String) -> FunctionType? {
  match name {
    "input_len" => Some(signature([], [I32]))
    "input_byte" => Some(signature([I32], [I32]))
    "output_byte" => Some(signature([I32], []))
    _ => None
  }
}

///|
/// The Extism host functions of `extism:host/env` that are not kernel
/// functions, as upstream Extism hosts link them (WASM-4).
fn extism_env_import(name : String) -> FunctionType? {
  match name {
    "config_get" | "var_get" => Some(signature([I64], [I64]))
    "var_set" => Some(signature([I64, I64], []))
    "log_trace" | "log_debug" | "log_info" | "log_warn" | "log_error" =>
      Some(signature([I64], []))
    "get_log_level" | "http_status_code" => Some(signature([], [I32]))
    "http_request" => Some(signature([I64, I64], [I64]))
    "http_headers" => Some(signature([], [I64]))
    _ => None
  }
}

///|
/// The Morphir host functions in `extism:host/user`, with the signatures of
/// `morphir-extension-sdk`.
fn morphir_user_import(name : String) -> FunctionType? {
  match name {
    "morphir_get_workspace_info" => Some(signature([], [I64]))
    "morphir_cache_ir" | "morphir_log" => Some(signature([I64, I64], []))
    "morphir_get_cached_ir" => Some(signature([I64], [I64]))
    _ => None
  }
}

///|
fn kernel_type(value : @kernel.KernelType) -> ValueType {
  match value {
    I32 => I32
    I64 => I64
  }
}

///|
fn wasi_type(value : @wasi.WasiType) -> ValueType {
  match value {
    I32 => I32
    I64 => I64
  }
}

///|
/// The type that a profile gives an import, or `None` when the import is
/// outside the profile's import surface.
fn surface(abi : @worker.WasmAbi, name : @worker.ImportName) -> FunctionType? {
  match abi {
    MorphirBytesV1 =>
      if name.module_name == bytes_namespace {
        bytes_import(name.name)
      } else {
        None
      }
    ExtismKernelV1 =>
      if name.module_name == @kernel.import_namespace {
        match @kernel.KernelFunction::from_name(name.name) {
          Some(function) =>
            Some(
              signature(
                function.params().map(kernel_type),
                function.results().map(kernel_type),
              ),
            )
          None => extism_env_import(name.name)
        }
      } else if name.module_name == extism_user_namespace {
        morphir_user_import(name.name)
      } else if name.module_name == @wasi.import_namespace {
        @wasi.Function::from_name(name.name).map(function => {
          signature(
            function.params().map(wasi_type),
            function.results().map(wasi_type),
          )
        })
      } else {
        None
      }
  }
}

///|
/// The profile that a module's imports name: `morphir-bytes-v1` when it
/// imports from `morphir_bytes_v1`, `extism-kernel-v1` when it imports from
/// an Extism or WASI module. A module with neither has no profile of its own.
fn WasmModule::named_profile(self : WasmModule) -> @worker.WasmAbi? {
  for import_ in self.imports {
    let module_name = import_.name.module_name
    if module_name == bytes_namespace {
      return Some(MorphirBytesV1)
    }
    if module_name == @kernel.import_namespace ||
      module_name == extism_user_namespace ||
      module_name == @wasi.import_namespace {
      return Some(ExtismKernelV1)
    }
  }
  None
}

///|
/// Classifies the module as exactly one ABI profile, before instantiation
/// (WASM-1). The imports choose the profile: an import from
/// `morphir_bytes_v1` makes it `morphir-bytes-v1`, and an import from
/// `extism:host/env`, `extism:host/user` or `wasi_snapshot_preview1` makes
/// it `extism-kernel-v1`. A module that imports from neither takes the
/// declared profile, or `extism-kernel-v1`.
///
/// Every import must then be a function of the profile's import surface with
/// the surface's type; the first that is not raises `AbiUnsupported` with
/// its name. The module must export `handle` as `() -> i32`, or the
/// classification raises `ExportMissing` with that name and type. A
/// declared profile must equal the classified one, or `AbiMismatch`: a
/// declaration never widens the imports that a module may have.
pub fn WasmModule::classify(
  self : WasmModule,
  declared? : @worker.WasmAbi,
) -> @worker.WasmAbi raise @worker.LaunchError {
  let abi = match (self.named_profile(), declared) {
    (Some(named), _) => named
    (None, Some(declared)) => declared
    (None, None) => ExtismKernelV1
  }
  for import_ in self.imports {
    guard import_.kind is Function(found) &&
      surface(abi, import_.name) is Some(expected) &&
      found == expected else {
      raise AbiUnsupported(import_.name)
    }
  }
  guard self.export_function(handle_export) is Some(found) &&
    found == handle_type() else {
    raise ExportMissing(name=handle_export, signature="() -> i32")
  }
  if declared is Some(declared) && declared != abi {
    raise AbiMismatch(declared~, classified=abi)
  }
  abi
}
