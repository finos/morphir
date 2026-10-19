///|
priv enum TokenType {
  /// The start of the stream. Sent first, before even `TokenType::DocumentStart`.
  StreamStart
  /// The end of the stream, EOF.
  StreamEnd
  /// A YAML version directive `(Major, Minor)`.
  VersionDirective(major~ : Int32, minor~ : Int32)
  /// A YAML tag directive `(Handle, Prefix)` (e.g.: `!!str`, `!foo!bar`, ...).
  TagDirective(handle~ : String, prefix~ : String)
  /// The start of a YAML document (`---`).
  DocumentStart
  /// The end of a YAML document (`...`).
  DocumentEnd
  /// The start of a sequence block.
  ///
  /// Sequence blocks are arrays starting with a `-`.
  BlockSequenceStart
  /// The start of a sequence mapping.
  ///
  /// Sequence mappings are "dictionaries" with "key: value" entries.
  BlockMappingStart
  /// End of the corresponding `BlockSequenceStart` or `BlockMappingStart`.
  BlockEnd
  /// Start of an inline array (`[ a, b ]`).
  FlowSequenceStart
  /// End of an inline array.
  FlowSequenceEnd
  /// Start of an inline mapping (`{ a: b, c: d }`).
  FlowMappingStart
  /// End of an inline mapping.
  FlowMappingEnd
  /// An entry in a block sequence (c.f.: `TokenType::BlockSequenceStart`).
  BlockEntry
  /// An entry in a flow sequence (c.f.: `TokenType::FlowSequenceStart`).
  FlowEntry
  /// A key in a mapping.
  Key
  /// A value in a mapping.
  Value
  /// A reference to an anchor.
  Alias(String)
  /// A YAML anchor (`&`/`*`).
  Anchor(String)
  /// A YAML tag `(Handle, Suffix)` (starting with bangs `!`).
  Tag(handle~ : String, suffix~ : String)
  /// A regular YAML scalar.
  Scalar(TScalarStyle, String)
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv struct Token {
  marker : Marker
  token_type : TokenType
} derive(Debug)

///|
/// A scalar that was parsed and may correspond to a simple key.
///
/// Upon scanning the following yaml:
/// ```yaml
/// a: b
/// ```
/// We do not know that `a` is a key for a map until we have reached the following `:`. For this
/// YAML, we would store `a` as a scalar token in the `Lexer`, but not emit it yet. It would be
/// kept inside the scanner until more context is fetched and we are able to know whether it is a
/// plain scalar or a key.
///
/// For example, see the following 2 yaml documents:
/// ```yaml
/// ---
/// a: b # Here, `a` is a key.
/// ...
/// ---
/// a # Here, `a` is a plain scalar.
/// ...
/// ```
/// An instance of `SimpleKey` is created in the `Lexer` when such ambiguity occurs.
///
/// In both documents, scanning `a` would lead to the creation of a `SimpleKey` with
/// `Self::possible` set to `true`. The token for `a` would be pushed in the `Lexer` but not
/// yet emitted. Instead, more context would be fetched (through `Lexer::fetch_more_tokens`).
///
/// In the first document, upon reaching the `:`, the `SimpleKey` would be inspected and our
/// scalar `a` since it is a possible key, would be "turned" into a key. This is done by prepending
/// a `TokenType::Key` to our scalar token in the `Lexer`. This way, the
/// `crate::parser::Parser` would read the `TokenType::Key` token before the
/// `TokenType::Scalar` token.
///
/// In the second document however, reaching the EOF would stale the `SimpleKey` and no
/// `TokenType::Key` would be emitted by the scanner.
priv struct SimpleKey {
  /// Whether the token this `SimpleKey` refers to may still be a key.
  ///
  /// Sometimes, when we have more context, we notice that what we thought could be a key no
  /// longer can be. In that case, `Self::possible` is set to `false`.
  ///
  /// For instance, let us consider the following invalid YAML:
  /// ```yaml
  /// key
  ///   : value
  /// ```
  /// Upon reading the `\n` after `key`, the `SimpleKey` that was created for `key` is staled
  /// and `Self::possible` set to `false`.
  mut possible : Bool
  /// Whether the token this `SimpleKey` refers to is required to be a key.
  ///
  /// With more context, we may know for sure that the token must be a key. If the YAML is
  /// invalid, it may happen that the token be deemed not a key. In such event, an error has to
  /// be raised. This boolean helps us know when to raise such error.
  ///
  /// TODO(ethiraric, 30/12/2023): Example of when this happens.
  mut required : Bool
  /// The index of the token referred to by the `SimpleKey`.
  ///
  /// This is the index in the scanner, which takes into account both the tokens that have been
  /// emitted and those about to be emitted. See `Lexer::tokens_parsed` and
  /// `Lexer::tokens` for more details.
  mut token_number : Int32
  /// The position at which the token the `SimpleKey` refers to is.
  mark : Marker
}

///|
fn SimpleKey::new(mark : Marker) -> SimpleKey {
  SimpleKey::{ possible: false, required: false, token_number: 0, mark, }
}

///|
fn SimpleKey::clone(self : SimpleKey) -> SimpleKey {
  SimpleKey::{
    possible: self.possible,
    required: self.required,
    token_number: self.token_number,
    mark: self.mark,
  }
}

///|
/// An indentation level on the stack of indentations.
priv struct Indent {
  /// The former indentation level.
  indent : Int32
  /// Whether, upon closing, this indents generates a `BlockEnd` token.
  ///
  /// There are levels of indentation which do not start a block. Examples of this would be:
  /// ```yaml
  /// -
  ///   foo # ok
  /// -
  /// bar # ko, bar needs to be indented further than the `-`.
  /// - [
  ///  baz, # ok
  /// quux # ko, quux needs to be indented further than the '-'.
  /// ] # ko, the closing bracket needs to be indented further than the `-`.
  /// ```
  ///
  /// The indentation level created by the `-` is for a single entry in the sequence. Emitting a
  /// `BlockEnd` when this indentation block ends would generate one `BlockEnd` per entry in the
  /// sequence, although we must have exactly one to end the sequence.
  needs_block_end : Bool
}

///|
/// The Yaml Lexer
///
/// This corresponds to the low-level interface when reading YAML, but it also holds sufficient context
/// to be able to disambiguate some of the constructs. It has understanding of indentation and whitespace and is able to
/// generate error messages for some invalid YAML constructs.
priv struct Lexer {
  mut scalar_limit : Int32
  mut nesting_limit : Int32
  mut token_limit : Int32
  mut produced_tokens : Int32
  mut input : StringView
  /// The index (in chars) in the input string.
  mut index : Int32
  /// The line (1-indexed).
  mut line : Int32
  /// The column (1-indexed).
  mut col : Int32
  /// Buffer for tokens to be returned (can hold some temporary tokens that are not yet ready to be returned)
  tokens : @deque.Deque[Token]
  /// Buffer for the next characters to consume.
  buffer : @deque.Deque[Char]
  /// The last error that happened.
  mut error : YamlError?
  /// Whether we have already emitted the `StreamStart` token.
  mut stream_start_produced : Bool
  /// Whether we have already emitted the `StreamEnd` token.
  mut stream_end_produced : Bool
  /// In some flow contexts, the value of a mapping is allowed to be adjacent to the `:`. When it
  /// is, the index at which the `:` may be must be stored in `adjacent_value_allowed_at`.
  mut adjacent_value_allowed_at : Int32
  /// Whether a simple key could potentially start at the current position.
  ///
  /// Simple keys are the opposite of complex keys which are keys starting with `?`.
  mut simple_key_allowed : Bool
  /// A stack of potential simple keys.
  ///
  /// Refer to the documentation of `SimpleKey` for a more in-depth explanation of what they
  /// are.
  simple_keys : Array[SimpleKey]
  /// The current indentation level.
  mut indent : Int32
  /// List of all block indentation levels we are in (except the current one).
  indents : Array[Indent]
  /// Level of nesting of flow sequences.
  mut flow_level : Int32
  /// The number of tokens that have been returned from the scanner.
  ///
  /// This excludes the tokens from `Self::tokens`.
  mut tokens_parsed : Int32
  /// Whether a token is ready to be taken from `Self::tokens`.
  mut token_available : Bool
  /// Whether all characters encountered since the last newline were whitespace.
  mut leading_whitespace : Bool
  /// Whether we started a flow mapping.
  ///
  /// This is used to detect implicit flow mapping starts such as:
  /// ```yaml
  /// [ : foo ] # { null: "foo" }
  /// ```
  mut flow_mapping_started : Bool
  /// Whether we currently are in an implicit flow mapping.
  mut implicit_flow_mapping : Bool
  /// Accept continuation lines of quoted scalars that are not indented enough
  /// (js-yaml compatibility, see `Parser::Parser`).
  mut lenient_quoted_scalar_indentation : Bool
  /// The line on which the last quoted scalar ended, if that line was less
  /// indented than the enclosing block (only possible with
  /// `lenient_quoted_scalar_indentation`), otherwise -1.
  ///
  /// The indentation of that line belongs to the quoted scalar, so the tokens
  /// following the closing quote on it (`,`, `]`, `}`, ... in a flow
  /// collection) are not checked against the indentation either.
  mut deficient_quoted_line : Int32
}

///|
/// The initial size of the buffer in `Lexer` .
///
/// The buffer is pre-allocated to avoid conditions for reallocations each time we
/// consume/push a character. As of now, almost all lookaheads are 4 characters maximum, except:
///   - Escape sequences parsing: some escape codes are 8 characters
///   - Scanning indent in scalars: this looks ahead `indent + 2` characters
///
/// This constant must be set to at least 8. When scanning indent in scalars, the lookahead is done
/// in a single call if and only if the indent is `BUFFER_LEN - 2` or less. If the indent is higher
/// than that, the code will fall back to a loop of lookaheads.
const BUFFER_LEN = 16

///|
fn Lexer::new(input : StringView) -> Lexer {
  Lexer::{
    scalar_limit: 1048576,
    nesting_limit: 128,
    token_limit: 400000,
    produced_tokens: 0,
    input,
    index: 0,
    line: 1,
    col: 0,
    buffer: @deque.Deque([], capacity=BUFFER_LEN),
    tokens: @deque.Deque([], capacity=42),
    error: None,
    stream_start_produced: false,
    stream_end_produced: false,
    adjacent_value_allowed_at: 0,
    simple_key_allowed: true,
    simple_keys: Array(),
    indent: -1,
    indents: Array(),
    flow_level: 0,
    tokens_parsed: 0,
    token_available: false,
    leading_whitespace: true,
    flow_mapping_started: false,
    implicit_flow_mapping: false,
    lenient_quoted_scalar_indentation: false,
    deficient_quoted_line: -1,
  }
}

///|
/// Get the last error that was encountered, if any.
fn Lexer::get_error(self : Lexer) -> YamlError? {
  self.error
}

///|
/// Get current position (`index`, `line`, `col`) as a `Marker`.
fn Lexer::get_marker(self : Lexer) -> Marker {
  Marker::{ index: self.index, line: self.line, col: self.col, }
}

///|
/// Fill `self.buffer` with at least `count` characters.
///
/// The characters that are extracted this way are not consumed but only placed in the buffer.
fn Lexer::lookahead(self : Lexer, count : Int32) -> Unit {
  if self.buffer.length() >= count {
    return
  }
  for _ in 0..<(count - self.buffer.length()) {
    let chr = match self.input {
      "" => '\u{0}'
      [chr, .. rest] => {
        self.input = rest
        chr
      }
    }
    self.buffer.push_back(chr)
  }
}

///|
/// Consume the next character. It is assumed the next character is a blank.
fn Lexer::skip_blank(self : Lexer) -> Unit {
  ignore(self.buffer.pop_front())
  self.index += 1
  self.col += 1
}

///|
/// Consume the next character. It is assumed the next character is not a blank.
fn Lexer::skip_non_blank(self : Lexer) -> Unit {
  ignore(self.buffer.pop_front())
  self.index += 1
  self.col += 1
  self.leading_whitespace = false
}

///|
/// Consume the next n characters. It is assumed none of the next characters are blanks.
fn Lexer::skip_n_non_blank(self : Lexer, n : Int32) -> Unit {
  // ignore(self.buffer.drain(start=0, len=n))
  for _ in 0..<n {
    ignore(self.buffer.pop_front())
  }
  self.index += n
  self.col += n
  self.leading_whitespace = false
}

///|
/// Consume the next character. It is assumed the next character is a newline.
fn Lexer::skip_newline(self : Lexer) -> Unit {
  ignore(self.buffer.pop_front())
  self.index += 1
  self.line += 1
  self.col = 0
  self.leading_whitespace = true
}

///|
/// Consume a linebreak (either CR, LF or CRLF), if any. Do nothing if there's none.
fn Lexer::skip_linebreak(self : Lexer) -> Unit {
  if self.buffer.length() > 2 &&
    self.buffer[0] == '\r' &&
    self.buffer[1] == '\n' {
    // CRLF
    self.skip_blank()
    self.skip_newline()
  } else if self.buffer.length() > 0 && self.buffer[0].is_break() {
    // CR or LF
    self.skip_newline()
  }
}

///|
/// Return the next character in the buffer.
///
/// The character is not consumed.
fn Lexer::char(self : Lexer) -> Char {
  self.buffer[0]
}

///|
/// Look for the next character and return it.
///
/// The character is not consumed.
fn Lexer::look_char(self : Lexer) -> Char {
  self.lookahead(1)
  self.buffer[0]
}

///|
/// Read a character from the input, returning it directly.
///
/// The buffer is bypassed and `self.{index, line, col}` needs to be updated manually.
fn Lexer::raw_read_char(self : Lexer) -> Char {
  match self.input {
    "" => '\u{0}'
    [chr, .. rest] => {
      self.input = rest
      chr
    }
  }
}

///|
/// Return whether the next character is `c`.
fn Lexer::char_is(self : Lexer, c : Char) -> Bool {
  self.buffer[0] == c
}

///|
/// Return whether the `TokenType::StreamEnd` event has been emitted.
fn Lexer::stream_ended(self : Lexer) -> Bool {
  self.stream_end_produced
}

///|
/// Return whether the `TokenType::StreamStart` event has been emitted
fn Lexer::stream_started(self : Lexer) -> Bool {
  self.stream_start_produced
}

///|
/// Read and consume a line break (either `\r`, `\n` or `\r\n`).
///
/// A `\n` is pushed into `s`.
fn Lexer::read_break(self : Lexer, buf : ScalarBuffer) -> Unit raise YamlError {
  let c = self.buffer[0]
  let nc = self.buffer[1]
  // guard c.is_break()
  if c == '\r' && nc == '\n' {
    self.skip_blank()
  }
  self.skip_newline()
  buf.write_char('\n')
}

///|
/// Check whether the next characters correspond to an end of document.
///
/// `Self::lookahead` must have been called before calling this function.
fn Lexer::next_is_document_end(self : Lexer) -> Bool {
  guard! self.buffer.length() >= 4
  self.buffer[0] == '.' &&
  self.buffer[1] == '.' &&
  self.buffer[2] == '.' &&
  self.buffer[3].is_blank_or_breakz()
}

///|
/// Check whether the next characters correspond to a document indicator.
///
/// `Self::lookahead` must have been called before calling this function.
fn Lexer::next_is_document_indicator(self : Lexer) -> Bool {
  guard! self.buffer.length() >= 4
  self.col == 0 &&
  (
    (self.buffer[0] == '-' && self.buffer[1] == '-' && self.buffer[2] == '-') ||
    (self.buffer[0] == '.' && self.buffer[1] == '.' && self.buffer[2] == '.')
  ) &&
  self.buffer[3].is_blank_or_breakz()
}

///|
/// Insert a token at the given position.
fn Lexer::insert_token(
  self : Lexer,
  pos : Int32,
  token : Token,
) -> Unit raise YamlError {
  self.charge_token()
  guard! pos <= self.tokens.length()
  self.tokens.insert(pos, token)
}

///|
fn Lexer::allow_simple_key(self : Lexer) -> Unit {
  self.simple_key_allowed = true
}

///|
fn Lexer::disallow_simple_key(self : Lexer) -> Unit {
  self.simple_key_allowed = false
}

///|
fn Lexer::next(self : Lexer) -> Token? {
  if self.error is Some(_) {
    return None
  }
  let tok = self.next_token() catch {
    YamlError(_) as err => {
      self.error = Some(err)
      return None
    }
  }
  return tok
}

///|
/// Fetch the next token in the stream.
/// Returns `YamlError` when the scanner does not find the next expected token.
fn Lexer::fetch_next_token(self : Lexer) -> Unit raise YamlError {
  self.lookahead(1)
  if !self.stream_start_produced {
    self.fetch_stream_start()
    return
  }
  self.skip_to_next_token()
  self.stale_simple_keys()
  let mark = self.get_marker()
  self.unroll_indent(mark.col)
  self.lookahead(4)
  if self.char().is_z() {
    self.fetch_stream_end()
    return
  }

  // Refuse profile features before scanning or registering their payload.
  if self.char() is ('&' | '*' | '!') || (self.col == 0 && self.char_is('%')) {
    raise YamlError(mark=self.get_marker(), info="unsupported_yaml_feature")
  }
  // Is it a directive?
  if self.col == 0 && self.char_is('%') {
    return self.fetch_directive()
  }
  if self.col == 0 &&
    self.buffer[0] == '-' &&
    self.buffer[1] == '-' &&
    self.buffer[2] == '-' &&
    self.buffer[3].is_blank_or_breakz() {
    self.fetch_document_indicator(TokenType::DocumentStart)
    return
  }
  if self.col == 0 &&
    self.buffer[0] == '.' &&
    self.buffer[1] == '.' &&
    self.buffer[2] == '.' &&
    self.buffer[3].is_blank_or_breakz() {
    self.fetch_document_indicator(TokenType::DocumentEnd)
    ignore(self.skip_ws_to_eol(SkipTabs::Yes))
    if !self.char().is_breakz() {
      raise YamlError::YamlError(
        mark=self.get_marker(),
        info="invalid content after document end marker",
      )
    }
    return
  }
  if self.is_below_indent(self.indent) {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="invalid indentation",
    )
  }
  let c = self.buffer[0]
  let nc = self.buffer[1]
  match c {
    '[' => self.fetch_flow_collection_start(TokenType::FlowSequenceStart)
    '{' => self.fetch_flow_collection_start(TokenType::FlowMappingStart)
    ']' => self.fetch_flow_collection_end(TokenType::FlowSequenceEnd)
    '}' => self.fetch_flow_collection_end(TokenType::FlowMappingEnd)
    ',' => self.fetch_flow_entry()
    '-' if nc.is_blank_or_breakz() => self.fetch_block_entry()
    '?' if nc.is_blank_or_breakz() => self.fetch_key()
    ':' if nc.is_blank_or_breakz() ||
      (
        self.flow_level > 0 &&
        (nc.is_flow() || self.index == self.adjacent_value_allowed_at)
      ) => self.fetch_value()
    // Is it an alias?
    '*' => self.fetch_anchor(true)
    // Is it an anchor?
    '&' => self.fetch_anchor(false)
    '!' => self.fetch_tag()
    // Is it a literal scalar?
    '|' if self.flow_level == 0 => self.fetch_block_scalar(true)
    // Is it a folded scalar?
    '>' if self.flow_level == 0 => self.fetch_block_scalar(false)
    '\'' => self.fetch_flow_scalar(true)
    '"' => self.fetch_flow_scalar(false)
    // plain scalar
    '-' if nc.is_blank_or_breakz() => self.fetch_plain_scalar()
    ':' | '?' if nc.is_blank_or_breakz() && self.flow_level == 0 =>
      self.fetch_plain_scalar()
    '%' | '@' | '`' =>
      raise YamlError::YamlError(
        mark=self.get_marker(),
        info="unexpected character: \{c}",
      )
    _ => self.fetch_plain_scalar()
  }
}

