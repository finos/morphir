///|
fn first_code(value : @sdk.Character) -> Int32 {
  let source = value.to_units()
  if source.length() == 0 {
    return -1
  }
  let first = source[0].to_int()
  if source.length() > 1 &&
    source[0].is_leading_surrogate() &&
    source[1].is_trailing_surrogate() {
    65536 + (first - 55296) * 1024 + source[1].to_int() - 56320
  } else {
    first
  }
}

///|
/// Elm Char classification uses ASCII ranges.
pub fn is_upper(value : @sdk.Character) -> Bool {
  let n = first_code(value)
  n >= 65 && n <= 90
}

///|
pub fn is_lower(value : @sdk.Character) -> Bool {
  let n = first_code(value)
  n >= 97 && n <= 122
}

///|
pub fn is_alpha(value : @sdk.Character) -> Bool {
  is_upper(value) || is_lower(value)
}

///|
pub fn is_alpha_num(value : @sdk.Character) -> Bool {
  is_alpha(value) || is_digit(value)
}

///|
pub fn is_digit(value : @sdk.Character) -> Bool {
  let n = first_code(value)
  n >= 48 && n <= 57
}

///|
pub fn is_oct_digit(value : @sdk.Character) -> Bool {
  let n = first_code(value)
  n >= 48 && n <= 55
}

///|
pub fn is_hex_digit(value : @sdk.Character) -> Bool {
  let n = first_code(value)
  (n >= 48 && n <= 57) || (n >= 65 && n <= 70) || (n >= 97 && n <= 102)
}

///|
pub fn to_upper(value : @sdk.Character) -> @sdk.Character {
  @sdk.Character::from_text(@text.to_upper(value.to_text()))
}

///|
pub fn to_lower(value : @sdk.Character) -> @sdk.Character {
  @sdk.Character::from_text(@text.to_lower(value.to_text()))
}

///|
/// Locale-independent casing is portable across SDK targets.
pub fn to_locale_upper(value : @sdk.Character) -> @sdk.Character {
  to_upper(value)
}

///|
pub fn to_locale_lower(value : @sdk.Character) -> @sdk.Character {
  to_lower(value)
}

///|
pub fn to_code(value : @sdk.Character) -> @integer.Integer {
  @integer.from_int(first_code(value))
}

///|
/// Elm Char.fromCode replaces values outside the Unicode range with U+FFFD.
pub fn from_code(value : @integer.Integer) -> @sdk.Character {
  match @integer.to_int(value) {
    Some(code) => {
      if code < 0 || code > 1114111 {
        return @sdk.Character::from_char('�')
      }
      if code >= 55296 && code <= 57343 {
        return @sdk.Character::from_units([code.to_uint16()])
      }
      match code.to_char() {
        Some(character) => @sdk.Character::from_char(character)
        None => @sdk.Character::from_char('�')
      }
    }
    None => @sdk.Character::from_char('�')
  }
}
