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

///|
/// The lexer chooses the suffix family. Reconstruct the exact integer from
/// digits so neither the host Int64 nor a floating value can truncate it.
fn library_integer_literal(
  raw : String,
  scalar : LibraryScalar,
  loc : @location.Location,
) -> String raise FrontendError {
  if scalar == SignedInt32 {
    return library_int32_literal(raw, loc)
  }
  let suffix = match scalar {
    SignedInt64 => "L"
    UnsignedInt32 => "U"
    UnsignedInt64 => "UL"
    UnboundedInteger => "N"
    _ => ""
  }
  let digits_text = if suffix != "" && raw.has_suffix(suffix) {
    raw[:raw.length() - suffix.length()].to_owned()
  } else {
    raw
  }
  let chars = digits_text.to_array()
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
  let mut value = @bigint.BigInt::from_int(0)
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
      reject("invalid_literal", "Invalid integer digit", loc)
    }
    value = value * @bigint.BigInt::from_int(radix) +
      @bigint.BigInt::from_int(digit)
    digits += 1
    if digits > 4096 {
      reject("literal_limit", "Integer literal exceeds the digit budget", loc)
    }
  }
  if digits == 0 || (negative && !scalar.is_signed()) {
    reject("invalid_literal", "Invalid integer literal", loc)
  }
  let bits = scalar.bits()
  if bits != 0 {
    let modulus = @bigint.BigInt::from_int(1) << bits
    let max_unsigned = modulus - @bigint.BigInt::from_int(1)
    if value > max_unsigned {
      reject("invalid_literal", "Integer literal exceeds its source width", loc)
    }
    if scalar.is_signed() {
      let signed_limit = @bigint.BigInt::from_int(1) << (bits - 1)
      if negative {
        if value > signed_limit {
          reject("invalid_literal", "Signed literal is out of range", loc)
        }
        return (-value).to_string()
      }
      if radix == 10 {
        if value >= signed_limit {
          reject("invalid_literal", "Signed literal is out of range", loc)
        }
      } else if value >= signed_limit {
        value = value - modulus
      }
    }
  } else if negative {
    value = -value
  }
  value.to_string()
}