///|
/// Whether a token starting at the current position is indented less than
/// `indent`.
///
/// The rest of a line on which a quoted scalar ended with a deficient
/// indentation (see `Lexer::deficient_quoted_line`) is exempt: the
/// indentation of that line was already accepted as part of the scalar.
fn Lexer::is_below_indent(self : Lexer, indent : Int32) -> Bool {
  self.col < indent && self.line != self.deficient_quoted_line
}

///|
fn Lexer::fetch_stream_start(self : Lexer) -> Unit raise YamlError {
  let mark = self.get_marker()
  self.indent = -1
  self.stream_start_produced = true
  self.allow_simple_key()
  self.push_token(Token::{ marker: mark, token_type: TokenType::StreamStart, })
  self.check_nesting()
  self.simple_keys.push(SimpleKey::new(Marker::{ index: 0, line: 0, col: 0, }))
}

///|
/// Return the next token in the stream.
/// # Errors
/// Returns `YamlError` when scanning fails to find an expected next token.
fn Lexer::next_token(self : Lexer) -> Token? raise YamlError {
  if self.stream_end_produced {
    return None
  }
  if !self.token_available {
    self.fetch_more_tokens()
  }
  guard self.tokens.pop_front() is Some(t) else {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="did not find expected next token",
    )
  }
  self.token_available = false
  self.tokens_parsed += 1
  if t.token_type == TokenType::StreamEnd {
    self.stream_end_produced = true
  }
  Some(t)
}

