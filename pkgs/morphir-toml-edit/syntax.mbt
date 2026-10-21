///|
/// Locations use zero-based UTF-16 offsets and one-based lines and columns.
pub(all) struct Position {
  offset : Int32
  line : Int32
  column : Int32
} derive(Eq, Debug)

///|
pub(all) enum DiagnosticKind {
  InvalidToml
  UnsupportedDottedKey
  UnsupportedArrayOfTables
  MissingPath
  WrongKind
  InvalidIndex
} derive(Eq, Debug)

///|
pub(all) suberror Diagnostic {
  Diagnostic(DiagnosticKind, String, Position)
} derive(Debug)

///|
priv struct Span {
  start : Int32
  end : Int32
}

///|
/// Source is retained once. Every concrete node references its original span;
/// comments and whitespace remain in the gaps between nodes.
priv enum Value {
  Atom(Span)
  Sequence(Span, Array[Value], Array[Int32])
  Inline(Span, Array[Entry], Array[Int32])
}

///|
priv struct Entry {
  keys : Array[String]
  start : Int32
  value : Value
}

///|
priv enum TableKind {
  Standard
  ArrayOfTables
}

///|
priv enum Statement {
  Assignment(Array[String], Entry)
  Header(Array[String], TableKind, Span)
}

///|
/// Documents are immutable. Editing reparses a candidate before returning it.
pub struct Document {
  priv source : String
  priv statements : Array[Statement]
  priv focus : EditFocus?
}

///|
fn Value::span(self : Value) -> Span {
  match self {
    Atom(s) | Sequence(s, _, _) | Inline(s, _, _) => s
  }
}

///|
fn position(source : String, offset : Int32) -> Position {
  let mut line = 1
  let mut column = 1
  for i = 0; i < offset && i < source.length(); i = i + 1 {
    if source.code_unit_at(i).to_int() == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
  }
  { offset, line, column, }
}

///|
fn problem(
  source : String,
  offset : Int32,
  kind : DiagnosticKind,
  message : String,
) -> Diagnostic {
  Diagnostic(kind, message, position(source, offset))
}

///|
priv struct Parser {
  source : String
  mut pos : Int32
}

///|
fn Parser::peek(self : Parser, ahead~ : Int32 = 0) -> Int32 {
  let i = self.pos + ahead
  if i < self.source.length() {
    self.source.code_unit_at(i).to_int()
  } else {
    -1
  }
}

///|
fn Parser::bad(self : Parser, message : String) -> Unit raise Diagnostic {
  raise problem(self.source, self.pos, InvalidToml, message)
}

///|
fn Parser::expect(self : Parser, c : Int32) -> Unit raise Diagnostic {
  if self.peek() != c {
    self.bad("Expected '" + c.unsafe_to_char().to_string() + "'")
  }
  self.pos += 1
}

///|
fn Parser::spaces(self : Parser) -> Unit {
  while self.peek() == 32 || self.peek() == 9 {
    self.pos += 1
  }
}

///|
fn Parser::newline(self : Parser) -> Unit raise Diagnostic {
  if self.peek() == 13 {
    self.pos += 1
  }
  self.expect(10)
}

///|
fn Parser::comment(self : Parser) -> Unit raise Diagnostic {
  self.expect(35)
  while self.peek() != -1 && self.peek() != 10 && self.peek() != 13 {
    let c = self.peek()
    if (c < 32 && c != 9) || c == 127 {
      self.bad("Control character in comment")
    }
    self.pos += 1
  }
}

///|
fn Parser::trivia(self : Parser) -> Unit raise Diagnostic {
  while true {
    self.spaces()
    match self.peek() {
      35 => self.comment()
      10 | 13 => self.newline()
      _ => break
    }
  }
}

///|
fn hex(c : Int32) -> Int32 {
  if c >= 48 && c <= 57 {
    c - 48
  } else if c >= 65 && c <= 70 {
    c - 55
  } else if c >= 97 && c <= 102 {
    c - 87
  } else {
    -1
  }
}

