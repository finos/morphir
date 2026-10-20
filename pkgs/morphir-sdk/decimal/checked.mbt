///|
/// Errors of the versioned checked Decimal contract. Classic div remains Maybe.
pub(all) suberror DecimalError {
  DivisionByZero
  Underflow
  PrecisionLoss
  InvalidLiteral
} derive(Eq, Debug)

///|
/// Construct exactly using the classic lexical grammar, refusing truncation.
/// Bound input and exponent work before invoking the numerical parser.
pub fn from_string_exact(text : String) -> Decimal raise DecimalError {
  if text.length() > 4096 {
    raise InvalidLiteral
  }
  let parts = text.split("e").map(p => p.to_owned()).to_array()
  if parts.length() > 2 {
    raise InvalidLiteral
  }
  let exponent = if parts.length() == 2 {
    @parse.parse_int(parts[1]) catch {
      _ => raise InvalidLiteral
    }
  } else {
    0
  }
  if exponent < -32 || exponent > 4096 {
    raise InvalidLiteral
  }
  let value = match from_string(text) {
    Some(value) => value
    None => raise InvalidLiteral
  }
  let mantissa = parts[0].split(".").map(p => p.to_owned()).to_array()
  let fraction = if mantissa.length() == 2 { mantissa[1] } else { "" }
  let below_floor = fraction.length() - exponent - 32
  if below_floor > 0 {
    let discarded = fraction.clamped_view(start=fraction.length() - below_floor)
    if discarded.to_owned().to_array().any(c => c != '0') {
      raise PrecisionLoss
    }
  }
  // Classic truncation can produce a zero with exponent -32. Checked zero is
  // canonical regardless of the authored number of fractional zeroes.
  if value.coefficient.is_zero() {
    zero()
  } else {
    value
  }
}

///|
/// Truncate the quotient toward zero at exponent -32. A nonzero quotient
/// below that floor is Underflow; exact zero succeeds, including 0/nonzero.
pub fn divide(a : Decimal, b : Decimal) -> Decimal raise DecimalError {
  if b.coefficient.is_zero() {
    raise DivisionByZero
  }
  match div(a, b) {
    Some(value) => value
    None => raise Underflow
  }
}

///|
/// Fallback is opt-in and applies only to the two documented division failures.
pub fn divide_with_default(
  fallback : Decimal,
  a : Decimal,
  b : Decimal,
) -> Decimal {
  match div(a, b) {
    Some(value) => value
    None => fallback
  }
}

///|
pub extend DecimalError with Eq::{equal, not_equal}

///|
pub extend DecimalError with @debug.Debug::{to_repr}
