///|
/// Source arithmetic is a separate extension from checked SDK narrowing.
pub const PROFILE : String = "morphir-moonbit-source-int32-v1"

///|
/// Normalize an exact intermediate to the signed 32-bit MoonBit result.
pub fn normalize(
  value : @integer.Integer,
) -> @int.Int32Value raise @sdk.SdkError {
  let modulus = @integer.from_int64(4294967296L)
  let residue = @integer.mod_by(modulus, value)
  let signed = if residue > @integer.from_int64(2147483647L) {
    @integer.subtract(residue, modulus)
  } else {
    residue
  }
  match @int.to_int32(signed) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source Int32 normalization")
  }
}