///|
/// Parse and decode a key or string, while the CST keeps its original spelling.
fn Parser::quoted(
  self : Parser,
  key~ : Bool = false,
) -> String raise Diagnostic {
  let quote = self.peek()
  self.pos += 1
  let multi = !key && self.peek() == quote && self.peek(ahead=1) == quote
  if multi {
    self.pos += 2
    if self.peek() == 10 || self.peek() == 13 {
      self.newline()
    }
  }
  let out = StringBuilder()
  while true {
    let c = self.peek()
    if c == -1 {
      self.bad("Unterminated string")
    }
    if c == quote {
      if !multi {
        self.pos += 1
        return out.to_string()
      }
      let mut n = 0
      while self.peek(ahead=n) == quote {
        n += 1
      }
      if n >= 3 {
        if n > 5 {
          self.bad("Too many closing quotes")
        }
        for i = 3; i < n; i = i + 1 {
          out.write_char(quote.unsafe_to_char())
        }
        self.pos += n
        return out.to_string()
      }
    }
    if c == 92 && quote == 34 {
      self.pos += 1
      let escape = self.peek()
      if multi && (escape == 32 || escape == 9 || escape == 10 || escape == 13) {
        self.spaces()
        self.newline()
        while self.peek() == 32 ||
              self.peek() == 9 ||
              self.peek() == 10 ||
              self.peek() == 13 {
          if self.peek() == 10 || self.peek() == 13 {
            self.newline()
          } else {
            self.pos += 1
          }
        }
        continue
      }
      if escape == -1 {
        self.bad("Unterminated escape")
      }
      self.pos += 1
      match escape {
        98 => out.write_char('\b')
        116 => out.write_char('\t')
        110 => out.write_char('\n')
        102 => out.write_char('\u{000c}')
        114 => out.write_char('\r')
        34 => out.write_char('"')
        92 => out.write_char('\\')
        117 | 85 => {
          let n = if escape == 117 { 4 } else { 8 }
          let mut scalar : Int64 = 0
          for i = 0; i < n; i = i + 1 {
            let h = hex(self.peek())
            if h < 0 {
              self.bad("Invalid Unicode escape")
            }
            scalar = scalar * 16 + h.to_int64()
            self.pos += 1
          }
          if scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff) {
            self.bad("Unicode escape is not a scalar value")
          }
          out.write_char(scalar.to_int().unsafe_to_char())
        }
        _ => self.bad("Invalid string escape")
      }
    } else if multi && (c == 10 || c == 13) {
      self.newline()
      out.write_char('\n')
    } else {
      if (c < 32 && c != 9) || c == 127 {
        self.bad("Control character in string")
      }
      // Copy a complete Unicode scalar, including astral characters.
      if c >= 0xd800 && c <= 0xdbff {
        let low = self.peek(ahead=1)
        if low < 0xdc00 || low > 0xdfff {
          self.bad("Unpaired Unicode surrogate")
        }
        out.write_char(
          (0x10000 + (c - 0xd800) * 1024 + low - 0xdc00).unsafe_to_char(),
        )
        self.pos += 2
      } else {
        if c >= 0xdc00 && c <= 0xdfff {
          self.bad("Unpaired Unicode surrogate")
        }
        out.write_char(c.unsafe_to_char())
        self.pos += 1
      }
    }
  } nobreak {
    abort("unreachable")
  }
}

///|
fn bare(c : Int32) -> Bool {
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  (c >= 48 && c <= 57) ||
  c == 95 ||
  c == 45
}

///|
fn Parser::keys(self : Parser) -> Array[String] raise Diagnostic {
  let keys = []
  while true {
    self.spaces()
    let start = self.pos
    let key = if self.peek() == 34 || self.peek() == 39 {
      self.quoted(key=true)
    } else {
      while bare(self.peek()) {
        self.pos += 1
      }
      if start == self.pos {
        self.bad("Expected a key")
      }
      self.source[start:self.pos].to_owned()
    }
    keys.push(key)
    self.spaces()
    if self.peek() != 46 {
      break
    }
    self.pos += 1
  }
  keys
}

///|
fn Parser::entry(self : Parser) -> Entry raise Diagnostic {
  let start = self.pos
  let keys = self.keys()
  self.expect(61)
  self.spaces()
  let value = self.value()
  { keys, start, value, }
}

