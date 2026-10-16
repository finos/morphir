///|
pub struct Integer {
  value : @bigint.BigInt
} derive(Eq, Compare, Debug)

///|
pub fn from_bigint(value : @bigint.BigInt) -> Integer {
  { value, }
}

///|
pub fn to_bigint(n : Integer) -> @bigint.BigInt {
  n.value
}

///|
pub fn from_int(n : Int32) -> Integer {
  from_bigint(@bigint.BigInt::from_int(n))
}

///|
pub fn from_int64(n : Int64) -> Integer {
  from_bigint(@bigint.BigInt::from_int64(n))
}

///|
pub fn from_string(s : String) -> Integer? {
  let chars = s.to_array()
  let start = if s.has_prefix("-") || s.has_prefix("+") { 1 } else { 0 }
  if chars.length() == start {
    return None
  }
  for i = start; i < chars.length(); i = i + 1 {
    if chars[i] < '0' || chars[i] > '9' {
      return None
    }
  }
  Some(
    from_bigint(
      @bigint.BigInt::from_string(
        if s.has_prefix("+") {
          s[1:].to_owned()
        } else {
          s
        },
      ),
    ),
  )
}

///|
pub fn parse(s : String) -> Integer raise @sdk.SdkError {
  match from_string(s) {
    Some(n) => n
    None => raise @sdk.InvalidNumber(s)
  }
}

///|
pub fn to_string(n : Integer) -> String {
  n.value.to_string()
}

///|
pub fn to_int(n : Integer) -> Int32? {
  if n.value.compare_int(-2147483648) < 0 || n.value.compare_int(2147483647) > 0 {
    None
  } else {
    Some(n.value.to_int())
  }
}

///|
pub fn to_int64(n : Integer) -> Int64? {
  if n.value.compare_int64(-9223372036854775808L) < 0 ||
    n.value.compare_int64(9223372036854775807L) > 0 {
    None
  } else {
    Some(n.value.to_int64())
  }
}

///|
pub fn add(a : Integer, b : Integer) -> Integer {
  from_bigint(a.value + b.value)
}

///|
pub fn subtract(a : Integer, b : Integer) -> Integer {
  from_bigint(a.value - b.value)
}

///|
pub fn multiply(a : Integer, b : Integer) -> Integer {
  from_bigint(a.value * b.value)
}

///|
pub fn negate(a : Integer) -> Integer {
  from_bigint(-a.value)
}

///|
pub fn abs(a : Integer) -> Integer {
  if a.value.compare_int(0) < 0 {
    negate(a)
  } else {
    a
  }
}

///|
pub fn compare(a : Integer, b : Integer) -> @sdk.Order {
  @sdk.order(a.value.compare(b.value))
}

///|
pub fn divide(a : Integer, b : Integer) -> Integer raise @sdk.SdkError {
  if b.value.is_zero() {
    raise @sdk.DivisionByZero
  }
  let q = abs(a).value / abs(b).value
  from_bigint(
    if (a.value.compare_int(0) < 0) != (b.value.compare_int(0) < 0) {
      -q
    } else {
      q
    },
  )
}

///|
pub fn remainder_by(
  divisor : Integer,
  value : Integer,
) -> Integer raise @sdk.SdkError {
  subtract(value, multiply(divide(value, divisor), divisor))
}

///|
pub fn mod_by(
  divisor : Integer,
  value : Integer,
) -> Integer raise @sdk.SdkError {
  let r = remainder_by(divisor, value)
  if !r.value.is_zero() &&
    (r.value.compare_int(0) < 0) != (divisor.value.compare_int(0) < 0) {
    add(r, divisor)
  } else {
    r
  }
}

///|
pub fn power(base : Integer, exponent : Integer) -> Integer raise @sdk.SdkError {
  if exponent.value.compare_int(0) < 0 {
    raise @sdk.OutOfRange("negative integer exponent")
  }
  from_bigint(base.value.pow(exponent.value))
}

///|
pub fn to_float(n : Integer) -> Double {
  @parse.parse_double(n.value.to_string()) catch {
    _ => if n.value.compare_int(0) < 0 { -1.0 / 0.0 } else { 1.0 / 0.0 }
  }
}

///|
/// Decode the IEEE significand directly, avoiding a machine-integer narrowing.
pub fn from_float_truncated(n : Double) -> Integer raise @sdk.SdkError {
  if n.is_nan() || n.is_inf() {
    raise @sdk.InvalidNumber("nonfinite Float to Integer")
  }
  let bits = n.reinterpret_as_uint64()
  let exponent = ((bits >> 52) & 2047UL).to_int() - 1023
  if exponent < 0 {
    return from_int(0)
  }
  let significand = (bits & 4503599627370495UL) | 4503599627370496UL
  let b = @bigint.BigInt::from_uint64(significand)
  let value = if exponent >= 52 {
    b << (exponent - 52)
  } else {
    b >> (52 - exponent)
  }
  from_bigint(if n < 0.0 { -value } else { value })
}

///|
pub extend Integer with Eq::{equal, not_equal}

///|
pub extend Integer with @debug.Debug::{to_repr}

///|
pub extend Integer with Compare::{compare, op_lt, op_le, op_gt, op_ge}
