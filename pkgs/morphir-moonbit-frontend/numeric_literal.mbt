///|
/// Parse only the pinned signed Int32 literal forms, without a machine Int
/// intermediate. The parser has already classified the token as an Int literal.
fn library_int32_literal(
  raw : String,
  loc : @location.Location,
) -> String raise FrontendError {
  let chars = raw.to_array()
  let negative = chars.length() > 0 && chars[0] == '-'
  let mut start = if negative { 1 } else { 0 }
  let mut radix = 10
  if chars.length() > start + 1 && chars[start] == '0' {
    match chars[start + 1] {
      'x' | 'X' => radix = 16
      'b' | 'B' => radix = 2
      'o' | 'O' => radix = 8
      _ => ()
    }
    if radix != 10 {
      start += 2
    }
  }
  let mut value = 0L
  let mut digits = 0
  for i = start; i < chars.length(); i = i + 1 {
    if chars[i] == '_' {
      continue
    }
    let code = chars[i].to_int()
    let digit = if code >= 48 && code <= 57 {
      code - 48
    } else if code >= 65 && code <= 70 {
      code - 55
    } else if code >= 97 && code <= 102 {
      code - 87
    } else {
      -1
    }
    if digit < 0 || digit >= radix {
      reject("invalid_literal", "Invalid signed Int32 literal", loc)
    }
    value = value * radix.to_int64() + digit.to_int64()
    if value > 4294967295L {
      reject("invalid_literal", "Signed Int32 literal exceeds 32 bits", loc)
    }
    digits += 1
  }
  let decimal_limit = if negative { 2147483648L } else { 2147483647L }
  if digits == 0 ||
    (radix == 10 && value > decimal_limit) ||
    (negative && value > 2147483648L) {
    reject("invalid_literal", "Signed Int32 literal is out of range", loc)
  }
  (if negative {
    -value
  } else if radix != 10 && value > 2147483647L {
    value - 4294967296L
  } else {
    value
  }).to_string()
}
