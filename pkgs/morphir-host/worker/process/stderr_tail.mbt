///|
/// The number of stderr bytes that a worker report keeps.
const STDERR_TAIL_BYTES : Int32 = 65536

///|
/// The buffer keeps one byte more than the tail, so that
/// `@worker.StderrTail::of` sees that bytes were dropped and marks the tail
/// as truncated.
const STDERR_BUFFER_BYTES : Int32 = STDERR_TAIL_BYTES + 1

///|
/// The end of a worker's stderr, drained while the worker runs. Memory stays
/// bounded whatever the worker writes.
pub struct StderrBuffer {
  priv ring : FixedArray[Byte]
  priv mut start : Int32
  priv mut length : Int32
}

///|
pub fn StderrBuffer::new() -> StderrBuffer {
  { ring: FixedArray::make(STDERR_BUFFER_BYTES, b'\x00'), start: 0, length: 0, }
}

///|
/// Adds a chunk and drops the oldest bytes above the bound.
pub fn StderrBuffer::write(self : StderrBuffer, chunk : Bytes) -> Unit {
  let capacity = self.ring.length()
  let skip = @cmp.maximum(0, chunk.length() - capacity)
  for i in skip..<chunk.length() {
    let end = (self.start + self.length) % capacity
    self.ring[end] = chunk[i]
    if self.length < capacity {
      self.length += 1
    } else {
      self.start = (self.start + 1) % capacity
    }
  }
}

///|
/// The tail that a worker report keeps.
pub fn StderrBuffer::tail(self : StderrBuffer) -> @worker.StderrTail {
  let capacity = self.ring.length()
  let bytes = Bytes::makei(self.length, i => {
    self.ring[(self.start + i) % capacity]
  })
  @worker.StderrTail::of(bytes)
}
