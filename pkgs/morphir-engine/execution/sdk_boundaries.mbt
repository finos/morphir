///|
/// Enforce the existing SDK's opaque bounded representation at execution adapters.
/// Descriptive source metadata cannot grant a value this semantic type.
fn validate_sdk_boundary(value : @protocol.Value) -> Unit raise {
  match value {
    Constructor("morphir/SDK:int#int-32", "morphir/SDK:int#int32", [Integer(n)]) => {
      guard @sdk_int.to_int32(@integer.from_bigint(n)) is Some(_) else {
        raise @protocol.Invalid("execution.int32_range")
      }
    }
    Constructor("morphir/SDK:int#int-32", _, _) =>
      raise @protocol.Invalid("execution.wrong_type")
    Constructor(_, _, items) | Product(items) | Sequence(items) =>
      for item in items {
        validate_sdk_boundary(item)
      }
    Record(fields) =>
      for (_, item) in fields {
        validate_sdk_boundary(item)
      }
    Optional(Some(item)) | Outcome(Ok(item)) | Outcome(Err(item)) =>
      validate_sdk_boundary(item)
    _ => ()
  }
}
