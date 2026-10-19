///|
fn source_int32_registry() -> Array[(String, Int32)] {
  [("morphir/moonbit-source:int32#normalize", 1)]
}

///|
fn source_int32_arity(name : String) -> Int32? {
  source_int32_registry().filter(row => row.0 == name).get(0).map(row => row.1)
}

///|
fn source_int32_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  guard source_int32_arity(name) is Some(arity) else {
    raise @scheme.Unbound("Missing source Int32 extension: " + name)
  }
  @scheme.arity(args, arity, name)
  sdk_width_value(
    "int32",
    @sdk_int.from_int32(@source_int32.normalize(sdk_integer(args[0]))),
  )
}
