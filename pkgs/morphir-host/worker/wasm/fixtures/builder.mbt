///|
/// A value type of a crafted module.
pub(all) enum Type {
  I32
  I64
}

///|
fn Type::code(self : Type) -> Byte {
  match self {
    I32 => b'\x7f'
    I64 => b'\x7e'
  }
}

///|
/// An imported function: its module, its name and its type.
pub struct ImportedFunction {
  module_name : String
  name : String
  params : Array[Type]
  results : Array[Type]
}

///|
pub fn ImportedFunction::new(
  module_name : String,
  name : String,
  params : Array[Type],
  results : Array[Type],
) -> ImportedFunction {
  { module_name, name, params, results, }
}

///|
/// A defined function: the name it is exported as, if any, its type, its
/// locals and its code without the final `end`.
pub struct DefinedFunction {
  export_name : String?
  params : Array[Type]
  results : Array[Type]
  locals : Array[Type]
  code : Bytes
}

///|
pub fn DefinedFunction::new(
  export_name? : String,
  params~ : Array[Type] = [],
  results~ : Array[Type] = [I32],
  locals~ : Array[Type] = [],
  code : Bytes,
) -> DefinedFunction {
  { export_name, params, results, locals, code, }
}

///|
/// A defined memory, in pages.
pub struct Memory {
  minimum : Int32
  maximum : Int32?
  exported : Bool
}

///|
pub fn Memory::new(
  minimum : Int32,
  maximum? : Int32,
  exported~ : Bool = true,
) -> Memory {
  { minimum, maximum, exported, }
}

///|
fn leb(value : Int32) -> Array[Byte] {
  let bytes = []
  let mut rest = value
  while true {
    let byte = rest & 0x7f
    rest = rest >> 7
    if rest == 0 {
      bytes.push(byte.to_byte())
      break
    }
    bytes.push((byte | 0x80).to_byte())
  }
  bytes
}

///|
fn name(text : String) -> Array[Byte] {
  let bytes = @utf8.encode(text).to_array()
  leb(bytes.length())..append(bytes)
}

///|
fn vector(items : Array[Array[Byte]]) -> Array[Byte] {
  let bytes = leb(items.length())
  for item in items {
    bytes.append(item)
  }
  bytes
}

///|
fn section(id : Int32, body : Array[Byte]) -> Array[Byte] {
  [id.to_byte()]..append(leb(body.length()))..append(body)
}

///|
fn function_type(params : Array[Type], results : Array[Type]) -> Array[Byte] {
  [b'\x60']
  ..append(vector(params.map(value => [value.code()])))
  ..append(vector(results.map(value => [value.code()])))
}

///|
/// A core WASM module with one type per function, the imported functions
/// first, then the defined functions, the memory and the exports. Function
/// `i` in code is the `i`th function, imports included.
pub fn module_(
  imports~ : Array[ImportedFunction] = [],
  functions~ : Array[DefinedFunction] = [],
  memory? : Memory,
) -> Bytes {
  let types = imports
    .map(item => function_type(item.params, item.results))
    ..append(functions.map(item => function_type(item.params, item.results)))
  let bytes = [b'\x00', b'a', b's', b'm', b'\x01', b'\x00', b'\x00', b'\x00']
  if !types.is_empty() {
    bytes.append(section(1, vector(types)))
  }
  if !imports.is_empty() {
    bytes.append(
      section(
        2,
        vector(
          imports.mapi((index, item) => {
            name(item.module_name)
            ..append(name(item.name))
            ..push(b'\x00')
            ..append(leb(index))
          }),
        ),
      ),
    )
  }
  if !functions.is_empty() {
    bytes.append(
      section(
        3,
        vector(functions.mapi((index, _) => leb(imports.length() + index))),
      ),
    )
  }
  if memory is Some(memory) {
    let limits = match memory.maximum {
      Some(maximum) =>
        [b'\x01']..append(leb(memory.minimum))..append(leb(maximum))
      None => [b'\x00']..append(leb(memory.minimum))
    }
    bytes.append(section(5, vector([limits])))
  }
  let exports = []
  for index, item in functions {
    if item.export_name is Some(export_name) {
      exports.push(
        name(export_name)..push(b'\x00')..append(leb(imports.length() + index)),
      )
    }
  }
  if memory is Some(memory) && memory.exported {
    exports.push(name("memory")..push(b'\x02')..append(leb(0)))
  }
  if !exports.is_empty() {
    bytes.append(section(7, vector(exports)))
  }
  if !functions.is_empty() {
    bytes.append(
      section(
        10,
        vector(
          functions.map(item => {
            let locals = vector(item.locals.map(slot => [b'\x01', slot.code()]))
            let body = locals..append(item.code.to_array())..push(b'\x0b')
            leb(body.length())..append(body)
          }),
        ),
      ),
    )
  }
  Bytes::from_array(bytes)
}