///|
/// Return the next token in the stream.
/// # Errors
/// Returns `YamlError` when scanning fails to find an expected next token.
fn Lexer::fetch_more_tokens(self : Lexer) -> Unit raise YamlError {
  let mut need_more = false
  while true {
    if self.tokens.is_empty() {
      need_more = true
    } else {
      need_more = false
      // Stale potential keys that we know won't be keys.
      self.stale_simple_keys()
      // If our next token to be emitted may be a key, fetch more context.
      for sk in self.simple_keys {
        if sk.possible && sk.token_number == self.tokens_parsed {
          need_more = true
          break
        }
      }
    }
    if !need_more {
      break
    }
    self.fetch_next_token()
  }
  self.token_available = true
}

///|
fn Lexer::fetch_plain_scalar(self : Lexer) -> Unit raise YamlError {
  self.save_simple_key()
  self.disallow_simple_key()
  let tok = self.scan_plain_scalar()
  self.push_token(tok)
}

///|
/// Scan for a plain scalar.
///
/// Plain scalars are the most readable but restricted style. They may span multiple lines in
/// some contexts.
fn Lexer::scan_plain_scalar(self : Lexer) -> Token raise YamlError {
  self.unroll_non_block_indents()
  let indent = self.indent + 1
  let start_mark = self.get_marker()
  if self.flow_level > 0 && self.is_below_indent(indent) {
    raise YamlError::YamlError(
      mark=start_mark,
      info="invalid indentation in flow construct",
    )
  }
  let buf = ScalarBuffer::new(self.scalar_limit)
  let leading_break = ScalarBuffer::new(self.scalar_limit)
  let trailing_breaks = ScalarBuffer::new(self.scalar_limit)
  let whitespaces = ScalarBuffer::new(self.scalar_limit)
  while true {
    self.lookahead(4)
    if self.next_is_document_indicator() || self.char() == '#' {
      break
    }
    if self.flow_level > 0 && self.char() == '-' && self.buffer[1].is_flow() {
      raise YamlError::YamlError(
        mark=self.get_marker(),
        info="plain scalar cannot start with '-' followed by ,[]{}",
      )
    }
    if !self.char().is_blank_or_breakz() && self.next_can_be_plain_scalar() {
      if self.leading_whitespace {
        if leading_break.is_empty() {
          buf.write_string(leading_break.to_string())
          buf.write_string(trailing_breaks.to_string())
          trailing_breaks.reset()
          leading_break.reset()
        } else {
          if trailing_breaks.is_empty() {
            buf.write_char(' ')
          } else {
            buf.write_string(trailing_breaks.to_string())
            trailing_breaks.reset()
          }
          leading_break.reset()
        }
        self.leading_whitespace = false
      } else if !whitespaces.is_empty() {
        buf.write_string(whitespaces.to_string())
        whitespaces.reset()
      }

      // We can unroll the first iteration of the loop.
      buf.write_char(self.char())
      self.skip_non_blank()
      self.lookahead(2)

      // Add content non-blank characters to the scalar.
      while !self.char().is_blank_or_breakz() {
        if !self.next_can_be_plain_scalar() {
          break
        }
        buf.write_char(self.char())
        self.skip_non_blank()
        self.lookahead(2)
      }
    }

    // We may reach the end of a plain scalar if:
    //  - We reach eof
    //  - We reach ": "
    //  - We find a flow character in a flow context
    if !(self.char().is_blank() || self.char().is_break()) {
      break
    }

    // Process blank characters.
    while self.look_char().is_blank() || self.char().is_break() {
      if self.char().is_blank() {
        if !self.leading_whitespace {
          whitespaces.write_char(self.char())
          self.skip_blank()
        } else if self.col < indent && self.char() == '\t' {
          // Tabs in an indentation columns are allowed if and only if the line is
          // empty. Skip to the end of the line.
          ignore(self.skip_ws_to_eol(SkipTabs::Yes))
          if !self.char().is_breakz() {
            raise YamlError::YamlError(
              mark=start_mark,
              info="while scanning a plain scalar, found a tab",
            )
          }
        } else {
          self.skip_blank()
        }
      } else {
        self.lookahead(2)
        // Check if it is a first line break
        if self.leading_whitespace {
          self.read_break(trailing_breaks)
        } else {
          whitespaces.reset()
          self.read_break(leading_break)
          self.leading_whitespace = true
        }
      }
    }

    // check indentation level
    if self.flow_level == 0 && self.col < indent {
      break
    }
  }
  if self.leading_whitespace {
    self.allow_simple_key()
  }
  return Token::{
    marker: start_mark,
    token_type: TokenType::Scalar(TScalarStyle::Plain, buf.to_string()),
  }
}

///|
/// Check whether the next characters may be part of a plain scalar.
///
/// This function assumes we are not given a blankz character.
fn Lexer::next_can_be_plain_scalar(self : Lexer) -> Bool {
  match self.char() {
    // indicators can end a plain scalar, see 7.3.3. Plain Style
    ':' if self.buffer[1].is_blank_or_breakz() ||
      (self.flow_level > 0 && self.buffer[1].is_flow()) => false
    c if self.flow_level > 0 && c.is_flow() => false
    _ => true
  }
}

///|
fn Lexer::fetch_flow_scalar(
  self : Lexer,
  single : Bool,
) -> Unit raise YamlError {
  self.save_simple_key()
  self.disallow_simple_key()
  let tok = self.scan_flow_scalar(single)

  // From spec: To ensure JSON compatibility, if a key inside a flow mapping is JSON-like,
  // YAML allows the following value to be specified adjacent to the “:”.
  self.skip_to_next_token()
  self.adjacent_value_allowed_at = self.index
  self.push_token(tok)
}

