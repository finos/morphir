///|
/// A WASM module that the reader could not read: the byte offset and what is
/// wrong there.
pub(all) suberror ModuleError {
  Malformed(offset~ : Int32, reason~ : String)
} derive(Eq, Debug)

///|
pub extend ModuleError with Eq::{equal, not_equal}

///|
pub extend ModuleError with @debug.Debug::{to_repr}

///|
pub impl Show for ModuleError with fn output(self, logger) {
  match self {
    Malformed(offset~, reason~) =>
      logger.write_string("byte \{offset}: \{reason}")
  }
}

///|
pub extend ModuleError with Show::{to_string, output}

///|
/// A WASM value type.
pub(all) enum ValueType {
  I32
  I64
  F32
  F64
  V128
  FuncRef
  ExternRef
  /// A reference or other type that core WASM 2.0 does not have, by its
  /// type byte.
  Other(Int32)
} derive(Eq, Debug)

///|
pub extend ValueType with Eq::{equal, not_equal}

///|
pub extend ValueType with @debug.Debug::{to_repr}

///|
pub impl Show for ValueType with fn output(self, logger) {
  logger.write_string(
    match self {
      I32 => "i32"
      I64 => "i64"
      F32 => "f32"
      F64 => "f64"
      V128 => "v128"
      FuncRef => "funcref"
      ExternRef => "externref"
      Other(code) => "type 0x\{code.to_byte().to_hex()}"
    },
  )
}

///|
pub extend ValueType with Show::{to_string, output}

///|
/// The parameter and result types of a function.
pub struct FunctionType {
  params : Array[ValueType]
  results : Array[ValueType]
} derive(Eq, Debug)

///|
pub extend FunctionType with Eq::{equal, not_equal}

///|
pub extend FunctionType with @debug.Debug::{to_repr}

///|
pub fn FunctionType::new(
  params : ArrayView[ValueType],
  results : ArrayView[ValueType],
) -> FunctionType {
  { params: params.to_owned(), results: results.to_owned(), }
}

///|
pub impl Show for FunctionType with fn output(self, logger) {
  let list = (types : Array[ValueType]) => {
    "(" + types.map(value => value.to_string()).join(", ") + ")"
  }
  logger.write_string(list(self.params))
  logger.write_string(" -> ")
  logger.write_string(list(self.results))
}

///|
pub extend FunctionType with Show::{to_string, output}

///|
/// The limits of a memory, in 64 KiB pages.
pub struct MemoryType {
  minimum : Int64
  maximum : Int64?
  shared : Bool
  memory64 : Bool
} derive(Eq, Debug)

///|
pub extend MemoryType with Eq::{equal, not_equal}

///|
pub extend MemoryType with @debug.Debug::{to_repr}

///|
/// What an import or an export is.
pub(all) enum ExternKind {
  Function(FunctionType)
  Table
  Memory(MemoryType)
  Global
  Tag
} derive(Eq, Debug)

///|
pub extend ExternKind with Eq::{equal, not_equal}

///|
pub extend ExternKind with @debug.Debug::{to_repr}

///|
/// One import of a module: its module and field names, and its kind.
pub struct Import {
  name : @worker.ImportName
  kind : ExternKind
} derive(Eq, Debug)

///|
pub extend Import with Eq::{equal, not_equal}

///|
pub extend Import with @debug.Debug::{to_repr}

///|
/// One export of a module: its name and its kind. A function export has the
/// type of the function it exports.
pub struct Export {
  name : String
  kind : ExternKind
} derive(Eq, Debug)

///|
pub extend Export with Eq::{equal, not_equal}

///|
pub extend Export with @debug.Debug::{to_repr}

///|
/// A memory that the module defines, with the byte span of the memory section
/// that holds it.
priv struct DefinedMemory {
  memory : MemoryType
}

///|
/// The parts of a WASM module that the host checks before instantiation: its
/// imports, its exports and its defined memories. The module keeps its bytes,
/// so the host can rewrite the memory maximum.
pub struct WasmModule {
  priv bytes : Bytes
  priv imports : Array[Import]
  priv exports : Array[Export]
  priv memories : Array[DefinedMemory]
  /// The byte span of the memory section, if the module has one.
  priv memory_section : (Int32, Int32)?
}