///|
fn Parser::value(self : Parser) -> Value raise Diagnostic {
  let start = self.pos
  match self.peek() {
    34 | 39 => {
      ignore(self.quoted())
      Atom({ start, end: self.pos, })
    }
    91 => {
      self.pos += 1
      let values = []
      let commas = []
      self.trivia()
      while self.peek() != 93 {
        values.push(self.value())
        self.trivia()
        if self.peek() != 44 {
          break
        }
        commas.push(self.pos)
        self.pos += 1
        self.trivia()
      }
      self.expect(93)
      Sequence({ start, end: self.pos, }, values, commas)
    }
    123 => {
      self.pos += 1
      let entries = []
      let commas = []
      self.spaces()
      while self.peek() != 125 {
        entries.push(self.entry())
        self.spaces()
        if self.peek() != 44 {
          break
        }
        commas.push(self.pos)
        self.pos += 1
        self.spaces()
        if self.peek() == 125 {
          self.bad("Trailing comma in inline table")
        }
      }
      self.expect(125)
      validate_inline(self.source, entries)
      Inline({ start, end: self.pos, }, entries, commas)
    }
    _ => {
      while true {
        let c = self.peek()
        if c == -1 ||
          c == 9 ||
          c == 10 ||
          c == 13 ||
          c == 35 ||
          c == 44 ||
          c == 93 ||
          c == 125 {
          break
        }
        if c == 32 {
          // RFC 3339 permits a single space between date and time.
          if self.pos - start == 10 &&
            self.peek(ahead=1) >= 48 &&
            self.peek(ahead=1) <= 57 {
            self.pos += 1
            continue
          }
          break
        }
        self.pos += 1
      }
      let token = self.source[start:self.pos].to_owned()
      if !valid_atom(token) {
        self.bad("Invalid TOML value: " + token)
      }
      Atom({ start, end: self.pos, })
    }
  }
}

///|
pub fn parse(source : String) -> Document raise Diagnostic {
  // String callers can supply unpaired UTF-16 surrogates on the JS target.
  let mut i = 0
  while i < source.length() {
    let c = source.code_unit_at(i).to_int()
    if c >= 0xd800 && c <= 0xdbff {
      if i + 1 >= source.length() ||
        source.code_unit_at(i + 1).to_int() < 0xdc00 ||
        source.code_unit_at(i + 1).to_int() > 0xdfff {
        raise problem(source, i, InvalidToml, "Unpaired Unicode surrogate")
      }
      i += 2
    } else {
      if c >= 0xdc00 && c <= 0xdfff {
        raise problem(source, i, InvalidToml, "Unpaired Unicode surrogate")
      }
      i += 1
    }
  }
  let p = Parser::{ source, pos: 0, }
  let statements = []
  let mut table : Array[String] = []
  p.trivia()
  while p.peek() != -1 {
    if p.peek() == 91 {
      let start = p.pos
      p.pos += 1
      let aot = p.peek() == 91
      if aot {
        p.pos += 1
      }
      table = p.keys()
      p.expect(93)
      if aot {
        p.expect(93)
      }
      statements.push(
        Header(table, if aot { ArrayOfTables } else { Standard }, {
          start,
          end: p.pos,
        }),
      )
    } else {
      statements.push(Assignment(table, p.entry()))
    }
    p.spaces()
    if p.peek() == 35 {
      p.comment()
    }
    if p.peek() != -1 {
      p.newline()
    }
    p.trivia()
  }
  validate_document(source, statements)
  { source, statements, focus: None, }
}

///|
pub fn Document::encode(self : Document) -> String {
  self.source
}

///|
/// Strict UTF-8 boundary. No lossy replacement or BOM stripping is performed.
pub fn parse_bytes(bytes : Bytes) -> Document raise Diagnostic {
  let source = @utf8.decode(bytes, ignore_bom=false) catch {
    @utf8.Malformed(rest) => {
      let byte_offset = bytes.length() - rest.length()
      let preceding = @utf8.decode_lossy(bytes[:byte_offset], ignore_bom=false)
      raise problem(
        preceding,
        preceding.length(),
        InvalidToml,
        "Invalid UTF-8 at byte offset \{byte_offset}",
      )
    }
  }
  parse(source)
}

///|
/// Re-encode the unchanged source or the result of localized edits as UTF-8.
pub fn Document::encode_bytes(self : Document) -> Bytes {
  @utf8.encode(self.source)
}

///|
pub extend Position with Eq::{equal, not_equal}

///|
pub extend Position with @debug.Debug::{to_repr}

///|
pub extend DiagnosticKind with Eq::{equal, not_equal}

///|
pub extend DiagnosticKind with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}
