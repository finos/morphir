///|
/// A numerical Decimal, distinct from an IR decimal literal's original lexeme.
/// The coefficient is exact; normalization follows elm-bignum 1.0.1's -32
/// minimum exponent for public arithmetic and parsing.
pub struct Decimal {
  coefficient : @bigint.BigInt
  exponent : Int32
} derive(Eq, Debug)

///|
pub extend Decimal with Eq::{equal, not_equal}

///|
pub extend Decimal with @debug.Debug::{to_repr}

///|
fn ten() -> @bigint.BigInt {
  @bigint.BigInt::from_int(10)
}

///|
fn pow10(n : Int32) -> @bigint.BigInt {
  ten().pow(@bigint.BigInt::from_int(n))
}

///|
fn absolute(n : @bigint.BigInt) -> @bigint.BigInt {
  if n.compare_int(0) < 0 {
    -n
  } else {
    n
  }
}

///|
fn divide_truncated(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let q = absolute(a) / absolute(b)
  if (a.compare_int(0) < 0) != (b.compare_int(0) < 0) {
    -q
  } else {
    q
  }
}

///|
fn normalize(coefficient : @bigint.BigInt, exponent : Int32) -> Decimal {
  if coefficient.is_zero() {
    return { coefficient, exponent: 0, }
  }
  let mut n = coefficient
  let mut e = exponent
  if e < -32 {
    n = divide_truncated(n, pow10(-32 - e))
    e = -32
  }
  while !n.is_zero() {
    let q = divide_truncated(n, ten())
    if q * ten() != n {
      break
    }
    n = q
    e += 1
  }
  { coefficient: n, exponent: e, }
}

///|
pub fn from_integer(value : @integer.Integer) -> Decimal {
  normalize(@integer.to_bigint(value), 0)
}

///|
pub fn from_int(value : @integer.Integer) -> Decimal {
  from_integer(value)
}

///|
pub fn zero() -> Decimal {
  normalize(@bigint.BigInt::from_int(0), 0)
}

///|
pub fn one() -> Decimal {
  normalize(@bigint.BigInt::from_int(1), 0)
}

