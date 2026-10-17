///|
/// Explicit extension admission. No classic SDK or arbitrary host binding fallback.
fn source_string_reference(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  let text = Atom(Scalar::Text)
  let int = Atom(Scalar::Integer)
  let (inputs, function) = match name.to_canonical() {
    "morphir/moonbit-source:string#require-valid" =>
      ([text, int], "require_valid")
    "morphir/moonbit-source:string#append-bounded" =>
      ([text, text, int], "append_bounded")
    _ =>
      raise Invalid(
        "moonbit.unsupported_source_extension",
        context,
        name.to_canonical(),
      )
  }
  let mut signature = text
  for i = inputs.length() - 1; i >= 0; i = i - 1 {
    signature = Arrow(inputs[i], signature)
  }
  if expected != signature {
    raise Invalid(
      "moonbit.source_extension_signature",
      context,
      name.to_canonical(),
    )
  }
  ctx.imports["source_string"] = true
  ctx.imports["integer"] = true
  let arguments = inputs.mapi((i, ty) => ("a" + i.to_string(), ty))
  let count = "a" + (inputs.length() - 1).to_string()
  let call = "{ guard @integer.to_int(" +
    count +
    ") is Some(limit) else { raise @sdk.OutOfRange(\"MoonBit source String limit\") }; @source_string." +
    function +
    "(" +
    (if inputs.length() == 2 { "a0, limit" } else { "a0, a1, limit" }) +
    ") }"
  curry_source(ctx, arguments, text, call)
}
