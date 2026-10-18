///|
fn integer_token(text : String) -> Bool {
  let characters = text.iter().collect()
  let start = if characters.length() > 0 &&
    (characters[0] == '-' || characters[0] == '+') {
    1
  } else {
    0
  }
  if start == characters.length() {
    return false
  }
  for i = start; i < characters.length(); i = i + 1 {
    if characters[i] < '0' || characters[i] > '9' {
      return false
    }
  }
  true
}

///|
fn bigint(text : String) -> @bigint.BigInt {
  @bigint.BigInt::from_string(
    if text.has_prefix("+") {
      text[1:].to_owned()
    } else {
      text
    },
  )
}

///|
pub fn rational(
  numerator : @bigint.BigInt,
  denominator : @bigint.BigInt,
) -> Number raise SchemeError {
  if denominator.is_zero() {
    raise Invalid("Division by zero")
  }
  let mut a = if numerator < @bigint.BigInt::from_int(0) {
    -numerator
  } else {
    numerator
  }
  let mut b = if denominator < @bigint.BigInt::from_int(0) {
    -denominator
  } else {
    denominator
  }
  while !b.is_zero() {
    let remainder = a % b
    a = b
    b = remainder
  }
  let divisor = if denominator < @bigint.BigInt::from_int(0) { -a } else { a }
  let n = numerator / divisor
  let d = denominator / divisor
  if d == @bigint.BigInt::from_int(1) {
    Integer(n)
  } else {
    Rational(n, d)
  }
}

///|
pub fn parse_number(text : String) -> Number? raise SchemeError {
  if integer_token(text) {
    return Some(Integer(bigint(text)))
  }
  let parts = text.split("/").collect()
  if parts.length() == 2 &&
    integer_token(parts[0].to_owned()) &&
    integer_token(parts[1].to_owned()) {
    return Some(
      rational(bigint(parts[0].to_owned()), bigint(parts[1].to_owned())),
    )
  }
  if text.contains(".") || text.contains("e") || text.contains("E") {
    let text = if text.has_prefix("+") { text[1:].to_owned() } else { text }
    let parsed = @json.parse(text) catch { _ => return None }
    if parsed is Number(value, ..) {
      if value.is_inf() || value.is_nan() {
        raise Invalid("Nonfinite number")
      }
      return Some(Real(value))
    }
  }
  None
}

///|
pub fn Number::to_text(self : Number) -> String {
  match self {
    Integer(value) => value.to_string()
    Rational(n, d) => n.to_string() + "/" + d.to_string()
    Real(value) => {
      // JavaScript's numeric printer drops the sign of zero.
      if value.reinterpret_as_uint64() == 0x8000000000000000UL {
        return "-0.0"
      }
      let text = value.to_string()
      if text.contains(".") || text.contains("e") || text.contains("E") {
        text
      } else {
        text + ".0"
      }
    }
  }
}

///|
fn Number::real(self : Number) -> Double raise SchemeError {
  match self {
    Real(value) => value
    Integer(value) => {
      let json = @json.parse(value.to_string()) catch {
        _ => raise Invalid("Invalid number")
      }
      match json {
        Number(number, ..) if !number.is_inf() => number
        _ => raise Invalid("Inexact conversion overflow")
      }
    }
    Rational(n, d) => Number::Integer(n).real() / Number::Integer(d).real()
  }
}

///|
fn Number::fraction(
  self : Number,
) -> (@bigint.BigInt, @bigint.BigInt) raise SchemeError {
  match self {
    Integer(value) => (value, @bigint.BigInt::from_int(1))
    Rational(n, d) => (n, d)
    Real(_) => raise Invalid("Expected exact number")
  }
}

///|
fn arithmetic(
  op : String,
  left : Number,
  right : Number,
) -> Number raise SchemeError {
  if left is Real(_) || right is Real(_) {
    let a = left.real()
    let b = right.real()
    if op == "/" && b == 0 {
      raise Invalid("Division by zero")
    }
    let value = match op {
      "+" => a + b
      "-" => a - b
      "*" => a * b
      _ => a / b
    }
    if value.is_inf() || value.is_nan() {
      raise Invalid("Nonfinite arithmetic result")
    }
    Real(value)
  } else {
    let (a, b) = left.fraction()
    let (c, d) = right.fraction()
    match op {
      "+" => rational(a * d + c * b, b * d)
      "-" => rational(a * d - c * b, b * d)
      "*" => rational(a * c, b * d)
      _ => rational(a * d, b * c)
    }
  }
}

///|
fn compare_numbers(left : Number, right : Number) -> Int32 raise SchemeError {
  if left is Real(_) || right is Real(_) {
    left.real().compare(right.real())
  } else {
    let (a, b) = left.fraction()
    let (c, d) = right.fraction()
    (a * d).compare(c * b)
  }
}

///|
fn number(value : Value) -> Number raise SchemeError {
  match value {
    Number(n) => n
    _ => raise Invalid("Expected number")
  }
}