///|
fn Lexer::scan_flow_scalar(
  self : Lexer,
  single : Bool,
) -> Token raise YamlError {
  let start_mark = self.get_marker()
  let buf = ScalarBuffer::new(self.scalar_limit)
  let leading_break = ScalarBuffer::new(self.scalar_limit)
  let trailing_breaks = ScalarBuffer::new(self.scalar_limit)
  let whitespaces = ScalarBuffer::new(self.scalar_limit)
  let leading_blanks = Ref(false)
  // The last line of the scalar that was less indented than the block.
  let mut deficient_line = -1

  // Eat the left quote.
  self.skip_non_blank()
  while true {
    // Check for a document indicator.

    self.lookahead(4)
    if self.col == 0 &&
      (
        (
          self.buffer[0] == '-' &&
          self.buffer[1] == '-' &&
          self.buffer[2] == '-'
        ) ||
        (
          self.buffer[0] == '.' &&
          self.buffer[1] == '.' &&
          self.buffer[2] == '.'
        )
      ) &&
      self.buffer[3].is_blank_or_breakz() {
      raise YamlError::YamlError(
        mark=start_mark,
        info="while scanning a quoted scalar, found unexpected document indicator",
      )
    }
    if self.char().is_z() {
      raise YamlError::YamlError(
        mark=start_mark,
        info="while scanning a quoted scalar, found unexpected end of stream",
      )
    }
    // Every line of the scalar is checked here before any of its content or
    // the closing quote is consumed: `consume_flow_scalar_non_whitespace_chars`
    // stops at an escaped line break, and only blanks and line breaks are
    // consumed below.
    if self.col < self.indent {
      // A continuation line (or the line holding the closing quote) is not
      // indented as the enclosing block requires (`s-flow-line-prefix(n)`).
      if !self.lenient_quoted_scalar_indentation {
        raise YamlError::YamlError(
          mark=start_mark,
          info="invalid indentation in quoted scalar",
        )
      }
      deficient_line = self.line
    }
    // The closing quote is only recognised here, after the checks above, so
    // that its line is checked like every other line of the scalar, however
    // it was reached (a folded line break, an escaped line break, ...).
    match self.char() {
      '\'' if single && self.buffer[1] != '\'' => break
      '"' if !single => break
      _ => ()
    }
    leading_blanks.val = false
    self.consume_flow_scalar_non_whitespace_chars(
      single, buf, leading_blanks, start_mark,
    )

    // Consume blank characters.
    while self.char().is_blank() || self.char().is_break() {
      if self.char().is_blank() {
        // Consume a space or a tab character.
        if leading_blanks.val {
          // Without an indentation requirement, all leading white space of
          // a continuation line is separation, and tabs are fine there.
          if self.char() == '\t' &&
            self.col < self.indent &&
            !self.lenient_quoted_scalar_indentation {
            raise YamlError::YamlError(
              mark=self.get_marker(),
              info="tab cannot be used as indentation",
            )
          }
          self.skip_blank()
        } else {
          whitespaces.write_char(self.char())
          self.skip_blank()
        }
      } else {
        self.lookahead(2)
        // Check if it is a first line break.
        if leading_blanks.val {
          self.read_break(trailing_breaks)
        } else {
          whitespaces.reset()
          self.read_break(leading_break)
          leading_blanks.val = true
        }
      }
      self.lookahead(1)
    }

    // Join the whitespaces or fold line breaks.
    if leading_blanks.val {
      if leading_break.is_empty() {
        buf.write_string(leading_break.to_string())
        buf.write_string(trailing_breaks.to_string())
        trailing_breaks.reset()
        leading_break.reset()
      } else {
        if trailing_breaks.is_empty() {
          buf.write_char(' ')
        } else {
          buf.write_string(trailing_breaks.to_string())
          trailing_breaks.reset()
        }
        leading_break.reset()
      }
    } else {
      buf.write_string(whitespaces.to_string())
      whitespaces.reset()
    }
  }

  // Eat the right quote.
  self.skip_non_blank()
  if deficient_line == self.line {
    self.deficient_quoted_line = self.line
  }
  // Ensure there is no invalid trailing content.
  ignore(self.skip_ws_to_eol(SkipTabs::Yes))
  match self.char() {
    // These can be encountered in flow sequences or mappings.
    ',' | '}' | ']' if self.flow_level > 0 => ()
    // An end-of-line / end-of-stream is fine. No trailing content.
    c if c.is_breakz() => ()
    // ':' can be encountered if our scalar is a key.
    // Outside of flow contexts, keys cannot span multiple lines
    ':' if self.flow_level == 0 && start_mark.line == self.line => ()
    // Inside a flow context, this is allowed.
    ':' if self.flow_level > 0 => ()
    _ =>
      raise YamlError::YamlError(
        mark=self.get_marker(),
        info="invalid trailing content after double-quoted scalar",
      )
  }
  let style = if single {
    TScalarStyle::SingleQuoted
  } else {
    TScalarStyle::DoubleQuoted
  }
  Token::{
    marker: start_mark,
    token_type: TokenType::Scalar(style, buf.to_string()),
  }
}

///|
/// Consume successive non-whitespace characters from a flow scalar.
///
/// This function resolves escape sequences and stops upon encountering a whitespace, the end
/// of the stream or the closing character for the scalar (`'` for single quoted scalars, `"`
/// for double quoted scalars).
///
/// # Errors
/// Return an error if an invalid escape sequence is found.
fn Lexer::consume_flow_scalar_non_whitespace_chars(
  self : Lexer,
  single : Bool,
  buf : ScalarBuffer,
  leading_blanks : Ref[Bool],
  start_mark : Marker,
) -> Unit raise YamlError {
  self.lookahead(2)
  while !self.char().is_blank_or_breakz() {
    match self.char() {
      // Check for an escaped single quote.
      '\'' if self.buffer[1] == '\'' && single => {
        buf.write_char('\'')
        self.skip_n_non_blank(2)
      }
      // Check for the right quote.
      '\'' if single => break
      '"' if !single => break
      // Check for an escaped line break.
      '\\' if !single && self.buffer[1].is_break() => {
        self.lookahead(3)
        self.skip_non_blank()
        self.skip_linebreak()
        leading_blanks.val = true
        break
      }
      // Check for an escape sequence.
      '\\' if !single =>
        buf.write_char(self.resolve_flow_scalar_escape_sequence(start_mark))
      c => {
        buf.write_char(c)
        self.skip_non_blank()
      }
    }
    self.lookahead(2)
  }
}

///|
/// Escape the sequence we encounter in a flow scalar.
///
/// `self.ch()` must point to the `\` starting the escape sequence.
///
/// # Errors
/// Return an error if an invalid escape sequence is found.
fn Lexer::resolve_flow_scalar_escape_sequence(
  self : Lexer,
  start_mark : Marker,
) -> Char raise YamlError {
  let mut code_length = 0
  let mut ret = '\u{0}'
  match self.buffer[1] {
    '0' => ret = '\u{0}'
    'a' => ret = '\u{07}'
    'b' => ret = '\u{08}'
    't' | '\t' => ret = '\t'
    'n' => ret = '\n'
    'v' => ret = '\u{0B}'
    'f' => ret = '\u{0C}'
    'r' => ret = '\r'
    'e' => ret = '\u{1B}'
    ' ' => ret = ' '
    '"' => ret = '"'
    '/' => ret = '/'
    '\\' => ret = '\\'
    // Unicode next line (#x85)
    'N' => ret = (0x85).unsafe_to_char()
    // Unicode non-breaking space (#xA0)
    '_' => ret = (0xA0).unsafe_to_char()
    // Unicode line separator (#x2028)
    'L' => ret = (0x2028).unsafe_to_char()
    // Unicode paragraph separator (#x2029)
    'P' => ret = (0x2029).unsafe_to_char()
    'x' => code_length = 2
    'u' => code_length = 4
    'U' => code_length = 8
    _ =>
      raise YamlError::YamlError(
        mark=start_mark,
        info="while parsing a quoted scalar, found unknown escape character",
      )
  }
  self.skip_n_non_blank(2)

  // Consume an arbitrary escape code.
  if code_length > 0 {
    self.lookahead(code_length)
    let mut value : Int32 = 0
    for i in 0..<code_length {
      if !self.buffer[i].is_hex() {
        raise YamlError::YamlError(
          mark=start_mark,
          info="while parsing a quoted scalar, did not find expected hexadecimal number",
        )
      }
      value = (value << 4) + self.buffer[i].as_hex()
    }
    guard value.to_char() is Some(ch) else {
      raise YamlError::YamlError(
        mark=start_mark,
        info="while parsing a quoted scalar, found invalid Unicode character escape code",
      )
    }
    ret = ch
    self.skip_n_non_blank(code_length)
  }
  return ret
}

///|
fn Lexer::fetch_block_scalar(
  self : Lexer,
  literal : Bool,
) -> Unit raise YamlError {
  self.save_simple_key()
  self.allow_simple_key()
  let tok = self.scan_block_scalar(literal)
  self.push_token(tok)
}

