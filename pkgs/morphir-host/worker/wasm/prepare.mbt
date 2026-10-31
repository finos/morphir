///|
/// A module that the host may load: its classified ABI profile, and its bytes
/// with the memory maximum capped.
pub struct PreparedModule {
  abi : @worker.WasmAbi
  module_ : WasmModule
}

///|
/// Reads, classifies and caps a module before instantiation, with the
/// refusals of the worker host: `AbiUnsupported`, `ExportMissing` and
/// `AbiMismatch` from the classification, `WasmFeatureUnsupported` for a
/// shared, 64-bit or second memory, `MemoryAboveCeiling` for an initial
/// memory above the ceiling (`extension.memory_limit`, before any
/// instantiation) and `LaunchFailed` for bytes that are not a WASM module.
pub fn PreparedModule::prepare(
  bytes : Bytes,
  declared? : @worker.WasmAbi,
  ceiling~ : MemoryCeiling = MemoryCeiling::restricted(),
) -> PreparedModule raise @worker.LaunchError {
  let module_ = WasmModule::read(bytes) catch {
    error => raise LaunchFailed("the module is not valid WASM: \{error}")
  }
  let abi = module_.classify(declared?)
  let capped = module_.with_memory_ceiling(ceiling) catch {
    MemoryFeature(feature) =>
      raise WasmFeatureUnsupported(feature=Some(feature))
    InitialAboveCeiling(initial~, ceiling~) =>
      raise MemoryAboveCeiling(initial~, ceiling~)
  }
  { abi, module_: capped, }
}
