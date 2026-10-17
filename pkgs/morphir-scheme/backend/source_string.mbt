///|
fn source_string_registry() -> Array[(String, Int32)] {
  [
    ("morphir/moonbit-source:string#require-valid", 2),
    ("morphir/moonbit-source:string#append-bounded", 3),
  ]
}

///|
fn source_string_arity(name : String) -> Int32? {
  source_string_registry().filter(row => row.0 == name).get(0).map(row => row.1)
}

///|
fn source_string_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  guard source_string_arity(name) is Some(arity) else {
    raise @scheme.Unbound("Missing source String extension: " + name)
  }
  @scheme.arity(args, arity, name)
  let limit = match @integer.to_int(sdk_integer(args[arity - 1])) {
    Some(n) => n
    None => raise @sdk.OutOfRange("MoonBit source String limit")
  }
  let value = match name {
    "morphir/moonbit-source:string#require-valid" =>
      @source_string.require_valid(sdk_text(args[0]), limit)
    "morphir/moonbit-source:string#append-bounded" =>
      @source_string.append_bounded(sdk_text(args[0]), sdk_text(args[1]), limit)
    _ => raise @scheme.Unbound(name)
  }
  sdk_text_value(value)
}
