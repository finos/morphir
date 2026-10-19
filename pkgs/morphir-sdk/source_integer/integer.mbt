///|
pub const PROFILE : String = "morphir-moonbit-source-integer-v1"

///|
pub const MAX_DECIMAL_DIGITS : Int32 = 4096

///|
fn bounded(value : @integer.Integer) -> @integer.Integer raise @sdk.SdkError {
  let text = @integer.to_string(value)
  let digits = text.length() - (if text.has_prefix("-") { 1 } else { 0 })
  if digits > MAX_DECIMAL_DIGITS {
    raise @sdk.OutOfRange("MoonBit source integer digit budget exceeded")
  }
  value
}

///|
pub fn require_budget(
  value : @integer.Integer,
) -> @integer.Integer raise @sdk.SdkError {
  bounded(value)
}

///|
pub fn add(
  a : @integer.Integer,
  b : @integer.Integer,
) -> @integer.Integer raise @sdk.SdkError {
  bounded(@integer.add(bounded(a), bounded(b)))
}

///|
pub fn subtract(
  a : @integer.Integer,
  b : @integer.Integer,
) -> @integer.Integer raise @sdk.SdkError {
  bounded(@integer.subtract(bounded(a), bounded(b)))
}

///|
pub fn multiply(
  a : @integer.Integer,
  b : @integer.Integer,
) -> @integer.Integer raise @sdk.SdkError {
  bounded(@integer.multiply(bounded(a), bounded(b)))
}

///|
pub fn negate(a : @integer.Integer) -> @integer.Integer raise @sdk.SdkError {
  bounded(@integer.negate(bounded(a)))
}

///|
pub fn equal(
  a : @integer.Integer,
  b : @integer.Integer,
) -> Bool raise @sdk.SdkError {
  bounded(a) == bounded(b)
}

///|
pub fn not_equal(
  a : @integer.Integer,
  b : @integer.Integer,
) -> Bool raise @sdk.SdkError {
  bounded(a) != bounded(b)
}

///|
pub fn less_than(
  a : @integer.Integer,
  b : @integer.Integer,
) -> Bool raise @sdk.SdkError {
  bounded(a) < bounded(b)
}

///|
pub fn less_than_or_equal(
  a : @integer.Integer,
  b : @integer.Integer,
) -> Bool raise @sdk.SdkError {
  bounded(a) <= bounded(b)
}

///|
pub fn greater_than(
  a : @integer.Integer,
  b : @integer.Integer,
) -> Bool raise @sdk.SdkError {
  bounded(a) > bounded(b)
}

///|
pub fn greater_than_or_equal(
  a : @integer.Integer,
  b : @integer.Integer,
) -> Bool raise @sdk.SdkError {
  bounded(a) >= bounded(b)
}

///|
/// Source arithmetic wraps modulo 2^bits. Signed forms interpret the upper
/// half as negative after the modular operation.
fn wrapped(
  value : @integer.Integer,
  bits : Int32,
  signed : Bool,
) -> @integer.Integer raise @sdk.SdkError {
  let modulus = @integer.power(@integer.from_int(2), @integer.from_int(bits))
  let residue = @integer.mod_by(modulus, value)
  if signed && residue >= @integer.divide(modulus, @integer.from_int(2)) {
    @integer.subtract(residue, modulus)
  } else {
    residue
  }
}

///|
pub fn normalize_int16(
  value : @integer.Integer,
) -> @int.Int16Value raise @sdk.SdkError {
  match @int.to_int16(wrapped(value, 16, true)) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source Int16 normalization")
  }
}

///|
pub fn normalize_int64(
  value : @integer.Integer,
) -> @int.Int64Value raise @sdk.SdkError {
  match @int.to_int64(wrapped(value, 64, true)) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source Int64 normalization")
  }
}

///|
pub fn normalize_byte(
  value : @integer.Integer,
) -> @int.ByteValue raise @sdk.SdkError {
  match @int.to_byte(wrapped(value, 8, false)) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source Byte normalization")
  }
}

///|
pub fn normalize_uint16(
  value : @integer.Integer,
) -> @int.UInt16Value raise @sdk.SdkError {
  match @int.to_uint16(wrapped(value, 16, false)) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source UInt16 normalization")
  }
}

///|
pub fn normalize_uint32(
  value : @integer.Integer,
) -> @int.UInt32Value raise @sdk.SdkError {
  match @int.to_uint32(wrapped(value, 32, false)) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source UInt32 normalization")
  }
}

///|
pub fn normalize_uint64(
  value : @integer.Integer,
) -> @int.UInt64Value raise @sdk.SdkError {
  match @int.to_uint64(wrapped(value, 64, false)) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source UInt64 normalization")
  }
}
