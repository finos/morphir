///|
/// Decode the pinned lexer's literal payload. Surrogate escapes are not scalars.
fn library_cook_string(repr : String, loc : @location.Location) -> String raise {
  let chars = repr.to_array()
  let output = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    if c != '\\' {
      output.write_char(c)
      continue
    }
    if i >= chars.length() {
      reject("invalid_string_literal", "Incomplete escape", loc)
    }
    let escape = chars[i]
    i += 1
    match escape {
      'n' => output.write_char('\n')
      't' => output.write_char('\t')
      'b' => output.write_char('\b')
      'r' => output.write_char('\r')
      'f' => output.write_char('\u{c}')
      '\\' | '"' | '\'' | '`' | '/' | ' ' => output.write_char(escape)
      'u' | 'x' | 'o' => {
        let braced = escape == 'u' && i < chars.length() && chars[i] == '{'
        if braced {
          i += 1
        }
        let digits = if escape == 'x' {
          2
        } else if escape == 'o' {
          3
        } else {
          4
        }
        let radix = if escape == 'o' { 8 } else { 16 }
        let mut code = 0
        let mut count = 0
        while i < chars.length() &&
              (if braced { chars[i] != '}' } else { count < digits }) {
          let n = chars[i].to_int()
          let digit = if n >= 48 && n <= 57 {
            n - 48
          } else if n >= 65 && n <= 70 {
            n - 55
          } else if n >= 97 && n <= 102 {
            n - 87
          } else {
            -1
          }
          if digit < 0 || digit >= radix || code > (1114111 - digit) / radix {
            reject(
              "invalid_string_literal", "Escape is outside the Unicode scalar range",
              loc,
            )
          }
          code = code * radix + digit
          i += 1
          count += 1
        }
        if count == 0 ||
          (!braced && count != digits) ||
          (braced && (i >= chars.length() || chars[i] != '}')) {
          reject("invalid_string_literal", "Incomplete numeric escape", loc)
        }
        if braced {
          i += 1
        }
        guard code.to_char() is Some(character) &&
          !(code >= 55296 && code <= 57343) else {
          reject(
            "invalid_string_literal", "Surrogate escapes are not MoonBit Unicode scalars",
            loc,
          )
          abort("unreachable")
        }
        output.write_char(character)
      }
      _ => reject("invalid_string_literal", "Unsupported escape", loc)
    }
  }
  output.to_string()
}
