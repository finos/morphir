///|
pub(all) struct Located {
  datum : Datum
  start : Int32
  children : Array[Located]
} derive(Eq, Debug)

///|
pub extend Located with Eq::{equal, not_equal}

///|
pub extend Located with @debug.Debug::{to_repr}

///|
priv struct Reader {
  chars : Array[Char]
  mut index : Int32
  // Pre-order start offsets of every datum read, when recording.
  record : Array[Int32]?
}

///|
fn delimiter(c : Char) -> Bool {
  c == ' ' ||
  c == '\n' ||
  c == '\r' ||
  c == '\t' ||
  c == '(' ||
  c == ')' ||
  c == '[' ||
  c == ']' ||
  c == ';' ||
  c == '`' ||
  c == ',' ||
  c == '\'' ||
  c == '"'
}

///|
fn Reader::starts(self : Reader, a : Char, b : Char) -> Bool {
  self.index + 1 < self.chars.length() &&
  self.chars[self.index] == a &&
  self.chars[self.index + 1] == b
}

///|
fn Reader::skip(self : Reader, depth : Int32) -> Unit raise {
  while self.index < self.chars.length() {
    let c = self.chars[self.index]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.index += 1
    } else if c == ';' {
      while self.index < self.chars.length() && self.chars[self.index] != '\n' {
        self.index += 1
      }
    } else if self.starts('#', '|') {
      self.index += 2
      let mut nesting = 1
      while nesting > 0 {
        if self.index >= self.chars.length() {
          raise Syntax("Unclosed block comment", self.index)
        }
        if self.starts('#', '|') {
          nesting += 1
          self.index += 2
        } else if self.starts('|', '#') {
          nesting -= 1
          self.index += 2
        } else {
          self.index += 1
        }
      }
    } else if self.starts('#', ';') {
      self.index += 2
      let mark = match self.record {
        Some(r) => r.length()
        None => 0
      }
      ignore(self.read(depth + 1))
      if self.record is Some(r) {
        r.truncate(mark)
      }
    } else {
      break
    }
  }
}

///|
fn Reader::quoted(self : Reader, terminator : Char) -> String raise SchemeError {
  self.index += 1
  let output : Array[Char] = []
  while self.index < self.chars.length() {
    let c = self.chars[self.index]
    self.index += 1
    if c == terminator {
      return String::from_array(output)
    }
    if c == '\\' {
      if self.index >= self.chars.length() {
        raise Syntax("Unclosed escape", self.index)
      }
      let escape = self.chars[self.index]
      self.index += 1
      output.push(
        match escape {
          'n' => '\n'
          'r' => '\r'
          't' => '\t'
          '\\' => '\\'
          '"' => '"'
          '|' => '|'
          _ => raise Syntax("Unsupported escape", self.index)
        },
      )
    } else {
      output.push(c)
    }
  }
  raise Syntax("Unclosed quoted text", self.index)
}

///|
fn Reader::token(self : Reader) -> String {
  let start = self.index
  while self.index < self.chars.length() && !delimiter(self.chars[self.index]) {
    self.index += 1
  }
  String::from_array(self.chars[start:self.index])
}

///|
fn Reader::read(self : Reader, depth : Int32) -> Datum raise {
  if depth > 256 {
    raise Syntax("Reader nesting limit", self.index)
  }
  self.skip(depth)
  if self.index == self.chars.length() {
    raise Syntax("Expected datum", self.index)
  }
  if self.record is Some(r) {
    r.push(self.index)
  }
  let c = self.chars[self.index]
  if c == '(' || c == '[' {
    let close = if c == '(' { ')' } else { ']' }
    self.index += 1
    let items : Array[Datum] = []
    for ;; {
      self.skip(depth)
      if self.index >= self.chars.length() {
        raise Syntax("Unclosed list", self.index)
      }
      if self.chars[self.index] == close {
        self.index += 1
        return Sequence(items, None)
      }
      if self.chars[self.index] == '.' &&
        (
          self.index + 1 == self.chars.length() ||
          delimiter(self.chars[self.index + 1])
        ) {
        if items.is_empty() {
          raise Syntax("Dot requires a head", self.index)
        }
        self.index += 1
        let tail = self.read(depth + 1)
        self.skip(depth)
        if self.index >= self.chars.length() || self.chars[self.index] != close {
          raise Syntax("Expected closing delimiter after tail", self.index)
        }
        self.index += 1
        return Sequence(items, Some(tail))
      }
      items.push(self.read(depth + 1))
    }
  }
  if c == ')' || c == ']' {
    raise Syntax("Unexpected closing delimiter", self.index)
  }
  if c == '\'' {
    if self.record is Some(r) {
      r.push(self.index)
    }
    self.index += 1
    return Sequence([Symbol("quote"), self.read(depth + 1)], None)
  }
  if c == '`' || c == ',' {
    raise Unsupported("Quasiquotation is not in the Morphir Scheme core")
  }
  if c == '"' {
    return Text(self.quoted('"'))
  }
  if c == '|' {
    return Symbol(self.quoted('|'))
  }
  if self.starts('#', '(') {
    self.index += 1
    // The inner list records its own start; drop it so the vector keeps the `#` offset.
    let inner = match self.record {
      Some(r) => r.length()
      None => 0
    }
    let list = self.read(depth + 1)
    if self.record is Some(r) {
      r.remove(inner) |> ignore
    }
    return match list {
      Sequence(items, None) => Vector(items)
      _ => raise Syntax("Invalid vector", self.index)
    }
  }
  if self.starts('#', '\\') {
    self.index += 2
    if self.index >= self.chars.length() {
      raise Syntax("Expected character", self.index)
    }
    let token = if delimiter(self.chars[self.index]) {
      let character = self.chars[self.index]
      self.index += 1
      character.to_string()
    } else {
      self.token()
    }
    let character = match token {
      "space" => ' '
      "newline" => '\n'
      "tab" => '\t'
      "return" => '\r'
      _ => {
        let chars = token.iter().collect()
        if chars.length() != 1 {
          raise Syntax("Expected one character", self.index)
        }
        chars[0]
      }
    }
    return Character(character)
  }
  let token = self.token()
  if token == "#t" || token == "#true" {
    return Boolean(true)
  }
  if token == "#f" || token == "#false" {
    return Boolean(false)
  }
  if parse_number(token) is Some(number) {
    return Number(number)
  }
  if token.is_empty() || token.has_prefix("#") {
    raise Syntax("Unknown reader token: " + token, self.index)
  }
  let first = token.iter().collect()[0]
  if first >= '0' && first <= '9' {
    raise Syntax("Invalid numeric token", self.index)
  }
  Symbol(token)
}

