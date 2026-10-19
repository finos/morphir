///|
/// Enforce the existing SDK's opaque bounded representation at execution adapters.
/// Descriptive source metadata cannot grant a value this semantic type.
fn sdk_integer_width(owner : String) -> String? {
  match owner {
    "morphir/SDK:int#int-16" => Some("int16")
    "morphir/SDK:int#int-64" => Some("int64")
    "morphir/SDK:int#byte" => Some("byte")
    "morphir/SDK:int#uint-16" => Some("uint16")
    "morphir/SDK:int#uint-32" => Some("uint32")
    "morphir/SDK:int#uint-64" => Some("uint64")
    _ => None
  }
}

///|
fn validate_sdk_boundary(value : @protocol.Value) -> Unit raise {
  match value {
    Constructor("morphir/SDK:int#int-32", "morphir/SDK:int#int32", [Integer(n)]) => {
      guard @sdk_int.to_int32(@integer.from_bigint(n)) is Some(_) else {
        raise @protocol.Invalid("execution.int32_range")
      }
    }
    Constructor("morphir/SDK:int#int-32", _, _) =>
      raise @protocol.Invalid("execution.wrong_type")
    Constructor(owner, tag, [Integer(n)]) if sdk_integer_width(owner)
      is Some(width) => {
      let expected_tag = "morphir/SDK:int#" +
        (if width.has_prefix("int") {
          width
        } else {
          owner.clamped_view(start="morphir/SDK:int#".length()).to_owned()
        })
      if tag != expected_tag {
        raise @protocol.Invalid("execution.wrong_type")
      }
      let integer = @integer.from_bigint(n)
      let fits = match width {
        "int16" => @sdk_int.to_int16(integer) is Some(_)
        "int64" => @sdk_int.to_int64(integer) is Some(_)
        "byte" => @sdk_int.to_byte(integer) is Some(_)
        "uint16" => @sdk_int.to_uint16(integer) is Some(_)
        "uint32" => @sdk_int.to_uint32(integer) is Some(_)
        "uint64" => @sdk_int.to_uint64(integer) is Some(_)
        _ => false
      }
      if !fits {
        raise @protocol.Invalid("execution." + width + "_range")
      }
    }
    Constructor(owner, _, _) if sdk_integer_width(owner) is Some(_) =>
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
