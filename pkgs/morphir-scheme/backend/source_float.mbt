///|
fn source_float_registry() -> Array[(String, Int32)] {
  [
    ("morphir/moonbit-source:float32#from-float64", 1),
    ("morphir/moonbit-source:float32#negate", 1),
    ("morphir/moonbit-source:float32#round-boundary", 1),
    ("morphir/moonbit-source:float32#add", 2),
    ("morphir/moonbit-source:float32#subtract", 2),
    ("morphir/moonbit-source:float32#multiply", 2),
    ("morphir/moonbit-source:float32#divide", 2),
    ("morphir/moonbit-source:float32#equal", 2),
    ("morphir/moonbit-source:float32#not-equal", 2),
    ("morphir/moonbit-source:float32#less-than", 2),
    ("morphir/moonbit-source:float32#less-than-or-equal", 2),
    ("morphir/moonbit-source:float32#greater-than", 2),
    ("morphir/moonbit-source:float32#greater-than-or-equal", 2),
  ]
}

///|
fn source_float_arity(name : String) -> Int32? {
  source_float_registry().filter(row => row.0 == name).get(0).map(row => row.1)
}

///|
fn source_float_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  guard source_float_arity(name) is Some(arity) else {
    raise @scheme.Unbound("Missing source Float extension: " + name)
  }
  @scheme.arity(args, arity, name)
  let left = @source_float.round32(sdk_float(args[0]))
  let right = if arity == 2 {
    @source_float.round32(sdk_float(args[1]))
  } else {
    0.0
  }
  let numeric = fn(value : Double) {
    @scheme.Value::Number(@scheme.Number::Real(value))
  }
  match name {
    "morphir/moonbit-source:float32#from-float64" => numeric(left)
    "morphir/moonbit-source:float32#negate" =>
      numeric(@source_float.negate32(left))
    "morphir/moonbit-source:float32#round-boundary" => numeric(left)
    "morphir/moonbit-source:float32#add" =>
      numeric(@source_float.add32(left, right))
    "morphir/moonbit-source:float32#subtract" =>
      numeric(@source_float.subtract32(left, right))
    "morphir/moonbit-source:float32#multiply" =>
      numeric(@source_float.multiply32(left, right))
    "morphir/moonbit-source:float32#divide" =>
      numeric(@source_float.divide32(left, right))
    "morphir/moonbit-source:float32#equal" => @scheme.Boolean(left == right)
    "morphir/moonbit-source:float32#not-equal" => @scheme.Boolean(left != right)
    "morphir/moonbit-source:float32#less-than" => @scheme.Boolean(left < right)
    "morphir/moonbit-source:float32#less-than-or-equal" =>
      @scheme.Boolean(left <= right)
    "morphir/moonbit-source:float32#greater-than" =>
      @scheme.Boolean(left > right)
    "morphir/moonbit-source:float32#greater-than-or-equal" =>
      @scheme.Boolean(left >= right)
    _ => raise @scheme.Unbound(name)
  }
}
