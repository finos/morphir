///|
/// JSON numbers can round to integral Doubles or underflow to zero. Use the
/// validated original decimal token to decide mathematical integrality first.
fn integral_token(source : String) -> Bool {
  let chars = source.iter().collect()
  let mut fraction = 0
  let mut decimal = false
  let mut zeros = 0
  let mut nonzero = false
  let mut index = 0
  while index < chars.length() && chars[index] != 'e' && chars[index] != 'E' {
    let c = chars[index]
    if c == '.' {
      decimal = true
    } else if c >= '0' && c <= '9' {
      if decimal {
        fraction += 1
      }
      if c == '0' {
        zeros += 1
      } else {
        zeros = 0
        nonzero = true
      }
    }
    index += 1
  }
  if !nonzero {
    return true
  }
  let mut negative = false
  let mut exponent = 0
  if index < chars.length() {
    index += 1
    if index < chars.length() && (chars[index] == '+' || chars[index] == '-') {
      negative = chars[index] == '-'
      index += 1
    }
    while index < chars.length() {
      // An exponent beyond the token length cannot be cancelled by its
      // mantissa or fraction. Saturate before multiplying, without overflow.
      let digit = chars[index].to_int() - '0'.to_int()
      let cap = chars.length()
      exponent = if exponent > cap / 10 ||
        (exponent == cap / 10 && digit > cap % 10) {
        cap
      } else {
        exponent * 10 + digit
      }
      index += 1
    }
  }
  (if negative { -exponent } else { exponent }) - fraction + zeros >= 0
}

///|
/// Mathematical integer test for the original JSON number token retained by
/// parse/parse_bounded. For numbers constructed without a token, inspect their
/// stored Double value. This cannot restore precision lost by another parser.
pub fn is_integral_number(value : Json) -> Bool {
  match value {
    Number(_, repr=Some(source)) => integral_token(source)
    Number(n, repr=None) => n - n == 0.0 && n.floor() == n
    _ => false
  }
}
