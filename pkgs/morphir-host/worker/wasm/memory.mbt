///|
/// The size of a WASM page.
pub const PAGE_BYTES : Int32 = 65536

///|
/// The largest guest memory, in 64 KiB pages.
pub struct MemoryCeiling {
  priv pages : Int32
} derive(Eq, Debug)

///|
pub extend MemoryCeiling with Eq::{equal, not_equal}

///|
pub extend MemoryCeiling with @debug.Debug::{to_repr}

///|
/// A ceiling of `pages` pages: from 1 to 65,536, the most that a 32-bit
/// memory has.
pub fn MemoryCeiling::of_pages(
  pages : Int32,
) -> MemoryCeiling raise ModuleError {
  guard pages >= 1 && pages <= 65536 else {
    raise Malformed(offset=0, reason="a memory ceiling of \{pages} pages")
  }
  { pages, }
}

///|
/// The ceiling of the restricted Extism profile: 256 MiB, 4,096 pages. Both
/// ABI profiles have it.
pub fn MemoryCeiling::restricted() -> MemoryCeiling {
  { pages: @worker.ExtismProfile::restricted().memory_bytes / PAGE_BYTES, }
}

///|
pub fn MemoryCeiling::pages(self : MemoryCeiling) -> Int32 {
  self.pages
}

///|
/// Why the host cannot cap a module's memory.
pub(all) suberror MemoryRefusal {
  /// The module needs a WASM feature for its memory: `threads` for a shared
  /// memory, `memory64` for a 64-bit one, `multi-memory` for more than one.
  MemoryFeature(String)
  /// The module's initial memory is already above the ceiling.
  InitialAboveCeiling(initial~ : Int64, ceiling~ : Int32)
} derive(Eq, Debug)

///|
pub extend MemoryRefusal with Eq::{equal, not_equal}

///|
pub extend MemoryRefusal with @debug.Debug::{to_repr}

///|
fn unsigned_leb(value : Int64) -> Array[Byte] {
  let bytes = []
  let mut rest = value
  while true {
    let byte = (rest & 0x7fL).to_int()
    rest = rest >> 7
    if rest == 0L {
      bytes.push(byte.to_byte())
      break
    }
    bytes.push((byte | 0x80).to_byte())
  }
  bytes
}

///|
/// The module with each defined memory's maximum set to at most `ceiling`
/// pages, as `embedding/wasm-memory.mts` did. A memory without a maximum
/// gets the ceiling; a larger maximum becomes the ceiling; a smaller one is
/// kept. The engine then cannot grant a growth beyond the ceiling. A module
/// without a defined memory, or with a memory section of no memories, is
/// returned as it is.
pub fn WasmModule::with_memory_ceiling(
  self : WasmModule,
  ceiling : MemoryCeiling,
) -> WasmModule raise MemoryRefusal {
  guard self.memory_section is Some((start, end)) && self.memories.length() > 0 else {
    return self
  }
  guard self.memories.length() == 1 else { raise MemoryFeature("multi-memory") }
  let memory = self.memories[0].memory
  if memory.shared {
    raise MemoryFeature("threads")
  }
  if memory.memory64 {
    raise MemoryFeature("memory64")
  }
  let limit = ceiling.pages.to_int64()
  if memory.minimum > limit {
    raise InitialAboveCeiling(initial=memory.minimum, ceiling=ceiling.pages)
  }
  let maximum = match memory.maximum {
    Some(declared) if declared < limit => declared
    _ => limit
  }
  let body = [b'\x01', b'\x01']
    ..append(unsigned_leb(memory.minimum))
    ..append(unsigned_leb(maximum))
  let section = [b'\x05']
    ..append(unsigned_leb(body.length().to_int64()))
    ..append(body)
  let rewritten = Bytes::from_array(
    self.bytes[:start]
    .to_array()
    ..append(section)
    ..append(self.bytes[end:].to_array()),
  )
  {
    ..self,
    bytes: rewritten,
    memories: [{ memory: { ..memory, maximum: Some(maximum), }, }],
    memory_section: Some((start, start + section.length())),
  }
}