///|
pub fn parse_program(source : String) -> Array[Datum] raise {
  let reader = Reader::{
    chars: source.iter().collect(),
    index: 0,
    record: None,
  }
  let forms = []
  reader.skip(0)
  while reader.index < reader.chars.length() {
    forms.push(reader.read(0))
    reader.skip(0)
  }
  forms
}

///|
fn attach(datum : Datum, offsets : Array[Int32], next : Ref[Int32]) -> Located {
  let start = offsets[next.val]
  next.val += 1
  let children = match datum {
    Sequence(items, tail) => {
      let result = items.map(item => attach(item, offsets, next))
      if tail is Some(t) {
        result.push(attach(t, offsets, next))
      }
      result
    }
    Vector(items) => items.map(item => attach(item, offsets, next))
    _ => []
  }
  { datum, start, children, }
}

///|
pub fn parse_program_located(source : String) -> Array[Located] raise {
  let offsets : Array[Int32] = []
  let reader = Reader::{
    chars: source.iter().collect(),
    index: 0,
    record: Some(offsets),
  }
  let forms = []
  reader.skip(0)
  while reader.index < reader.chars.length() {
    forms.push(reader.read(0))
    reader.skip(0)
  }
  let next : Ref[Int32] = { val: 0, }
  forms.map(form => attach(form, offsets, next))
}

///|
pub fn line_column(source : String, offset : Int32) -> (Int32, Int32) {
  let mut line = 1
  let mut column = 1
  for i, c in source.iter().collect() {
    if i >= offset {
      break
    }
    if c == '\n' {
      line += 1
      column = 1
    } else {
      column += 1
    }
  }
  (line, column)
}

///|
pub fn symbol_text(text : String) -> String {
  if !text.is_empty() &&
    !text.iter().any(c => delimiter(c) || c == '|' || c == '\\') &&
    text != "." {
    let is_number = parse_number(text) catch { _ => None }
    if is_number is None &&
      !text.has_prefix("#") &&
      !(text.iter().collect()[0] >= '0' && text.iter().collect()[0] <= '9') {
      return text
    }
  }
  escaped(text, '|')
}

///|
pub fn Datum::to_source(self : Datum) -> String {
  match self {
    Number(n) => n.to_text()
    Boolean(b) => if b { "#t" } else { "#f" }
    Character(c) =>
      "#\\" +
      (match c {
        ' ' => "space"
        '\n' => "newline"
        '\t' => "tab"
        '\r' => "return"
        _ => c.to_string()
      })
    Text(s) => escaped(s, '"')
    Symbol(s) => symbol_text(s)
    Sequence(items, tail) =>
      "(" +
      items.map(Datum::to_source).join(" ") +
      (match tail {
        None => ""
        Some(tail) => " . " + tail.to_source()
      }) +
      ")"
    Vector(items) => "#(" + items.map(Datum::to_source).join(" ") + ")"
  }
}

///|
pub fn quote(datum : Datum) -> Value {
  match datum {
    Number(n) => Number(n)
    Boolean(b) => Boolean(b)
    Character(c) => Character(c)
    Text(s) => Text(s)
    Symbol(s) => Symbol(s)
    Vector(items) => Vector(items.map(quote))
    Sequence(items, tail) => {
      let mut result = match tail {
        None => Nil
        Some(tail) => quote(tail)
      }
      for i = items.length() - 1; i >= 0; i = i - 1 {
        result = Pair(quote(items[i]), result)
      }
      result
    }
  }
}

///|
fn escaped(text : String, terminator : Char) -> String {
  let output : Array[Char] = [terminator]
  for c in text {
    if c == terminator || c == '\\' {
      output.push('\\')
      output.push(c)
    } else if c == '\n' {
      output.push('\\')
      output.push('n')
    } else if c == '\r' {
      output.push('\\')
      output.push('r')
    } else if c == '\t' {
      output.push('\\')
      output.push('t')
    } else {
      output.push(c)
    }
  }
  output.push(terminator)
  String::from_array(output)
}
