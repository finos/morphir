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
  let int32 = Atom(Scalar::SignedInt32)
  let (inputs, output, function) = match name.to_canonical() {
    "morphir/moonbit-source:string#require-valid" =>
      ([text, int], text, "require_valid")
    "morphir/moonbit-source:string#append-bounded" =>
      ([text, text, int], text, "append_bounded")
    "morphir/moonbit-source:string#length-int32" =>
      ([text, int], int32, "length_int32")
    "morphir/moonbit-source:string#slice-owned" =>
      ([text, int32, int32, int], text, "slice_owned")
    _ =>
      raise Invalid(
        "moonbit.unsupported_source_extension",
        context,
        name.to_canonical(),
      )
  }
  let mut signature = output
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
  if output == int32 || inputs.contains(int32) {
    ctx.imports["int"] = true
    ctx.imports["source_string_index"] = true
  }
  let arguments = inputs.mapi((i, ty) => ("a" + i.to_string(), ty))
  let count = "a" + (inputs.length() - 1).to_string()
  let call = "{ guard @integer.to_int(" +
    count +
    ") is Some(limit) else { raise @sdk.OutOfRange(\"MoonBit source String limit\") }; @source_string." +
    function +
    "(" +
    (if inputs.length() == 2 {
      "a0, limit"
    } else if inputs.length() == 3 {
      "a0, a1, limit"
    } else {
      "a0, a1, a2, limit"
    }) +
    ") }"
  curry_source(ctx, arguments, output, call)
}