///|
pub fn WasmModule::imports(self : WasmModule) -> Array[Import] {
  self.imports.copy()
}

///|
pub fn WasmModule::exports(self : WasmModule) -> Array[Export] {
  self.exports.copy()
}

///|
/// The memories that the module defines, not those that it imports.
pub fn WasmModule::memories(self : WasmModule) -> Array[MemoryType] {
  self.memories.map(defined => defined.memory)
}

///|
pub fn WasmModule::bytes(self : WasmModule) -> Bytes {
  self.bytes
}

///|
/// The function that the module exports as `name`, with its type.
pub fn WasmModule::export_function(
  self : WasmModule,
  name : String,
) -> FunctionType? {
  for item in self.exports {
    if item.name == name && item.kind is Function(function) {
      return Some(function)
    }
  }
  None
}

///|
/// A cursor over the bytes of a module.
priv struct Cursor {
  bytes : Bytes
  mut at : Int32
  end : Int32
}

///|
fn Cursor::fail(self : Cursor, reason : String) -> ModuleError {
  Malformed(offset=self.at, reason~)
}

///|
fn Cursor::byte(self : Cursor) -> Int32 raise ModuleError {
  guard self.at < self.end else { raise self.fail("unexpected end") }
  let value = self.bytes[self.at].to_int()
  self.at += 1
  value
}

///|
/// An unsigned LEB128 integer of at most `bits` bits.
fn Cursor::unsigned(
  self : Cursor,
  bits~ : Int32 = 32,
) -> Int64 raise ModuleError {
  let mut value = 0L
  let mut shift = 0
  while true {
    let start = self.at
    let byte = self.byte()
    guard shift < bits else {
      raise Malformed(offset=start, reason="integer too long")
    }
    let payload = (byte & 0x7f).to_int64()
    // The last byte may not set bits above the integer's width.
    if bits - shift < 7 && payload >> (bits - shift) != 0L {
      raise Malformed(offset=start, reason="integer too large")
    }
    value = value | (payload << shift)
    if (byte & 0x80) == 0 {
      return value
    }
    shift += 7
  }
  value
}

///|
fn Cursor::u32(self : Cursor) -> Int32 raise ModuleError {
  let start = self.at
  let value = self.unsigned()
  guard value <= 0x7fffffffL else {
    raise Malformed(offset=start, reason="count or size too large")
  }
  value.to_int()
}

///|
fn Cursor::name(self : Cursor) -> String raise ModuleError {
  let length = self.u32()
  guard length <= self.end - self.at else {
    raise self.fail("name runs past its section")
  }
  let start = self.at
  self.at += length
  @utf8.decode(self.bytes[start:start + length]) catch {
    _ => raise Malformed(offset=start, reason="name is not valid UTF-8")
  }
}

///|
fn Cursor::value_type(self : Cursor) -> ValueType raise ModuleError {
  match self.byte() {
    0x7f => I32
    0x7e => I64
    0x7d => F32
    0x7c => F64
    0x7b => V128
    0x70 => FuncRef
    0x6f => ExternRef
    code => Other(code)
  }
}

///|
fn Cursor::value_types(self : Cursor) -> Array[ValueType] raise ModuleError {
  let count = self.u32()
  let types = []
  for _ in 0..<count {
    types.push(self.value_type())
  }
  types
}

///|
fn Cursor::limits(self : Cursor) -> MemoryType raise ModuleError {
  let start = self.at
  let flags = self.byte()
  guard (flags & 0xf8) == 0 else {
    raise Malformed(offset=start, reason="unknown memory limit flags")
  }
  let memory64 = (flags & 4) != 0
  let bits = if memory64 { 64 } else { 32 }
  let minimum = self.unsigned(bits~)
  let maximum = if (flags & 1) != 0 { Some(self.unsigned(bits~)) } else { None }
  { minimum, maximum, shared: (flags & 2) != 0, memory64, }
}

///|
fn Cursor::table(self : Cursor) -> Unit raise ModuleError {
  ignore(self.value_type())
  let flags = self.byte()
  ignore(self.unsigned(bits=64))
  if (flags & 1) != 0 {
    ignore(self.unsigned(bits=64))
  }
}

