///|
fn source_float_reference(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  if !ctx.source_extensions.contains("float32") {
    raise Invalid(
      "moonbit.missing_source_extension",
      context,
      name.to_canonical(),
    )
  }
  let operation = name.local_name.to_canonical()
  let float = Atom(Scalar::Float32)
  let float64 = Atom(Scalar::Float)
  let boolean = [
    "equal", "not-equal", "less-than", "less-than-or-equal", "greater-than", "greater-than-or-equal",
  ].contains(operation)
  let unary = operation == "from-float64" ||
    operation == "negate" ||
    operation == "round-boundary"
  if !unary &&
    !boolean &&
    !["add", "subtract", "multiply", "divide"].contains(operation) {
    raise Invalid(
      "moonbit.unsupported_source_extension",
      context,
      name.to_canonical(),
    )
  }
  let result = if boolean { Atom(Scalar::Boolean) } else { float }
  let signature = if unary {
    Arrow(if operation == "from-float64" { float64 } else { float }, result)
  } else {
    Arrow(float, Arrow(float, result))
  }
  if expected != signature {
    raise Invalid(
      "moonbit.source_extension_signature",
      context,
      name.to_canonical(),
    )
  }
  ctx.imports["source_float"] = true
  let arguments = if unary {
    [("a0", if operation == "from-float64" { float64 } else { float })]
  } else {
    [("a0", float), ("a1", float)]
  }
  let body = match operation {
    "from-float64" => "@source_float.round32(a0)"
    "round-boundary" => "@source_float.round32(a0)"
    "negate" => "@source_float.negate32(a0)"
    "add" | "subtract" | "multiply" | "divide" =>
      "@source_float." + operation + "32(a0, a1)"
    _ => {
      let lhs = "@source_float.round32(a0)"
      let rhs = "@source_float.round32(a1)"
      let comparator = match operation {
        "equal" => "=="
        "not-equal" => "!="
        "less-than" => "<"
        "less-than-or-equal" => "<="
        "greater-than" => ">"
        _ => ">="
      }
      "(" + lhs + " " + comparator + " " + rhs + ")"
    }
  }
  curry_source(ctx, arguments, result, body)
}
