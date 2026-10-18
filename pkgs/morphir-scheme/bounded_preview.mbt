///|
priv struct PreviewWriter {
  output : StringBuilder
  mut remaining : Int32
  mut steps : Int32
  mut stopped : Bool
}

///|
fn PreviewWriter::tick(self : PreviewWriter) -> Unit raise SchemeError {
  self.steps -= 1
  if self.steps < 0 {
    raise Limit("value preview traversal")
  }
}

///|
fn PreviewWriter::character(
  self : PreviewWriter,
  character : Char,
) -> Unit raise SchemeError {
  if self.stopped {
    return
  }
  self.tick()
  let units = if character.to_int() > 65535 { 2 } else { 1 }
  if units > self.remaining {
    self.stopped = true
    return
  }
  self.output.write_char(character)
  self.remaining -= units
  if self.remaining == 0 {
    self.stopped = true
  }
}

///|
fn PreviewWriter::text(
  self : PreviewWriter,
  text : String,
) -> Unit raise SchemeError {
  for character in text {
    if self.stopped {
      break
    }
    self.character(character)
  }
}

///|
fn PreviewWriter::quoted(
  self : PreviewWriter,
  text : String,
  terminator : Char,
) -> Unit raise SchemeError {
  self.character(terminator)
  for character in text {
    if self.stopped {
      break
    }
    if character == terminator || character == '\\' {
      self.character('\\')
      self.character(character)
    } else if character == '\n' {
      self.text("\\n")
    } else if character == '\r' {
      self.text("\\r")
    } else if character == '\t' {
      self.text("\\t")
    } else {
      self.character(character)
    }
  }
  self.character(terminator)
}

///|
fn PreviewWriter::symbol(
  self : PreviewWriter,
  text : String,
) -> Unit raise SchemeError {
  let mut plain = !text.is_empty() && text != "."
  if plain {
    for character in text {
      self.tick()
      if delimiter(character) || character == '|' || character == '\\' {
        plain = false
        break
      }
    }
  }
  if plain {
    let first = text.iter().next().unwrap()
    if first == '#' || (first >= '0' && first <= '9') {
      plain = false
    } else if first == '+' || first == '-' || first == '.' {
      // A number-like identifier needs classification before emitting its first
      // character. Bound this lookahead instead of constructing a huge BigInt.
      if text.length() > 10000 {
        raise Limit("value preview numeric atom")
      }
      let parsed = parse_number(text) catch { _ => None }
      if parsed is Some(_) {
        plain = false
      }
    }
  }
  if plain {
    self.text(text)
  } else {
    self.quoted(text, '|')
  }
}

///|
fn PreviewWriter::number(
  self : PreviewWriter,
  number : Number,
) -> Unit raise SchemeError {
  match number {
    Integer(value) =>
      if value.bit_length() > 65536 {
        raise Limit("value preview numeric atom")
      }
    Rational(numerator, denominator) =>
      if numerator.bit_length() > 65536 || denominator.bit_length() > 65536 {
        raise Limit("value preview numeric atom")
      }
    Real(_) => ()
  }
  self.text(number.to_text())
}

///|
fn PreviewWriter::value(
  self : PreviewWriter,
  value : Value,
  depth : Int32,
) -> Unit raise SchemeError {
  if self.stopped {
    return
  }
  self.tick()
  if depth > 256 {
    raise Limit("value printing depth")
  }
  match value {
    Number(number) => self.number(number)
    Boolean(value) => self.text(if value { "#t" } else { "#f" })
    Character(character) => {
      self.text("#\\")
      match character {
        ' ' => self.text("space")
        '\n' => self.text("newline")
        '\t' => self.text("tab")
        '\r' => self.text("return")
        _ => self.character(character)
      }
    }
    Text(text) => self.quoted(text, '"')
    Symbol(text) => self.symbol(text)
    Nil => self.text("()")
    Pair(_, _) => {
      self.text("(")
      let mut rest = value
      let mut first = true
      while rest is Pair(head, tail) {
        if self.stopped {
          return
        }
        self.tick()
        if !first {
          self.text(" ")
        }
        self.value(head, depth + 1)
        first = false
        rest = tail
      }
      match rest {
        Nil => ()
        _ => {
          self.text(" . ")
          self.value(rest, depth + 1)
        }
      }
      self.text(")")
    }
    Vector(items) => {
      self.text("#(")
      for index, item in items {
        if self.stopped {
          return
        }
        if index > 0 {
          self.text(" ")
        }
        self.value(item, depth + 1)
      }
      self.text(")")
    }
    Record(fields) => {
      self.text("#<record ")
      let mut first = true
      for name, value in fields {
        if self.stopped {
          return
        }
        self.tick()
        if !first {
          self.text(" ")
        }
        self.text(name)
        self.text("=")
        self.value(value, depth + 1)
        first = false
      }
      self.text(">")
    }
    Tagged(tag, items) => {
      self.text("#<")
      self.text(tag)
      self.text(" ")
      for index, item in items {
        if self.stopped {
          return
        }
        if index > 0 {
          self.text(" ")
        }
        self.value(item, depth + 1)
      }
      self.text(">")
    }
    Unit => self.text("#<unit>")
    Closure(_) | Native(_) | NativeFunction(_) => self.text("#<procedure>")
    IR(_) => self.text("#<morphir-value>")
    IRType(_) => self.text("#<morphir-type>")
    IRFile(_) => self.text("#<morphir-file>")
  }
}

///|
/// Return a UTF-16-safe prefix of the existing value printer without expanding
/// the rest of a composite value. Limits are 0..65536 units, depth 256 and
/// 100000 traversal steps. Excessive lookahead or numeric atoms raise Limit.
pub fn value_preview(
  value : Value,
  max_units : Int32,
) -> String raise SchemeError {
  if max_units < 0 || max_units > 65536 {
    raise Invalid("Value preview limit must be between 0 and 65536")
  }
  let writer = PreviewWriter::{
    output: StringBuilder(),
    remaining: max_units,
    steps: 100000,
    stopped: max_units == 0,
  }
  writer.value(value, 0)
  writer.output.to_string()
}

///|
// Diagnostic arguments share one streaming budget, including separators. Never
// fully render an argument before limiting the aggregate error detail.
fn error_arguments_preview(
  arguments : Array[Value],
) -> String raise SchemeError {
  let writer = PreviewWriter::{
    output: StringBuilder(),
    remaining: 4096,
    steps: 100000,
    stopped: false,
  }
  for index, argument in arguments {
    if writer.stopped {
      break
    }
    if index > 0 {
      writer.text(" ")
    }
    writer.value(argument, 0)
  }
  writer.output.to_string()
}