///|
fn Lexer::scan_block_scalar(
  self : Lexer,
  literal : Bool,
) -> Token raise YamlError {
  let start_mark = self.get_marker()
  let mut chomping = Chomping::Clip
  let mut increment = 0
  let indent = Ref(0)
  let mut trailing_blank = false
  let mut leading_blank = false
  let style = if literal { TScalarStyle::Literal } else { TScalarStyle::Folded }
  let buf = ScalarBuffer::new(self.scalar_limit)
  let leading_break = ScalarBuffer::new(self.scalar_limit)
  let trailing_breaks = ScalarBuffer::new(self.scalar_limit)
  let chomping_break = ScalarBuffer::new(self.scalar_limit)

  // skip '|' or '>'
  self.skip_non_blank()
  self.unroll_non_block_indents()
  if self.look_char() == '+' || self.char() == '-' {
    if self.char() == '+' {
      chomping = Chomping::Keep
    } else {
      chomping = Chomping::Strip
    }
    self.skip_non_blank()
    if self.look_char().is_ascii_digit() {
      if self.char() == '0' {
        raise YamlError::YamlError(
          mark=start_mark,
          info="while scanning a block scalar, found an indentation indicator equal to 0",
        )
      }
      increment = self.char().to_int() - '0'.to_int()
      self.skip_non_blank()
    }
  } else if self.char().is_ascii_digit() {
    if self.char() == '0' {
      raise YamlError::YamlError(
        mark=start_mark,
        info="while scanning a block scalar, found an indentation indicator equal to 0",
      )
    }
    increment = self.char().to_int() - '0'.to_int()
    self.skip_non_blank()
    self.lookahead(1)
    if self.char() == '+' || self.char() == '-' {
      if self.char() == '+' {
        chomping = Chomping::Keep
      } else {
        chomping = Chomping::Strip
      }
      self.skip_non_blank()
    }
  }
  ignore(self.skip_ws_to_eol(SkipTabs::Yes))

  // Check if we are at the end of the line.
  if !self.look_char().is_breakz() {
    raise YamlError::YamlError(
      mark=start_mark,
      info="while scanning a block scalar, did not find expected comment or line break",
    )
  }
  if self.char().is_break() {
    self.lookahead(2)
    self.read_break(chomping_break)
  }
  if self.look_char() == '\t' {
    raise YamlError::YamlError(
      mark=start_mark,
      info="a block scalar content cannot start with a tab",
    )
  }
  if increment > 0 {
    indent.val = if self.indent >= 0 {
      self.indent + increment
    } else {
      increment
    }
  }

  // Scan the leading line breaks and determine the indentation level if needed.
  if indent.val == 0 {
    self.skip_block_scalar_first_line_indent(indent, trailing_breaks)
  } else {
    self.skip_block_scalar_indent(indent.val, trailing_breaks)
  }

  // We have an end-of-stream with no content, e.g.:
  // ```yaml
  // - |+
  // ```
  if self.char().is_z() {
    let contents = match chomping {
      // We strip trailing linebreaks. Nothing remain.
      Chomping::Strip => ""
      // There was no newline after the chomping indicator
      _ if self.line == start_mark.line => ""
      // We clip lines, and there was a newline after the chomping indicator.
      // All other breaks are ignored.
      Chomping::Clip => chomping_break.to_string()
      // We keep lines. There was a newline after the chomping indicator but nothing
      // else.
      Chomping::Keep if trailing_breaks.is_empty() => chomping_break.to_string()
      // Otherwise, the newline after chomping is ignored.
      Chomping::Keep => trailing_breaks.to_string()
    }
    return Token::{
      marker: start_mark,
      token_type: TokenType::Scalar(style, contents),
    }
  }
  if self.col < indent.val && self.col > self.indent {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="wrongly indented line in block scalar",
    )
  }
  let line_buffer = ScalarBuffer::new(self.scalar_limit)
  let start_mark = self.get_marker()
  while self.col == indent.val && !self.char().is_z() {
    if indent.val == 0 {
      self.lookahead(4)
      if self.next_is_document_end() {
        break
      }
    }

    // We are at the first content character of a content line.
    trailing_blank = self.char().is_blank()
    if !literal &&
      !leading_break.is_empty() &&
      !leading_blank &&
      !trailing_blank {
      buf.write_string(trailing_breaks.to_string())
      if trailing_breaks.is_empty() {
        buf.write_char(' ')
      }
    } else {
      buf.write_string(leading_break.to_string())
      buf.write_string(trailing_breaks.to_string())
    }
    leading_break.reset()
    trailing_breaks.reset()
    leading_blank = self.char().is_blank()
    self.scan_block_scalar_content_line(buf, line_buffer)

    // break on EOF
    if self.char().is_z() {
      break
    }
    self.lookahead(2)
    self.read_break(leading_break)

    // Eat the following indentation spaces and line breaks.
    self.skip_block_scalar_indent(indent.val, trailing_breaks)
  }

  // Chomp the tail.
  if chomping != Chomping::Strip {
    buf.write_string(leading_break.to_string())
    // If we had reached an eof but the last character wasn't an end-of-line, check if the
    // last line was indented at least as the rest of the scalar, then we need to consider
    // there is a newline.
    if self.char().is_z() && self.col >= indent.val.max(1) {
      buf.write_char('\n')
    }
  }
  if chomping == Chomping::Keep {
    buf.write_string(trailing_breaks.to_string())
  }
  Token::{
    marker: start_mark,
    token_type: TokenType::Scalar(style, buf.to_string()),
  }
}

///|
/// Retrieve the contents of the line, parsing it as a block scalar.
///
/// The contents will be appended to `string`. `line_buffer` is used as a temporary buffer to
/// store bytes before pushing them to `string` and thus avoiding reallocating more than
/// necessary. `line_buffer` is assumed to be empty upon calling this function. It will be
/// `clear`ed before the end of the function.
///
/// This function assumed the first character to read is the first content character in the
/// line. This function does not consume the line break character(s) after the line.
fn Lexer::scan_block_scalar_content_line(
  self : Lexer,
  buf : ScalarBuffer,
  line_buffer : ScalarBuffer,
) -> Unit raise YamlError {
  // Start by evaluating characters in the buffer.
  while !self.buffer.is_empty() && !self.char().is_breakz() {
    buf.write_char(self.char())
    // We may technically skip non-blank characters. However, the only distinction is
    // to determine what is leading whitespace and what is not. Here, we read the
    // contents of the line until either eof or a linebreak. We know we will not read
    // `self.leading_whitespace` until the end of the line, where it will be reset.
    // This allows us to call a slightly less expensive function.
    self.skip_blank()
  }

  // All characters that were in the buffer were consumed. We need to check if more
  // follow.
  if self.buffer.is_empty() {
    // We will read all consecutive non-breakz characters. We push them into a temporary buffer.
    let mut line_buffer_size = 0
    let mut c = self.raw_read_char()
    while !c.is_breakz() {
      line_buffer.write_char(c)
      line_buffer_size += 1
      c = self.raw_read_char()
    }

    // Our last character read is stored in `c`. It is either an EOF or a break. In any
    // case, we need to push it back into `self.buffer` so it may be properly read
    // after. We must not insert it in `string`.
    self.buffer.push_back(c)

    // We need to manually update our position; we haven't called a `skip` function.
    self.col += line_buffer_size
    self.index += line_buffer_size
    buf.write_string(line_buffer.to_string())
    line_buffer.reset()
  }
}

///|
/// Skip the block scalar indentation and empty lines.
fn Lexer::skip_block_scalar_indent(
  self : Lexer,
  indent : Int32,
  breaks : ScalarBuffer,
) -> Unit raise YamlError {
  while true {
    // Consume all spaces. Tabs cannot be used as indentation.
    if indent < BUFFER_LEN - 2 {
      self.lookahead(BUFFER_LEN)
      while self.col < indent && self.char() == ' ' {
        self.skip_blank()
      }
    } else {
      while true {
        self.lookahead(BUFFER_LEN)
        while !self.buffer.is_empty() && self.col < indent && self.char() == ' ' {
          self.skip_blank()
        }
        // If we reached our indent, we can break. We must also break if we have
        // reached content or EOF; that is, the buffer is not empty and the next
        // character is not a space.
        if self.col == indent || (!self.buffer.is_empty() && self.char() != ' ') {
          break
        }
      }
      self.lookahead(2)
    }

    // If our current line is empty, skip over the break and continue looping.
    if self.char().is_break() {
      self.read_break(breaks)
    } else {
      // Otherwise, we have a content line. Return control.
      break
    }
  }
}

///|
/// Determine the indentation level for a block scalar from the first line of its contents.
///
/// The function skips over whitespace-only lines and sets `indent` to the the longest
/// whitespace line that was encountered.
fn Lexer::skip_block_scalar_first_line_indent(
  self : Lexer,
  indent : Ref[Int32],
  breaks : ScalarBuffer,
) -> Unit raise YamlError {
  let mut max_indent = 0
  while true {
    // Consume all spaces. Tabs cannot be used as indentation.
    while self.look_char() == ' ' {
      self.skip_blank()
    }
    if self.col > max_indent {
      max_indent = self.col
    }
    if self.char().is_break() {
      // If our current line is empty, skip over the break and continue looping.
      self.lookahead(2)
      self.read_break(breaks)
    } else {
      // Otherwise, we have a content line. Return control.
      break
    }
  }

  // In case a yaml looks like:
  // ```yaml
  // |
  // foo
  // bar
  // ```
  // We need to set the indent to 0 and not 1. In all other cases, the indent must be at
  // least 1. When in the above example, `self.indent` will be set to -1.
  indent.val = max_indent.max(self.indent + 1)
  if self.indent > 0 {
    indent.val = indent.val.max(1)
  }
}

///|
/// Unroll all last indents created with `Self::roll_one_col_indent`.
fn Lexer::unroll_non_block_indents(self : Lexer) -> Unit {
  while self.indents.last() is Some(indent) {
    if indent.needs_block_end {
      break
    }
    self.indent = indent.indent
    ignore(self.indents.pop())
  }
}

///|
fn Lexer::fetch_tag(self : Lexer) -> Unit raise YamlError {
  self.save_simple_key()
  self.disallow_simple_key()
  let tok = self.scan_tag()
  self.push_token(tok)
}

///|
fn Lexer::scan_tag(self : Lexer) -> Token raise YamlError {
  let start_mark = self.get_marker()
  let mut handle = ""
  let mut suffix = ""

  // Check if the tag is in the canonical form (verbatim).
  self.lookahead(2)
  if self.buffer[1] == '<' {
    suffix = self.scan_verbatim_tag(start_mark)
  } else {
    // The tag has either the '!suffix' or the '!handle!suffix'
    handle = self.scan_tag_handle(false, start_mark)
    // Check if it is, indeed, handle.
    if handle.length() >= 2 && handle.has_prefix("!") && handle.has_suffix("!") {
      // A tag handle starting with "!!" is a secondary tag handle.
      let is_secondary_handle = handle == "!!"
      suffix = self.scan_tag_shorthand_suffix(
        false, is_secondary_handle, "", start_mark,
      )
    } else {
      suffix = self.scan_tag_shorthand_suffix(false, false, handle, start_mark)
      handle = "!"
      // A special case: the '!' tag.  Set the handle to '' and the
      // suffix to '!'.
      if suffix.is_empty() {
        handle = ""
        suffix = "!"
      }
    }
  }
  if self.look_char().is_blank_or_breakz() ||
    (self.flow_level > 0 && self.char().is_flow()) {
    // XXX: ex 7.2, an empty scalar can follow a secondary tag
    Token::{ marker: start_mark, token_type: TokenType::Tag(handle~, suffix~), }
  } else {
    raise YamlError::YamlError(
      mark=start_mark,
      info="while scanning a tag, did not find expected whitespace or line break",
    )
  }
}

