///|
fn fixture_type(value : @engine.ValueType) -> @fixtures.Type {
  match value {
    I32 => I32
    I64 => I64
    _ => abort("the surface has only i32 and i64")
  }
}

///|
fn wasi_fixture_type(value : @wasi.WasiType) -> @fixtures.Type {
  match value {
    I32 => I32
    I64 => I64
  }
}

///|
fn kernel_fixture_type(value : @kernel.KernelType) -> @fixtures.Type {
  match value {
    I32 => I32
    I64 => I64
  }
}

///|
test "Extism import surface: every function that moonrockz/extism links is accepted" {
  let imports = []
  for function in @kernel.KernelFunction::all() {
    imports.push(
      @fixtures.ImportedFunction::new(
        @kernel.import_namespace,
        function.name(),
        function.params().map(kernel_fixture_type),
        function.results().map(kernel_fixture_type),
      ),
    )
  }
  for function in @extism.ExtismFunction::all() {
    let signature = function.signature()
    imports.push(
      @fixtures.ImportedFunction::new(
        @kernel.import_namespace,
        function.name(),
        signature.params.map(fixture_type),
        signature.results.map(fixture_type),
      ),
    )
  }
  for function in @wasi.Function::all() {
    imports.push(
      @fixtures.ImportedFunction::new(
        @wasi.import_namespace,
        function.name(),
        function.params().map(wasi_fixture_type),
        function.results().map(wasi_fixture_type),
      ),
    )
  }
  assert_eq(imports.length(), 20 + 12 + 46)
  let module_ = @fixtures.module_(imports~, functions=[
    @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
  ])
  assert_eq(@wasm.WasmModule::read(module_).classify(), ExtismKernelV1)
}