///|
pub fn minus_one() -> Decimal {
  normalize(@bigint.BigInt::from_int(-1), 0)
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn all_digits(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for c in value.to_array() {
    if !is_digit(c) {
      return false
    }
  }
  true
}

///|
pub fn from_string(value : String) -> Decimal? {
  if value.is_empty() {
    return None
  }
  let negative = value.has_prefix("-")
  let unsigned = if negative {
    value.clamped_view(start=1).to_owned()
  } else {
    value
  }
  let scientific = unsigned.split("e").map(part => part.to_owned()).to_array()
  if scientific.length() > 2 {
    return None
  }
  let mantissa = scientific[0]
  let mut scientific_exponent = 0
  if scientific.length() == 2 {
    let exp_text = scientific[1]
    let exp_digits = if exp_text.has_prefix("-") {
      exp_text.clamped_view(start=1).to_owned()
    } else {
      exp_text
    }
    if !all_digits(exp_digits) {
      return None
    }
    scientific_exponent = @parse.parse_int(exp_text) catch { _ => return None }
    if scientific_exponent < -32 {
      return None
    }
  }
  let components = mantissa.split(".").map(part => part.to_owned()).to_array()
  if components.length() > 2 || !all_digits(components[0]) {
    return None
  }
  let fraction = if components.length() == 2 { components[1] } else { "" }
  if components.length() == 2 && !all_digits(fraction) {
    return None
  }
  if scientific.length() == 2 {
    if components[0].length() != 1 {
      return None
    }
    if components.length() == 2 && fraction.has_suffix("0") {
      return None
    }
  }
  let digits = components[0] + fraction
  let signed = if negative { "-" + digits } else { digits }
  let coefficient = @bigint.BigInt::from_string(signed)
  let exponent = scientific_exponent - fraction.length()
  Some(normalize(coefficient, exponent))
}

///|
pub fn to_string(value : Decimal) -> String {
  if value.coefficient.is_zero() {
    return "0"
  }
  let sign = if value.coefficient.compare_int(0) < 0 { "-" } else { "" }
  let digits = absolute(value.coefficient).to_string()
  if value.exponent >= 0 {
    return sign + digits + "0".repeat(value.exponent)
  }
  let point = digits.length() + value.exponent
  if point > 0 {
    sign +
    digits.clamped_view(end=point).to_owned() +
    "." +
    digits.clamped_view(start=point).to_owned()
  } else {
    sign + "0." + "0".repeat(-point) + digits
  }
}

///|
pub fn from_float(value : Double) -> Decimal raise @sdk.SdkError {
  if value.is_nan() || value.is_inf() {
    raise @sdk.InvalidNumber("nonfinite Float to Decimal")
  }
  let text = value.to_string().replace_all(old="e+", new="e")
  match from_string(text) {
    Some(decimal) => decimal
    None => raise @sdk.InvalidNumber(text)
  }
}

///|
pub fn to_float(value : Decimal) -> Double {
  @parse.parse_double(to_string(value)) catch {
    _ =>
      if value.coefficient.compare_int(0) < 0 {
        -1.0 / 0.0
      } else {
        1.0 / 0.0
      }
  }
}

///|
pub fn add(a : Decimal, b : Decimal) -> Decimal {
  let exponent = Int32::min(a.exponent, b.exponent)
  normalize(
    a.coefficient * pow10(a.exponent - exponent) +
    b.coefficient * pow10(b.exponent - exponent),
    exponent,
  )
}

///|
pub fn sub(a : Decimal, b : Decimal) -> Decimal {
  add(a, negate(b))
}

///|
pub fn negate(value : Decimal) -> Decimal {
  { coefficient: -value.coefficient, exponent: value.exponent, }
}

///|
pub fn abs(value : Decimal) -> Decimal {
  if value.coefficient.compare_int(0) < 0 {
    negate(value)
  } else {
    value
  }
}

///|
pub fn mul(a : Decimal, b : Decimal) -> Decimal {
  normalize(a.coefficient * b.coefficient, a.exponent + b.exponent)
}

///|
pub fn div(a : Decimal, b : Decimal) -> Decimal? {
  if b.coefficient.is_zero() {
    return None
  }
  if a.coefficient.is_zero() {
    return Some(zero())
  }
  let scale = a.exponent - b.exponent + 32
  let coefficient = if scale >= 0 {
    divide_truncated(a.coefficient * pow10(scale), b.coefficient)
  } else {
    divide_truncated(a.coefficient, b.coefficient * pow10(-scale))
  }
  if coefficient.is_zero() {
    None
  } else {
    Some(normalize(coefficient, -32))
  }
}

///|
pub fn div_with_default(
  fallback : Decimal,
  a : Decimal,
  b : Decimal,
) -> Decimal {
  match div(a, b) {
    Some(result) => result
    None => fallback
  }
}

///|
pub fn compare(a : Decimal, b : Decimal) -> @sdk.Order {
  let exponent = Int32::min(a.exponent, b.exponent)
  @sdk.order(
    (a.coefficient * pow10(a.exponent - exponent)).compare(
      b.coefficient * pow10(b.exponent - exponent),
    ),
  )
}

///|
pub fn eq(a : Decimal, b : Decimal) -> Bool {
  compare(a, b) == @sdk.EQ
}

///|
pub fn neq(a : Decimal, b : Decimal) -> Bool {
  !eq(a, b)
}

///|
pub fn gt(a : Decimal, b : Decimal) -> Bool {
  compare(a, b) == @sdk.GT
}

///|
pub fn gte(a : Decimal, b : Decimal) -> Bool {
  compare(a, b) != @sdk.LT
}

///|
pub fn lt(a : Decimal, b : Decimal) -> Bool {
  compare(a, b) == @sdk.LT
}

///|
pub fn lte(a : Decimal, b : Decimal) -> Bool {
  compare(a, b) != @sdk.GT
}

///|
pub fn truncate(value : Decimal) -> Decimal {
  if value.exponent >= 0 {
    return value
  }
  normalize(divide_truncated(value.coefficient, pow10(-value.exponent)), 0)
}

///|
pub fn round(value : Decimal) -> Decimal {
  if value.exponent >= 0 {
    return value
  }
  let denominator = pow10(-value.exponent)
  let quotient = divide_truncated(value.coefficient, denominator)
  let remainder = value.coefficient - quotient * denominator
  let doubled = absolute(remainder) * @bigint.BigInt::from_int(2)
  let two = @bigint.BigInt::from_int(2)
  let odd = divide_truncated(quotient, two) * two != quotient
  let should_adjust = doubled.compare(denominator) > 0 ||
    (doubled.compare(denominator) == 0 && odd)
  let rounded = if should_adjust {
    quotient +
    @bigint.BigInt::from_int(
      if value.coefficient.compare_int(0) < 0 {
        -1
      } else {
        1
      },
    )
  } else {
    quotient
  }
  normalize(rounded, 0)
}

///|
pub fn shift_decimal_left(count : Int32, value : Decimal) -> Decimal {
  normalize(value.coefficient, value.exponent - count)
}

///|
pub fn shift_decimal_right(count : Int32, value : Decimal) -> Decimal {
  normalize(value.coefficient, value.exponent + count)
}

///|
pub fn hundred(value : @integer.Integer) -> Decimal {
  shift_decimal_right(2, from_int(value))
}

///|
pub fn thousand(value : @integer.Integer) -> Decimal {
  shift_decimal_right(3, from_int(value))
}

///|
pub fn million(value : @integer.Integer) -> Decimal {
  shift_decimal_right(6, from_int(value))
}

///|
pub fn tenth(value : @integer.Integer) -> Decimal {
  shift_decimal_left(1, from_int(value))
}

///|
pub fn hundredth(value : @integer.Integer) -> Decimal {
  shift_decimal_left(2, from_int(value))
}

///|
pub fn thousandth(value : @integer.Integer) -> Decimal {
  shift_decimal_left(3, from_int(value))
}

///|
pub fn millionth(value : @integer.Integer) -> Decimal {
  shift_decimal_left(6, from_int(value))
}

///|
pub fn bps(value : @integer.Integer) -> Decimal {
  shift_decimal_left(4, from_int(value))
}