///|
fn Lexer::scan_tag_shorthand_suffix(
  self : Lexer,
  _directive : Bool,
  _is_secondary : Bool,
  head : String,
  mark : Marker,
) -> String raise YamlError {
  let buf = ScalarBuffer::new(self.scalar_limit)

  // Copy the head if needed.
  // Note that we don't copy the leading '!' character.
  match head {
    [_, .. rest] => buf.write_stringview(rest)
    _ => ()
  }
  let mut length = head.length()
  while self.look_char().is_tag_char() {
    // Check if it is a URI-escape sequence.
    if self.char() == '%' {
      buf.write_char(self.scan_uri_escapes(mark))
    } else {
      buf.write_char(self.char())
      self.skip_non_blank()
    }
    length += 1
  }
  if length == 0 {
    raise YamlError::YamlError(
      mark~,
      info="while parsing a tag, did not find expected tag URI",
    )
  }
  return buf.to_string()
}

///|
/// Scan for a verbatim tag.
///
/// The prefixing `!<` must _not_ have been skipped.
fn Lexer::scan_verbatim_tag(
  self : Lexer,
  start_mark : Marker,
) -> String raise YamlError {
  // Eat `!<`
  self.skip_non_blank()
  self.skip_non_blank()
  let buf = ScalarBuffer::new(self.scalar_limit)
  while self.look_char().is_uri_char() {
    if self.char() == '%' {
      buf.write_char(self.scan_uri_escapes(start_mark))
    } else {
      buf.write_char(self.char())
    }
  }
  if self.char() != '>' {
    raise YamlError::YamlError(
      mark=start_mark,
      info="while scanning a verbatim tag, did not find the expected '>'",
    )
  }
  self.skip_non_blank()
  return buf.to_string()
}

///|
fn Lexer::fetch_anchor(self : Lexer, is_alias : Bool) -> Unit raise YamlError {
  self.save_simple_key()
  self.disallow_simple_key()
  let tok = self.scan_anchor(is_alias)
  self.push_token(tok)
}

///|
fn Lexer::scan_anchor(self : Lexer, is_alias : Bool) -> Token raise YamlError {
  let buf = ScalarBuffer::new(self.scalar_limit)
  let start_mark = self.get_marker()
  self.skip_non_blank()
  while self.look_char().is_anchor_char() {
    buf.write_char(self.char())
    self.skip_non_blank()
  }
  if buf.is_empty() {
    raise YamlError::YamlError(
      mark=start_mark,
      info="while scanning an anchor or alias, did not find expected alphabetic or numeric character",
    )
  }
  if is_alias {
    Token::{
      marker: start_mark,
      token_type: TokenType::Alias(buf.to_string()),
    }
  } else {
    Token::{
      marker: start_mark,
      token_type: TokenType::Anchor(buf.to_string()),
    }
  }
}

///|
/// Fetch a value from a mapping (after a `:`).
fn Lexer::fetch_value(self : Lexer) -> Unit raise YamlError {
  let sk = self.simple_keys.last().unwrap().clone()
  let start_mark = self.get_marker()
  self.implicit_flow_mapping = self.flow_level > 0 && !self.flow_mapping_started

  // Skip over ':'.
  self.skip_non_blank()
  if self.look_char() == '\t' &&
    !self.skip_ws_to_eol(SkipTabs::Yes).has_valid_yaml_ws() &&
    (self.char() == '-' || self.char().is_alpha()) {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="':' must be followed by a valid YAML whitespace",
    )
  }
  if sk.possible {
    // insert simple key
    let tok = Token::{ marker: sk.mark, token_type: TokenType::Key, }
    self.insert_token(sk.token_number - self.tokens_parsed, tok)
    if self.implicit_flow_mapping {
      if sk.mark.line < start_mark.line {
        raise YamlError::YamlError(
          mark=start_mark,
          info="illegal placement of ':' indicator",
        )
      }
      self.insert_token(sk.token_number - self.tokens_parsed, Token::{
        marker: self.get_marker(),
        token_type: TokenType::FlowMappingStart,
      })
    }

    // Add the BLOCK-MAPPING-START token if needed.
    self.roll_indent(
      sk.mark.col,
      Some(sk.token_number),
      TokenType::BlockMappingStart,
      start_mark,
    )
    self.roll_one_col_indent()
    self.simple_keys.last().unwrap().possible = false
    self.disallow_simple_key()
  } else {
    if self.implicit_flow_mapping {
      self.push_token(Token::{
        marker: self.get_marker(),
        token_type: TokenType::FlowMappingStart,
      })
    }

    // The ':' indicator follows a complex key.
    if self.flow_level == 0 {
      if !self.simple_key_allowed {
        raise YamlError::YamlError(
          mark=start_mark,
          info="mapping values are not allowed in this context",
        )
      }
      self.roll_indent(
        start_mark.col,
        None,
        TokenType::BlockMappingStart,
        start_mark,
      )
    }
    self.roll_one_col_indent()
    if self.flow_level == 0 {
      self.allow_simple_key()
    } else {
      self.disallow_simple_key()
    }
  }
  self.push_token(Token::{ marker: start_mark, token_type: TokenType::Value, })
}

///|
fn Lexer::fetch_key(self : Lexer) -> Unit raise YamlError {
  let start_mark = self.get_marker()
  if self.flow_level == 0 {
    // Check if we are allowed to start a new key (not necessarily simple).
    if !self.simple_key_allowed {
      raise YamlError::YamlError(
        mark=self.get_marker(),
        info="mapping keys are not allowed in this context",
      )
    }
    self.roll_indent(
      start_mark.col,
      None,
      TokenType::BlockMappingStart,
      start_mark,
    )
  } else {
    // The parser, upon receiving a `Key`, will insert a `MappingStart` event.

    self.flow_mapping_started = true
  }
  self.remove_simple_key()
  if self.flow_level == 0 {
    self.allow_simple_key()
  } else {
    self.disallow_simple_key()
  }
  self.skip_non_blank()
  self.skip_yaml_whitespace()
  if self.char() == '\t' {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="tabs disallowed in this context",
    )
  }
  self.push_token(Token::{ marker: start_mark, token_type: TokenType::Key, })
}

///|
/// Skip over YAML whitespace (` `, `\n`, `\r`).
///
/// # Errors
/// This function returns an error if no whitespace was found.
fn Lexer::skip_yaml_whitespace(self : Lexer) -> Unit raise YamlError {
  let mut need_whitespace = true
  while true {
    match self.look_char() {
      ' ' => {
        self.skip_blank()
        need_whitespace = false
      }
      '\n' | '\r' => {
        self.lookahead(2)
        self.skip_linebreak()
        if self.flow_level == 0 {
          self.allow_simple_key()
        }
        need_whitespace = false
      }
      '#' =>
        while self.look_char().is_breakz() {
          self.skip_non_blank()
        }
      _ => break
    }
  }
  if need_whitespace {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="expected whitespace",
    )
  }
}

///|
/// Push the `Block*` token(s) and skip over the `-`.
///
/// Add an indentation level and push a `BlockSequenceStart` token if needed, then push a
/// `BlockEntry` token.
/// This function only skips over the `-` and does not fetch the entry value.
fn Lexer::fetch_block_entry(self : Lexer) -> Unit raise YamlError {
  if self.flow_level > 0 {
    // - * only allowed in block
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="'-' is only valid inside a block",
    )
  }

  // Check if we are allowed to start a new entry.
  if !self.simple_key_allowed {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="block sequence entries are not allowed in this context",
    )
  }

  // ???, fixes test G9HC.
  if self.tokens.back() is Some({ marker, token_type: Anchor(_) | Tag(_), }) {
    if self.col == 0 && marker.col == 0 && self.indent > -1 {
      raise YamlError::YamlError(
        mark=marker,
        info="invalid indentation for anchor",
      )
    }
  }

  // Skip over the `-`
  let mark = self.get_marker()
  self.skip_non_blank()

  // generate BLOCK-SEQUENCE-START if indented
  self.roll_indent(mark.col, None, TokenType::BlockSequenceStart, mark)
  let found_tabs = self.skip_ws_to_eol(SkipTabs::Yes).found_tabs()
  self.lookahead(2)
  if found_tabs && self.buffer[0] == '-' && self.buffer[1].is_blank_or_breakz() {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="'-' must be followed by a valid YAML whitespace",
    )
  }
  ignore(self.skip_ws_to_eol(SkipTabs::No))
  if self.look_char().is_break() || self.char().is_flow() {
    self.roll_one_col_indent()
  }
  self.remove_simple_key()
  self.allow_simple_key()
  self.push_token(Token::{
    marker: self.get_marker(),
    token_type: TokenType::BlockEntry,
  })
}

