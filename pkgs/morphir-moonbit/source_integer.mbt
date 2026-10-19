///|
fn source_integer_reference(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  let module_name = name.module_name.to_canonical()
  if !ctx.source_extensions.contains(module_name) {
    raise Invalid(
      "moonbit.missing_source_extension",
      context,
      name.to_canonical(),
    )
  }
  if module_name == "integer" {
    let operation = name.local_name.to_canonical()
    let boolean = [
      "equal", "not-equal", "less-than", "less-than-or-equal", "greater-than", "greater-than-or-equal",
    ].contains(operation)
    let arithmetic = ["add", "subtract", "multiply", "negate", "require-budget"].contains(
      operation,
    )
    if !boolean && !arithmetic {
      raise Invalid(
        "moonbit.unsupported_source_extension",
        context,
        name.to_canonical(),
      )
    }
    let integer = Atom(Scalar::Integer)
    let output = if boolean { Atom(Scalar::Boolean) } else { integer }
    let unary = operation == "negate" || operation == "require-budget"
    let signature = if unary {
      Arrow(integer, output)
    } else {
      Arrow(integer, Arrow(integer, output))
    }
    if expected != signature {
      raise Invalid(
        "moonbit.source_extension_signature",
        context,
        name.to_canonical(),
      )
    }
    ctx.imports["source_integer"] = true
    ctx.imports["integer"] = true
    return curry_source(
      ctx,
      if unary {
        [("a0", integer)]
      } else {
        [("a0", integer), ("a1", integer)]
      },
      output,
      "@source_integer." +
      operation.replace(old="-", new="_") +
      (if unary { "(a0)" } else { "(a0, a1)" }),
    )
  }
  let width = match module_name {
    "int16" => "int-16"
    "int64" => "int-64"
    "byte" => "byte"
    "uint16" => "uint-16"
    "uint32" => "uint-32"
    "uint64" => "uint-64"
    _ =>
      raise Invalid(
        "moonbit.unsupported_source_extension",
        context,
        name.to_canonical(),
      )
  }
  if name.local_name.to_canonical() != "normalize" ||
    expected != Arrow(Atom(Integer), Atom(BoundedInteger(width))) {
    raise Invalid(
      "moonbit.source_extension_signature",
      context,
      name.to_canonical(),
    )
  }
  ctx.imports["source_integer"] = true
  ctx.imports["integer"] = true
  ctx.imports["int"] = true
  curry_source(
    ctx,
    [("a0", Atom(Integer))],
    Atom(BoundedInteger(width)),
    "@source_integer.normalize_" + module_name + "(a0)",
  )
}
