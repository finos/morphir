///|
/// Recognize only the actual emitted JSON projection header. Source format metadata,
/// consumer support and typed inspection remain separate decisions. Limits are
/// explicit acceptance/parser budgets, not a VM or streaming-allocation claim.
pub fn recognize_projection_header(
  bytes : Bytes,
  limits : Limits,
) -> @version.FormatVersion raise BoundaryError {
  if limits.max_bytes <= 0 || limits.max_depth < 0 || limits.max_values <= 0 {
    raise Invalid("data.invalid_limits", "Limits must be positive")
  }
  if bytes.length() > limits.max_bytes {
    raise Invalid("data.byte_limit", "Projection exceeds the byte budget")
  }
  let text = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => raise Invalid("data.invalid_utf8", "Projection must be valid UTF-8")
  }
  try {
    let value = @wire.parse_bounded(
      text,
      max_depth=limits.max_depth,
      max_nodes=limits.max_values,
      // A valid UTF-8 byte bounds decoded UTF-16 units conservatively. Escapes
      // consume more source bytes, not fewer, than their decoded string units.
      max_string_units=limits.max_bytes,
    )
    @wire.read_version(@wire.field(value, "formatVersion"))
  } catch {
    @wire.Invalid(code, detail) => raise Invalid(code, detail)
    error =>
      raise Invalid(
        boundary_code(error, "data.decode_failed"),
        error.to_string(),
      )
  }
}
