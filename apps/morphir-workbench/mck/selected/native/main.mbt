///|
async fn main {
  let pending : Array[Byte] = []
  // Bound input before parsing. The MCK transport also bounds its output/input.
  while @stdio.stdin.read_some(max_len=65536) is Some(chunk) {
    for byte in chunk {
      if byte == b'\n' {
        let line = @utf8.decode(Bytes::from_array(pending)[:])
        guard @mck.handle_line(line) is Some(response) else { return }
        @stdio.stdout.write(response.stringify() + "\n")
        pending.clear()
      } else {
        pending.push(byte)
        if pending.length() > 2097152 {
          abort("workbench: NDJSON line exceeds 2 MiB")
        }
      }
    }
  }
  if !pending.is_empty() {
    abort("workbench: incomplete NDJSON line")
  }
}
