///|
fn Char::is_break(self : Char) -> Bool {
  self == '\n' || self == '\r'
}

///|
fn Char::is_z(self : Char) -> Bool {
  self == '\u{0}'
}

///|
fn Char::is_breakz(self : Char) -> Bool {
  self.is_break() || self.is_z()
}

///|
fn Char::is_blank(self : Char) -> Bool {
  self == ' ' || self == '\t'
}

///|
fn Char::is_blank_or_breakz(self : Char) -> Bool {
  self.is_blank() || self.is_break() || self.is_z()
}

///|
fn Char::is_alpha(self : Char) -> Bool {
  self is ('0'..<='9') ||
  self is ('a'..<='z') ||
  self is ('A'..<='Z') ||
  self is '_' ||
  self is '-'
}

///|
fn Char::to_digit(self : Char) -> Int32? {
  if self is ('0'..<='9') {
    Some(self.to_int() - 48)
  } else {
    None
  }
}

///|
test {
  @debug.assert_eq('0'.to_digit(), Some(0))
  @debug.assert_eq('9'.to_digit(), Some(9))
  @debug.assert_eq('A'.to_digit(), None)
}

///|
fn Char::is_tag_char(self : Char) -> Bool {
  self.is_uri_char() && !self.is_flow() && self != '!'
}

///|
/// Check whether the character is a YAML flow character (one of `,[]{}`).
fn Char::is_flow(self : Char) -> Bool {
  self == ',' || self == '[' || self == ']' || self == '{' || self == '}'
}

///|
fn Char::is_uri_char(self : Char) -> Bool {
  self.is_word_char() || "#;/?:@&=+$,_.!~*\'()[]%".contains_char(self)
}

///|
fn Char::is_word_char(self : Char) -> Bool {
  self.is_alpha() && self != '_'
}

///|
/// Check whether the character is a hexadecimal character (case insensitive).
fn Char::is_hex(self : Char) -> Bool {
  self.is_ascii_digit() || self is ('a'..<='f') || self is ('A'..<='F')
}

///|
fn Char::as_hex(self : Char) -> Int32 {
  match self {
    '0'..<='9' => (self.to_uint() - '0'.to_uint()).reinterpret_as_int()
    'a'..<='f' => (self.to_uint() - 'a'.to_uint()).reinterpret_as_int() + 10
    'A'..<='F' => (self.to_uint() - 'A'.to_uint()).reinterpret_as_int() + 10
    _ => panic()
  }
}

///|
test {
  @debug.assert_eq('0'.as_hex(), 0)
  @debug.assert_eq('9'.as_hex(), 9)
  @debug.assert_eq('a'.as_hex(), 10)
  @debug.assert_eq('A'.as_hex(), 10)
  @debug.assert_eq('f'.as_hex(), 15)
  @debug.assert_eq('F'.as_hex(), 15)
}

///|
fn Char::is_anchor_char(self : Char) -> Bool {
  self.is_yaml_non_space() && !self.is_flow() && !self.is_z()
}

///|
test {
  assert_true('x'.is_anchor_char())
}

///|
fn Char::is_yaml_non_space(self : Char) -> Bool {
  self.is_yaml_non_break() && !self.is_blank()
}

///|
fn Char::is_yaml_non_break(self : Char) -> Bool {
  !self.is_break() && !self.is_bom()
}

///|
fn Char::is_bom(self : Char) -> Bool {
  self == '\u{FEFF}'
}