///|
/// Add an indentation level to the stack with the given block token, if needed.
///
/// An indentation level is added only if:
///   - We are not in a flow-style construct (which don't have indentation per-se).
///   - The current column is further indented than the last indent we have registered.
fn Lexer::roll_indent(
  self : Lexer,
  col : Int32,
  number : Int32?,
  tok : TokenType,
  mark : Marker,
) -> Unit raise YamlError {
  if self.flow_level > 0 {
    return
  }

  // If the last indent was a non-block indent, remove it.
  // This means that we prepared an indent that we thought we wouldn't use, but realized just
  // now that it is a block indent.
  if self.indent <= col {
    if self.indents.last() is Some(indent) {
      if !indent.needs_block_end {
        self.indent = indent.indent
        ignore(self.indents.pop())
      }
    }
  }
  if self.indent < col {
    self.check_nesting()
    self.indents.push(Indent::{ indent: self.indent, needs_block_end: true, })
    self.indent = col
    let tokens_parsed = self.tokens_parsed
    match number {
      Some(n) =>
        self.insert_token(n - tokens_parsed, Token::{
          marker: mark,
          token_type: tok,
        })
      None => self.push_token(Token::{ marker: mark, token_type: tok, })
    }
  }
}

///|
/// Push the `FlowEntry` token and skip over the `,`.
fn Lexer::fetch_flow_entry(self : Lexer) -> Unit raise YamlError {
  self.remove_simple_key()
  self.allow_simple_key()
  self.end_implicit_mapping(self.get_marker())
  let start_mark = self.get_marker()
  self.skip_non_blank()
  ignore(self.skip_ws_to_eol(SkipTabs::Yes))
  self.push_token(Token::{
    marker: start_mark,
    token_type: TokenType::FlowEntry,
  })
}

///|
fn Lexer::fetch_flow_collection_end(
  self : Lexer,
  tok : TokenType,
) -> Unit raise YamlError {
  self.remove_simple_key()
  self.decrease_flow_level()
  self.disallow_simple_key()
  self.end_implicit_mapping(self.get_marker())
  let start_mark = self.get_marker()
  self.skip_non_blank()
  ignore(self.skip_ws_to_eol(SkipTabs::Yes))

  // A flow collection within a flow mapping can be a key. In that case, the value may be
  // adjacent to the `:`.
  // ```yaml
  // - [ {a: b}:value ]
  // ```

  if self.flow_level > 0 {
    self.adjacent_value_allowed_at = self.index
  }
  self.push_token(Token::{ marker: start_mark, token_type: tok, })
}

///|
fn Lexer::end_implicit_mapping(
  self : Lexer,
  mark : Marker,
) -> Unit raise YamlError {
  if self.implicit_flow_mapping {
    self.implicit_flow_mapping = false
    self.flow_mapping_started = false
    self.push_token(Token::{
      marker: mark,
      token_type: TokenType::FlowMappingEnd,
    })
  }
}

///|
fn Lexer::decrease_flow_level(self : Lexer) -> Unit {
  if self.flow_level > 0 {
    self.flow_level -= 1
    ignore(self.simple_keys.pop().unwrap())
  }
}

///|
fn Lexer::fetch_flow_collection_start(
  self : Lexer,
  tok : TokenType,
) -> Unit raise YamlError {
  // The indicators '[' and '{' may start a simple key.
  self.save_simple_key()
  self.roll_one_col_indent()
  self.increase_flow_level()
  self.allow_simple_key()
  let start_mark = self.get_marker()
  self.skip_non_blank()
  if tok == TokenType::FlowMappingStart {
    self.flow_mapping_started = true
  }
  ignore(self.skip_ws_to_eol(SkipTabs::Yes))
  self.push_token(Token::{ marker: start_mark, token_type: tok, })
}

///|
fn Lexer::increase_flow_level(self : Lexer) -> Unit raise YamlError {
  self.check_nesting()
  self.simple_keys.push(SimpleKey::new(Marker::{ index: 0, line: 0, col: 0, }))
  self.flow_level = if self.flow_level < 0xFF {
    self.flow_level + 1
  } else {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="recursion limit exceeded",
    )
  }
}

///|
/// Add an indentation level of 1 column that does not start a block.
///
/// See the documentation of `Indent::needs_block_end` for more details.
/// An indentation is not added if we are inside a flow level or if the last indent is already
/// a non-block indent.
fn Lexer::roll_one_col_indent(self : Lexer) -> Unit raise YamlError {
  if self.flow_level == 0 &&
    self.indents.last().map_or(false, indent => indent.needs_block_end) {
    self.check_nesting()
    self.indents.push(Indent::{ indent: self.indent, needs_block_end: false, })
    self.indent += 1
  }
}

///|
fn Lexer::save_simple_key(self : Lexer) -> Unit raise YamlError {
  if self.simple_key_allowed {
    let required = self.flow_level == 0 &&
      self.indent == self.col &&
      self.indents.last().unwrap().needs_block_end
    let sk = SimpleKey::new(self.get_marker())
    sk.possible = true
    sk.required = required
    sk.token_number = self.tokens_parsed + self.tokens.length()
    ignore(self.simple_keys.pop())
    self.check_nesting()
    self.simple_keys.push(sk)
  }
}

///|
fn Lexer::fetch_document_indicator(
  self : Lexer,
  t : TokenType,
) -> Unit raise YamlError {
  self.unroll_indent(-1)
  self.remove_simple_key()
  self.disallow_simple_key()
  let mark = self.get_marker()
  self.skip_n_non_blank(3)
  self.push_token(Token::{ marker: mark, token_type: t, })
}

///|
fn Lexer::fetch_directive(self : Lexer) -> Unit raise YamlError {
  self.unroll_indent(-1)
  self.remove_simple_key()
  self.disallow_simple_key()
  let tok = self.scan_directive()
  self.push_token(tok)
}

///|
fn Lexer::scan_directive(self : Lexer) -> Token raise YamlError {
  let start_mark = self.get_marker()
  self.skip_non_blank()
  let name = self.scan_directive_name()
  let tok = match name {
    "YAML" => self.scan_version_directive_value(start_mark)
    "TAG" => self.scan_tag_directive_value(start_mark)
    // XXX This should be a warning instead of an error
    _ => {
      // skip current line
      while self.look_char().is_breakz() {
        self.skip_non_blank()
      }

      // XXX return an empty TagDirective token

      Token::{
        marker: start_mark,
        token_type: TokenType::TagDirective(handle="", prefix=""),
      }

      // return Err(YamlError::new(start_mark,
      //     "while scanning a directive, found unknown directive name"))
    }
  }
  ignore(self.skip_ws_to_eol(SkipTabs::Yes))
  if self.char().is_breakz() {
    self.lookahead(2)
    self.skip_linebreak()
    return tok
  } else {
    raise YamlError::YamlError(
      mark=start_mark,
      info="while scanning a directive, did not find expected comment or line break",
    )
  }
}

///|
fn Lexer::scan_tag_directive_value(
  self : Lexer,
  mark : Marker,
) -> Token raise YamlError {
  // Eat whitespaces.
  while self.look_char().is_blank() {
    self.skip_blank()
  }
  let handle = self.scan_tag_handle(true, mark)

  // Eat whitespaces.
  while self.look_char().is_blank() {
    self.skip_blank()
  }
  let prefix = self.scan_tag_prefix(mark)
  self.lookahead(1)
  if self.char().is_blank_or_breakz() {
    return Token::{
      marker: mark,
      token_type: TokenType::TagDirective(handle~, prefix~),
    }
  } else {
    raise YamlError::YamlError(
      mark~,
      info="while scanning TAG, did not find expected whitespace or line break",
    )
  }
}

///|
/// Scan for a tag prefix (6.8.2.2).
///
/// There are 2 kinds of tag prefixes:
///   - Local: Starts with a `!`, contains only URI chars (`!foo`)
///   - Global: Starts with a tag char, contains then URI chars (`!foo,2000:app/`)
fn Lexer::scan_tag_prefix(
  self : Lexer,
  start_mark : Marker,
) -> String raise YamlError {
  let buf = ScalarBuffer::new(self.scalar_limit)
  if self.look_char() == '!' {
    // If we have a local tag, insert and skip `!`.
    buf.write_char(self.char())
    self.skip_non_blank()
  } else if !self.char().is_tag_char() {
    // Otherwise, check if the first global tag character is valid.
    raise YamlError::YamlError(
      mark=start_mark,
      info="invalid global tag character",
    )
  } else if self.char() == '%' {
    // If it is valid and an escape sequence, escape it.
    buf.write_char(self.scan_uri_escapes(start_mark))
  } else {
    // Otherwise, push the first character.
    buf.write_char(self.char())
    self.skip_non_blank()
  }
  while self.look_char().is_uri_char() {
    if self.char() == '%' {
      buf.write_char(self.scan_uri_escapes(start_mark))
    } else {
      buf.write_char(self.char())
      self.skip_non_blank()
    }
  }
  return buf.to_string()
}

///|
fn Lexer::scan_uri_escapes(self : Lexer, mark : Marker) -> Char raise YamlError {
  let mut width = 0
  let mut code = 0
  while true {
    self.lookahead(3)
    if !(self.char() == '%' &&
      self.buffer[1].is_hex() &&
      self.buffer[2].is_hex()) {
      raise YamlError::YamlError(
        mark~,
        info="while parsing a tag, did not find URI escaped octet",
      )
    }
    let octet = (self.buffer[1].as_hex() << 4) + self.buffer[2].as_hex()
    if width == 0 {
      width = match octet {
        _ if (octet & 0x80) == 0x00 => 1
        _ if (octet & 0xE0) == 0xC0 => 2
        _ if (octet & 0xF0) == 0xE0 => 3
        _ if (octet & 0xF8) == 0xF0 => 4
        _ =>
          raise YamlError::YamlError(
            mark~,
            info="while parsing a tag, found an incorrect leading UTF-8 octet",
          )
      }
      code = octet
    } else {
      if (octet & 0xc0) != 0x80 {
        raise YamlError::YamlError(
          mark~,
          info="while parsing a tag, found an incorrect trailing UTF-8 octet",
        )
      }
      code = (code << 8) + octet
    }
    self.skip_n_non_blank(3)
    width -= 1
    if width == 0 {
      break
    }
  }
  match Int32::to_char(code) {
    Some(ch) => ch
    None =>
      raise YamlError::YamlError(
        mark~,
        info="while parsing a tag, found an invalid UTF-8 codepoint",
      )
  }
}