///|
fn Cursor::global(self : Cursor) -> Unit raise ModuleError {
  ignore(self.value_type())
  ignore(self.byte())
}

///|
fn function_type(
  types : Array[FunctionType],
  index : Int32,
  at : Int32,
) -> FunctionType raise ModuleError {
  guard index >= 0 && index < types.length() else {
    raise Malformed(offset=at, reason="type index \{index} out of range")
  }
  types[index]
}

///|
/// Reads the type, import, function, memory and export sections of a core
/// WASM module, version 1. It checks the section framing and the entries it
/// reads; the engine validates the rest when it compiles the module.
pub fn WasmModule::read(bytes : Bytes) -> WasmModule raise ModuleError {
  let header = b"\x00asm\x01\x00\x00\x00"
  guard bytes.length() >= 8 && bytes[0:8] == header[:] else {
    raise Malformed(offset=0, reason="not a core WASM module, version 1")
  }
  let cursor = { bytes, at: 8, end: bytes.length(), }
  let types : Array[FunctionType] = []
  let imports : Array[Import] = []
  // The type index of each function, imported functions first.
  let functions : Array[Int32] = []
  let memories : Array[DefinedMemory] = []
  let exports : Array[(String, Int32, Int32, Int32)] = []
  let mut memory_section = None
  while cursor.at < cursor.end {
    let section_start = cursor.at
    let id = cursor.byte()
    let size = cursor.u32()
    guard size <= cursor.end - cursor.at else {
      raise Malformed(offset=section_start, reason="section runs past the end")
    }
    let body = { bytes, at: cursor.at, end: cursor.at + size, }
    cursor.at += size
    match id {
      1 => {
        let count = body.u32()
        for _ in 0..<count {
          let at = body.at
          guard body.byte() == 0x60 else {
            raise Malformed(offset=at, reason="type is not a function type")
          }
          let params = body.value_types()
          let results = body.value_types()
          types.push({ params, results, })
        }
      }
      2 => {
        let count = body.u32()
        for _ in 0..<count {
          let module_name = body.name()
          let name = body.name()
          let at = body.at
          let kind : ExternKind = match body.byte() {
            0 => {
              let index = body.u32()
              functions.push(index)
              Function(function_type(types, index, at))
            }
            1 => {
              body.table()
              Table
            }
            2 => Memory(body.limits())
            3 => {
              body.global()
              Global
            }
            4 => {
              ignore(body.byte())
              ignore(body.u32())
              Tag
            }
            _ => raise Malformed(offset=at, reason="unknown import kind")
          }
          imports.push({
            name: @worker.ImportName::new(module_name, name),
            kind,
          })
        }
      }
      3 => {
        let count = body.u32()
        for _ in 0..<count {
          functions.push(body.u32())
        }
      }
      5 => {
        memory_section = Some((section_start, cursor.at))
        let count = body.u32()
        for _ in 0..<count {
          memories.push({ memory: body.limits(), })
        }
      }
      7 => {
        let count = body.u32()
        for _ in 0..<count {
          let name = body.name()
          let at = body.at
          let kind = body.byte()
          let index = body.u32()
          exports.push((name, kind, index, at))
        }
      }
      _ => continue
    }
    guard body.at == body.end else {
      raise Malformed(offset=body.at, reason="section \{id} has trailing bytes")
    }
  }
  let memory_types = imports.filter_map(import_ => {
    match import_.kind {
      Memory(memory) => Some(memory)
      _ => None
    }
  })
  memory_types.append(memories.map(defined => defined.memory))
  {
    bytes,
    imports,
    exports: exports.map(entry => {
      let (name, kind, index, at) = entry
      let kind : ExternKind = match kind {
        0 => {
          guard index < functions.length() else {
            raise Malformed(offset=at, reason="function index out of range")
          }
          Function(function_type(types, functions[index], at))
        }
        1 => Table
        2 => {
          guard index < memory_types.length() else {
            raise Malformed(offset=at, reason="memory index out of range")
          }
          Memory(memory_types[index])
        }
        3 => Global
        4 => Tag
        _ => raise Malformed(offset=at, reason="unknown export kind")
      }
      { name, kind, }
    }),
    memories,
    memory_section,
  }
}
