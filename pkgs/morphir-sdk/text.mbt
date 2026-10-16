///|
/// Elm strings contain UTF-16 code units, including isolated surrogates.
/// Copying at the boundary keeps Text immutable to callers.
pub struct Text {
  priv units : Array[UInt16]
} derive(Eq, Debug)

///|
pub fn Text::from_units(units : Array[UInt16]) -> Text {
  { units: units.copy(), }
}

///|
pub fn Text::from_string(value : String) -> Text {
  { units: value.code_units().to_owned(), }
}

///|
pub fn Text::to_units(self : Text) -> Array[UInt16] {
  self.units.copy()
}

///|
pub fn Text::length(self : Text) -> Int32 {
  self.units.length()
}

///|
pub fn Text::to_string(self : Text) -> String raise SdkError {
  let characters : Array[Char] = []
  let mut i = 0
  while i < self.units.length() {
    let first = self.units[i]
    let mut code = first.to_int()
    if first.is_leading_surrogate() {
      if i + 1 >= self.units.length() ||
        !self.units[i + 1].is_trailing_surrogate() {
        raise UnrepresentableText("isolated UTF-16 surrogate")
      }
      code = 65536 +
        (code - 55296) * 1024 +
        (self.units[i + 1].to_int() - 56320)
      i += 1
    } else if first.is_trailing_surrogate() {
      raise UnrepresentableText("isolated UTF-16 surrogate")
    }
    match code.to_char() {
      Some(character) => characters.push(character)
      None => raise UnrepresentableText("invalid UTF-16 code point")
    }
    i += 1
  }
  String::from_array(characters)
}

///|
/// Elm Char can contain a surrogate or a case conversion expansion.
pub struct Character {
  priv text : Text
} derive(Eq, Debug)

///|
pub fn Character::from_units(units : Array[UInt16]) -> Character {
  { text: Text::from_units(units), }
}

///|
pub fn Character::from_char(value : Char) -> Character {
  { text: Text::from_string(value.to_string()), }
}

///|
pub fn Character::from_text(value : Text) -> Character {
  { text: value, }
}

///|
pub fn Character::to_text(self : Character) -> Text {
  self.text
}

///|
pub fn Character::to_units(self : Character) -> Array[UInt16] {
  self.text.to_units()
}

///|
pub fn Character::to_string(self : Character) -> String raise SdkError {
  self.text.to_string()
}

///|
pub extend Text with Eq::{equal, not_equal}

///|
pub extend Text with @debug.Debug::{to_repr}

///|
pub extend Character with Eq::{equal, not_equal}

///|
pub extend Character with @debug.Debug::{to_repr}