///|
fn Lexer::scan_tag_handle(
  self : Lexer,
  directive : Bool,
  mark : Marker,
) -> String raise YamlError {
  let buf = ScalarBuffer::new(self.scalar_limit)
  if self.look_char() != '!' {
    raise YamlError::YamlError(
      mark~,
      info="while scanning a tag, did not find expected '!'",
    )
  }
  buf.write_char(self.char())
  self.skip_non_blank()
  while self.look_char().is_alpha() {
    buf.write_char(self.char())
    self.skip_non_blank()
  }

  // Check if the trailing character is '!' and copy it.
  if self.char() == '!' {
    buf.write_char(self.char())
    self.skip_non_blank()
  } else if directive && buf.to_string() != "!" {
    // It's either the '!' tag or not really a tag handle.  If it's a %TAG
    // directive, it's an error.  If it's a tag token, it must be a part of
    // URI.
    raise YamlError::YamlError(
      mark~,
      info="while parsing a tag directive, did not find expected '!'",
    )
  }
  return buf.to_string()
}

///|
fn Lexer::scan_version_directive_value(
  self : Lexer,
  mark : Marker,
) -> Token raise YamlError {
  while self.look_char().is_blank() {
    self.skip_blank()
  }
  let major = self.scan_version_directive_number(mark)
  if self.char() != '.' {
    raise YamlError::YamlError(
      mark~,
      info="while scanning a YAML directive, did not find expected digit or '.' character",
    )
  }
  self.skip_non_blank()
  let minor = self.scan_version_directive_number(mark)
  Token::{
    marker: mark,
    token_type: TokenType::VersionDirective(major~, minor~),
  }
}

///|
fn Lexer::scan_version_directive_number(
  self : Lexer,
  mark : Marker,
) -> Int32 raise YamlError {
  let mut val = 0
  let mut length = 0
  while self.look_char().to_digit() is Some(digit) {
    if length + 1 > 9 {
      raise YamlError::YamlError(
        mark~,
        info="while scanning a YAML directive, found extremely long version number",
      )
    }
    length += 1
    val = val * 10 + digit
    self.skip_non_blank()
  }
  if length == 0 {
    raise YamlError::YamlError(
      mark~,
      info="while scanning a YAML directive, did not find expected version number",
    )
  }
  return val
}

///|
fn Lexer::scan_directive_name(self : Lexer) -> String raise YamlError {
  let start_mark = self.get_marker()
  let buf = ScalarBuffer::new(self.scalar_limit)
  while self.look_char().is_alpha() {
    buf.write_char(self.char())
    self.skip_non_blank()
  }
  if buf.is_empty() {
    raise YamlError::YamlError(
      mark=start_mark,
      info="while scanning a directive, could not find expected directive name",
    )
  }
  if !self.char().is_blank_or_breakz() {
    raise YamlError::YamlError(
      mark=start_mark,
      info="while scanning a directive, found unexpected non-alphabetical character",
    )
  }
  return buf.to_string()
}

///|
fn Lexer::fetch_stream_end(self : Lexer) -> Unit raise YamlError {
  // force new line
  if self.col != 0 {
    self.col = 0
    self.line += 1
  }
  // If the stream ended, we won't have more context. We can stall all the simple keys we
  // had. If one was required, however, that was an error and we must propagate it.
  for sk in self.simple_keys {
    if sk.required && sk.possible {
      raise YamlError::YamlError(
        mark=self.get_marker(),
        info="simple key expected",
      )
    }
    sk.possible = false
  }
  self.unroll_indent(-1)
  self.remove_simple_key()
  self.disallow_simple_key()
  self.push_token(Token::{
    marker: self.get_marker(),
    token_type: TokenType::StreamEnd,
  })
}

///|
fn Lexer::remove_simple_key(self : Lexer) -> Unit raise YamlError {
  let last = self.simple_keys.last().unwrap()
  if last.possible && last.required {
    raise YamlError::YamlError(
      mark=self.get_marker(),
      info="simple key expected",
    )
  }
  last.possible = false
}

///|
/// Pop indentation levels from the stack as much as needed.
///
/// Indentation levels are popped from the stack while they are further indented than `col`.
/// If we are in a flow-style construct (which don't have indentation per-se), this function
/// does nothing.
fn Lexer::unroll_indent(self : Lexer, col : Int32) -> Unit raise YamlError {
  if self.flow_level > 0 {
    return
  }
  while self.indent > col {
    let indent = self.indents.pop().unwrap()
    self.indent = indent.indent
    if indent.needs_block_end {
      self.push_token(Token::{
        marker: self.get_marker(),
        token_type: TokenType::BlockEnd,
      })
    }
  }
}

///|
/// Mark simple keys that can no longer be keys as such.
///
/// This function sets `possible` to `false` to each key that, now we have more context, we
/// know will not be keys.
///
/// # Errors
/// This function returns an error if one of the key we would stale was required to be a key.
fn Lexer::stale_simple_keys(self : Lexer) -> Unit raise YamlError {
  for sk in self.simple_keys {
    if sk.possible &&
      self.flow_level == 0 &&
      (sk.mark.line < self.line || sk.mark.index + 1024 < self.index) {
      if sk.required {
        raise YamlError::YamlError(
          mark=self.get_marker(),
          info="simple key expect ':'",
        )
      }
      sk.possible = false
    }
  }
}

///|
/// Skip over all whitespace and comments until the next token.
///
/// # Errors
/// This function returns an error if a tabulation is encountered where there should not be
/// one.
fn Lexer::skip_to_next_token(self : Lexer) -> Unit raise YamlError {
  while true {
    match self.look_char() {
      // Tabs may not be used as indentation.
      // "Indentation" only exists as long as a block is started, but does not exist
      // inside of flow-style constructs. Tabs are allowed as part of leading
      // whitespaces outside of indentation.
      // If a flow-style construct is in an indented block, its contents must still be
      // indented. Also, tabs are allowed anywhere in it if it has no content.
      '\t' if self.is_within_block() &&
        self.leading_whitespace &&
        self.col < self.indent => {
        ignore(self.skip_ws_to_eol(SkipTabs::Yes))
        // If we have content on that line with a tab, return an error.
        if !self.char().is_breakz() {
          raise YamlError::YamlError(
            mark=self.get_marker(),
            info="tabs disallowed within this context (block indentation)",
          )
        }
      }
      '\t' | ' ' => self.skip_blank()
      '\n' | '\r' => {
        self.lookahead(2)
        self.skip_linebreak()
        if self.flow_level == 0 {
          self.allow_simple_key()
        }
      }
      '#' =>
        while !self.look_char().is_breakz() {
          self.skip_non_blank()
        }
      _ => break
    }
  }
}

///|
/// Skip yaml whitespace at most up to eol. Also skips comments.
fn Lexer::skip_ws_to_eol(
  self : Lexer,
  skip_tabs : SkipTabs,
) -> SkipTabs raise YamlError {
  let mut encountered_tab = false
  let mut has_onemore_whitespace = false
  while true {
    match self.look_char() {
      ' ' => {
        has_onemore_whitespace = true
        self.skip_blank()
      }
      '\t' if skip_tabs != SkipTabs::No => {
        encountered_tab = true
        self.skip_blank()
      }
      // YAML comments must be preceded by whitespace.
      '#' if !encountered_tab && !has_onemore_whitespace =>
        raise YamlError::YamlError(
          mark=self.get_marker(),
          info="comments must be separated from other tokens by whitespace",
        )
      '#' =>
        while !self.look_char().is_breakz() {
          self.skip_non_blank()
        }
      _ => break
    }
  }
  SkipTabs::Result(encountered_tab~, has_onemore_whitespace~)
}

///|
fn Lexer::is_within_block(self : Lexer) -> Bool {
  !self.indents.is_empty()
}

///|
priv enum SkipTabs {
  /// Skip all tabs as whitespace.
  Yes
  /// Don't skip any tab. Return from the function when encountering one.
  No
  /// Return value from the function.
  /// - `encountered_tab`: Whether tabs were encountered.
  /// - `has_onemore_whitespace`: Whether at least 1 valid yaml whitespace has been encountered.
  Result(encountered_tab~ : Bool, has_onemore_whitespace~ : Bool)
} derive(Eq)

///|
/// Whether tabs were found while skipping whitespace.
///
/// This function must be called after a call to `skip_ws_to_eol`.
fn SkipTabs::found_tabs(self : SkipTabs) -> Bool {
  self is Result(encountered_tab=true, ..)
}

///|
/// Whether a valid YAML whitespace has been found in skipped-over content.
///
/// This function must be called after a call to `skip_ws_to_eol`.
fn SkipTabs::has_valid_yaml_ws(self : SkipTabs) -> Bool {
  self is Result(has_onemore_whitespace=true, ..)
}

///|
/// Chomping, how final line breaks and trailing empty lines are interpreted.
///
/// See YAML spec 8.1.1.2.
priv enum Chomping {
  /// The final line break and any trailing empty lines are excluded.
  Strip
  /// The final line break is preserved, but trailing empty lines are excluded.
  Clip
  /// The final line break and trailing empty lines are included.
  Keep
} derive(Eq)
