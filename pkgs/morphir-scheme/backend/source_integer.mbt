///|
fn source_integer_registry() -> Array[(String, Int32)] {
  [
    ("morphir/moonbit-source:int16#normalize", 1),
    ("morphir/moonbit-source:int64#normalize", 1),
    ("morphir/moonbit-source:byte#normalize", 1),
    ("morphir/moonbit-source:uint16#normalize", 1),
    ("morphir/moonbit-source:uint32#normalize", 1),
    ("morphir/moonbit-source:uint64#normalize", 1),
    ("morphir/moonbit-source:integer#add", 2),
    ("morphir/moonbit-source:integer#subtract", 2),
    ("morphir/moonbit-source:integer#multiply", 2),
    ("morphir/moonbit-source:integer#negate", 1),
    ("morphir/moonbit-source:integer#require-budget", 1),
    ("morphir/moonbit-source:integer#equal", 2),
    ("morphir/moonbit-source:integer#not-equal", 2),
    ("morphir/moonbit-source:integer#less-than", 2),
    ("morphir/moonbit-source:integer#less-than-or-equal", 2),
    ("morphir/moonbit-source:integer#greater-than", 2),
    ("morphir/moonbit-source:integer#greater-than-or-equal", 2),
  ]
}

///|
fn source_integer_arity(name : String) -> Int32? {
  source_integer_registry()
  .filter(row => row.0 == name)
  .get(0)
  .map(row => row.1)
}

///|
fn source_integer_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  guard source_integer_arity(name) is Some(arity) else {
    raise @scheme.Unbound("Missing source integer extension: " + name)
  }
  @scheme.arity(args, arity, name)
  let value = sdk_integer(args[0])
  if name.has_prefix("morphir/moonbit-source:integer#") {
    let right = if arity == 2 { sdk_integer(args[1]) } else { value }
    return match name {
      "morphir/moonbit-source:integer#add" =>
        exact_integer(@source_integer.add(value, right))
      "morphir/moonbit-source:integer#subtract" =>
        exact_integer(@source_integer.subtract(value, right))
      "morphir/moonbit-source:integer#multiply" =>
        exact_integer(@source_integer.multiply(value, right))
      "morphir/moonbit-source:integer#negate" =>
        exact_integer(@source_integer.negate(value))
      "morphir/moonbit-source:integer#require-budget" =>
        exact_integer(@source_integer.require_budget(value))
      "morphir/moonbit-source:integer#equal" =>
        @scheme.Boolean(@source_integer.equal(value, right))
      "morphir/moonbit-source:integer#not-equal" =>
        @scheme.Boolean(@source_integer.not_equal(value, right))
      "morphir/moonbit-source:integer#less-than" =>
        @scheme.Boolean(@source_integer.less_than(value, right))
      "morphir/moonbit-source:integer#less-than-or-equal" =>
        @scheme.Boolean(@source_integer.less_than_or_equal(value, right))
      "morphir/moonbit-source:integer#greater-than" =>
        @scheme.Boolean(@source_integer.greater_than(value, right))
      "morphir/moonbit-source:integer#greater-than-or-equal" =>
        @scheme.Boolean(@source_integer.greater_than_or_equal(value, right))
      _ => raise @scheme.Unbound(name)
    }
  }
  match name {
    "morphir/moonbit-source:int16#normalize" =>
      sdk_width_value(
        "int16",
        @sdk_int.from_int16(@source_integer.normalize_int16(value)),
      )
    "morphir/moonbit-source:int64#normalize" =>
      sdk_width_value(
        "int64",
        @sdk_int.from_int64(@source_integer.normalize_int64(value)),
      )
    "morphir/moonbit-source:byte#normalize" =>
      sdk_width_value(
        "byte",
        @sdk_int.from_byte(@source_integer.normalize_byte(value)),
      )
    "morphir/moonbit-source:uint16#normalize" =>
      sdk_width_value(
        "uint-16",
        @sdk_int.from_uint16(@source_integer.normalize_uint16(value)),
      )
    "morphir/moonbit-source:uint32#normalize" =>
      sdk_width_value(
        "uint-32",
        @sdk_int.from_uint32(@source_integer.normalize_uint32(value)),
      )
    "morphir/moonbit-source:uint64#normalize" =>
      sdk_width_value(
        "uint-64",
        @sdk_int.from_uint64(@source_integer.normalize_uint64(value)),
      )
    _ => raise @scheme.Unbound(name)
  }
}
