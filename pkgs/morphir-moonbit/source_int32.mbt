///|
fn source_int32_reference(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  let input = Atom(Scalar::Integer)
  let output = Atom(Scalar::SignedInt32)
  if name.to_canonical() != "morphir/moonbit-source:int32#normalize" {
    raise Invalid(
      "moonbit.unsupported_source_extension",
      context,
      name.to_canonical(),
    )
  }
  if expected != Arrow(input, output) {
    raise Invalid(
      "moonbit.source_extension_signature",
      context,
      name.to_canonical(),
    )
  }
  ctx.imports["source_int32"] = true
  ctx.imports["integer"] = true
  ctx.imports["int"] = true
  curry_source(ctx, [("a0", input)], output, "@source_int32.normalize(a0)")
}
