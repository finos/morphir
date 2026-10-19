///|
/// Scanner buffers check UTF-16 units before every append, including temporary
/// buffers used while folding block and quoted scalars.
priv struct ScalarBuffer {
  builder : StringBuilder
  limit : Int32
  mut units : Int32
}

///|
fn ScalarBuffer::new(limit : Int32) -> ScalarBuffer {
  { builder: StringBuilder(), limit, units: 0, }
}

///|
fn ScalarBuffer::reserve(
  self : ScalarBuffer,
  units : Int32,
) -> Unit raise YamlError {
  guard units <= self.limit - self.units else {
    raise YamlError(
      mark={ index: 0, line: 1, col: 0, },
      info="yaml_scalar_limit",
    )
  }
  self.units += units
}

///|
fn ScalarBuffer::write_char(
  self : ScalarBuffer,
  value : Char,
) -> Unit raise YamlError {
  self.reserve(if value.to_int() > 65535 { 2 } else { 1 })
  self.builder.write_char(value)
}

///|
fn ScalarBuffer::write_string(
  self : ScalarBuffer,
  value : String,
) -> Unit raise YamlError {
  self.reserve(value.length())
  self.builder.write_string(value)
}

///|
fn ScalarBuffer::write_stringview(
  self : ScalarBuffer,
  value : StringView,
) -> Unit raise YamlError {
  self.reserve(value.length())
  self.builder.write_stringview(value)
}

///|
fn ScalarBuffer::reset(self : ScalarBuffer) -> Unit {
  self.units = 0
  self.builder.reset()
}

///|
fn ScalarBuffer::is_empty(self : ScalarBuffer) -> Bool {
  self.units == 0
}

///|
fn ScalarBuffer::to_string(self : ScalarBuffer) -> String {
  self.builder.to_string()
}

///|
fn Lexer::charge_token(self : Lexer) -> Unit raise YamlError {
  guard self.produced_tokens < self.token_limit else {
    raise YamlError(mark=self.get_marker(), info="yaml_token_limit")
  }
  self.produced_tokens += 1
}

///|
fn Lexer::push_token(self : Lexer, token : Token) -> Unit raise YamlError {
  self.charge_token()
  self.tokens.push_back(token)
}

///|
fn Lexer::check_nesting(self : Lexer) -> Unit raise YamlError {
  guard self.simple_keys.length() <= self.nesting_limit &&
    self.indents.length() <= self.nesting_limit else {
    raise YamlError(mark=self.get_marker(), info="yaml_depth_limit")
  }
}

///|
/// Pulling lets the profile refuse an event before requesting further work.
pub fn Parser::next_event(self : Parser) -> (Event, Marker) raise YamlError {
  self.next_token()
}

///|
pub fn Parser::bounded(
  source : StringView,
  max_depth~ : Int32,
  max_tokens~ : Int32,
  max_scalar_units~ : Int32,
) -> Parser {
  let parser = Parser::Parser(source)
  parser.lexer.nesting_limit = max_depth
  parser.lexer.token_limit = max_tokens
  parser.lexer.scalar_limit = max_scalar_units
  parser
}
