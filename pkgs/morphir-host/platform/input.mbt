///|
/// Read explicit input with a byte limit. A dash selects stdin. Files use the
/// regular-file chunk reader, and stdin reads at most one byte beyond the limit.
/// Input ownership remains with the caller; stdin is never closed.
#cfg(any(target="native", target="js"))
pub fn read_input(path : String, limit : Int32) -> Bytes raise {
  if limit < 1 || limit > 16777216 {
    raise IOError("input.invalid_limit")
  }
  let chunks : Array[Bytes] = []
  if path != "-" {
    if path.contains("\u0000") || kind(path) != 1 {
      raise IOError("input.regular_file_required")
    }
    let length = size(path)
    if length < 0 {
      raise IOError("input.read_failed")
    }
    if length > limit {
      raise IOError("input.limit")
    }
    file_chunks(path, limit, chunk => chunks.push(chunk)) catch {
      _ => raise IOError("input.read_failed")
    }
  } else {
    let mut total = 0
    while true {
      if interruption_requested() {
        raise IOError("Cancelled")
      }
      let capacity = (limit - total + 1).min(65536)
      let buffer = FixedArray::make(capacity, b'\x00')
      let length = stdin_read(buffer, capacity)
      if length < 0 || length > capacity {
        if interruption_requested() {
          raise IOError("Cancelled")
        }
        raise IOError("input.read_failed")
      }
      if length == 0 {
        break
      }
      total += length
      if total > limit {
        raise IOError("input.limit")
      }
      chunks.push(Bytes::from_array(buffer[:length].to_owned()))
    }
  }
  Bytes::from_array(chunks.iter().flat_map(chunk => chunk.iter()).collect())
}
